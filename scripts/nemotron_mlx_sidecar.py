#!/usr/bin/env python3
import argparse
import json
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from nemotron_sidecar_common import (
    DEFAULT_MODEL_ID,
    peak_memory_mb,
    read_json_body,
    validate_transcription_request,
    write_f32le_wav,
    write_json,
)


def parse_args():
    parser = argparse.ArgumentParser(
        description="Run a Nemotron MLX HTTP sidecar that matches Minto's Swift client contract."
    )
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--model-id", default=DEFAULT_MODEL_ID)
    parser.add_argument("--quantization", default="8bit")
    parser.add_argument("--device", default="mlx")
    parser.add_argument(
        "--force-language",
        default="",
        help="Optional Nemotron prompt key such as en-US. Empty keeps mlx-audio auto detection.",
    )
    parser.add_argument(
        "--preload",
        action="store_true",
        help="Load the MLX model before accepting requests. Default loads on first /transcribe.",
    )
    parser.add_argument(
        "--check-dependencies",
        action="store_true",
        help="Import mlx_audio.stt and exit without loading model weights.",
    )
    parser.add_argument("--verbose", action="store_true")
    return parser.parse_args()


class NemotronMLXState:
    def __init__(self, args):
        self.model_id = args.model_id
        self.quantization = args.quantization
        self.device = args.device
        self.force_language = args.force_language.strip()
        self.verbose = args.verbose
        self.started_at = time.perf_counter()
        self.model = None
        self.model_load_error = None
        self.model_load_elapsed_seconds = None
        self.transcribe_count = 0
        self.model_lock = threading.Lock()
        self.transcribe_lock = threading.Lock()
        dependency = check_dependencies()
        self.dependency_error = None if dependency["ok"] else dependency["error"]

    @property
    def uptime_seconds(self):
        return time.perf_counter() - self.started_at

    @property
    def status(self):
        if self.dependency_error:
            return "error"
        if self.model_load_error:
            return "error"
        if self.model is None:
            return "ok"
        return "ready"

    @property
    def detail(self):
        if self.dependency_error:
            return self.dependency_error
        if self.model_load_error:
            return self.model_load_error
        if self.model is None:
            return "mlx-audio dependency available; model lazy-loaded"
        return "model loaded"

    def health_payload(self):
        return {
            "status": self.status,
            "model_id": self.model_id,
            "quantization": self.quantization,
            "device": self.device,
            "detail": self.detail,
            "uptime_seconds": round(self.uptime_seconds, 6),
            "dependency_available": self.dependency_error is None,
            "model_loaded": self.model is not None,
            "model_load_elapsed_seconds": self.model_load_elapsed_seconds,
            "peak_memory_mb": peak_memory_mb(),
        }

    def ensure_model_loaded(self):
        if self.dependency_error:
            raise RuntimeError(self.dependency_error)
        if self.model is not None:
            return 0.0
        with self.model_lock:
            if self.model is not None:
                return 0.0
            started_at = time.perf_counter()
            try:
                from mlx_audio.stt import load

                self.model = load(self.model_id)
                self.model_load_error = None
            except Exception as error:
                self.model_load_error = f"{type(error).__name__}: {error}"
                raise
            finally:
                self.model_load_elapsed_seconds = time.perf_counter() - started_at
        return self.model_load_elapsed_seconds

    def transcribe(self, audio):
        cold_start_seconds = self.ensure_model_loaded()
        with tempfile.NamedTemporaryFile(suffix=".wav") as wav:
            write_f32le_wav(audio, wav.name)
            kwargs = {}
            if self.force_language:
                kwargs["language"] = self.force_language
            result = self.model.generate(wav.name, **kwargs)
        return {
            "text": text_from_result(result),
            "cold_start_seconds": cold_start_seconds,
        }


def text_from_result(result):
    text = getattr(result, "text", result)
    if text is None:
        return ""
    return str(text).strip()


def check_dependencies():
    try:
        from mlx_audio.stt import load  # noqa: F401
    except Exception as error:
        return {
            "ok": False,
            "error": f"{type(error).__name__}: {error}",
        }
    return {"ok": True}


def make_handler(state):
    class NemotronMLXSidecarHandler(BaseHTTPRequestHandler):
        server_version = "MintoNemotronMLXSidecar/1.0"

        def do_GET(self):
            if self.path != "/health":
                write_json(self, 404, {"error": "not found"})
                return
            status_code = 200 if state.status in ("ok", "ready") else 503
            write_json(self, status_code, state.health_payload())

        def do_POST(self):
            if self.path != "/transcribe":
                write_json(self, 404, {"error": "not found"})
                return
            if not state.transcribe_lock.acquire(blocking=False):
                write_json(self, 429, {"error": "sidecar busy"})
                return
            started_at = time.perf_counter()
            try:
                self.handle_transcribe(started_at)
            finally:
                state.transcribe_lock.release()

        def handle_transcribe(self, started_at):
            try:
                payload = read_json_body(self)
                audio = validate_transcription_request(payload)
            except ValueError as error:
                write_json(self, 400, {"error": str(error)})
                return

            try:
                transcription = state.transcribe(audio)
            except Exception as error:
                write_json(self, 503, {
                    "error": "mlx_transcription_failed",
                    "detail": f"{type(error).__name__}: {error}",
                    "model_id": state.model_id,
                    "peak_memory_mb": peak_memory_mb(),
                })
                return

            state.transcribe_count += 1
            elapsed_seconds = time.perf_counter() - started_at
            audio_seconds = audio["audio_seconds"]
            write_json(self, 200, {
                "text": transcription["text"],
                "model_id": state.model_id,
                "audio_seconds": audio_seconds,
                "elapsed_seconds": elapsed_seconds,
                "rtf": elapsed_seconds / max(audio_seconds, 0.001),
                "peak_memory_mb": peak_memory_mb(),
                "request_id": payload.get("request_id"),
                "sample_count": audio["sample_count"],
                "transcribe_count": state.transcribe_count,
                "cold_start_seconds": transcription["cold_start_seconds"],
                "model_load_elapsed_seconds": state.model_load_elapsed_seconds,
            })

        def log_message(self, format_string, *args):
            if state.verbose:
                super().log_message(format_string, *args)

    return NemotronMLXSidecarHandler


def main():
    args = parse_args()
    if args.check_dependencies:
        result = check_dependencies()
        status_code = 0 if result["ok"] else 1
        print(json.dumps(result, sort_keys=True))
        raise SystemExit(status_code)

    state = NemotronMLXState(args)
    if args.preload:
        try:
            state.ensure_model_loaded()
        except Exception as error:
            print(json.dumps({
                "error": "preload_failed",
                "detail": f"{type(error).__name__}: {error}",
                "model_id": state.model_id,
                "peak_memory_mb": peak_memory_mb(),
            }, sort_keys=True))
            raise SystemExit(1)
    server = ThreadingHTTPServer((args.host, args.port), make_handler(state))
    print(
        f"Nemotron MLX sidecar listening on http://{args.host}:{args.port} "
        f"model={args.model_id} preload={args.preload}",
        flush=True,
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
