#!/usr/bin/env python3
import argparse
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from nemotron_sidecar_common import (
    DEFAULT_MODEL_ID,
    peak_memory_mb,
    read_json_body,
    validate_transcription_request,
    write_json,
)


def parse_args():
    parser = argparse.ArgumentParser(
        description="Run a dependency-free Nemotron sidecar mock for Swift client contract tests."
    )
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--text", default="nemotron sidecar mock transcript")
    parser.add_argument("--delay-ms", type=int, default=0)
    parser.add_argument("--status", default="ready", choices=["ready", "ok", "warming", "error"])
    parser.add_argument("--http-status", type=int, default=200)
    parser.add_argument("--model-id", default=DEFAULT_MODEL_ID)
    parser.add_argument("--quantization", default="8bit")
    parser.add_argument("--device", default="mock")
    parser.add_argument("--verbose", action="store_true")
    return parser.parse_args()


class MockState:
    def __init__(self, args):
        self.text = args.text
        self.delay_seconds = max(args.delay_ms, 0) / 1000
        self.status = args.status
        self.http_status = args.http_status
        self.model_id = args.model_id
        self.quantization = args.quantization
        self.device = args.device
        self.verbose = args.verbose
        self.started_at = time.perf_counter()
        self.transcribe_count = 0

    @property
    def is_ready(self):
        return self.status in ("ready", "ok") and 200 <= self.http_status < 300

    @property
    def uptime_seconds(self):
        return time.perf_counter() - self.started_at


def make_handler(state):
    class NemotronSidecarMockHandler(BaseHTTPRequestHandler):
        server_version = "MintoNemotronSidecarMock/1.0"

        def do_GET(self):
            if self.path != "/health":
                write_json(self, 404, {"error": "not found"})
                return
            payload = {
                "status": state.status,
                "model_id": state.model_id,
                "quantization": state.quantization,
                "device": state.device,
                "detail": "mock worker",
                "uptime_seconds": round(state.uptime_seconds, 6),
            }
            write_json(self, state.http_status, payload)

        def do_POST(self):
            if self.path != "/transcribe":
                write_json(self, 404, {"error": "not found"})
                return
            if not state.is_ready:
                status_code = state.http_status if state.http_status >= 300 else 503
                write_json(self, status_code, {"error": state.status})
                return

            started_at = time.perf_counter()
            try:
                payload = read_json_body(self)
                audio = validate_transcription_request(payload)
            except ValueError as error:
                write_json(self, 400, {"error": str(error)})
                return

            if state.delay_seconds > 0:
                time.sleep(state.delay_seconds)

            state.transcribe_count += 1
            elapsed_seconds = time.perf_counter() - started_at
            audio_seconds = audio["audio_seconds"]
            response = {
                "text": state.text,
                "model_id": state.model_id,
                "audio_seconds": audio_seconds,
                "elapsed_seconds": elapsed_seconds,
                "rtf": elapsed_seconds / max(audio_seconds, 0.001),
                "peak_memory_mb": peak_memory_mb(),
                "request_id": payload.get("request_id"),
                "sample_count": audio["sample_count"],
                "transcribe_count": state.transcribe_count,
            }
            write_json(self, 200, response)

        def log_message(self, format_string, *args):
            if state.verbose:
                super().log_message(format_string, *args)

    return NemotronSidecarMockHandler


def main():
    args = parse_args()
    state = MockState(args)
    server = ThreadingHTTPServer((args.host, args.port), make_handler(state))
    print(
        f"Nemotron sidecar mock listening on http://{args.host}:{args.port} "
        f"status={args.status} model={args.model_id}",
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
