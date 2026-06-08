#!/usr/bin/env python3
import argparse
import base64
import binascii
import json
import resource
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


DEFAULT_MODEL_ID = "mlx-community/nemotron-3.5-asr-streaming-0.6b-8bit"


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
                self.write_json(404, {"error": "not found"})
                return
            payload = {
                "status": state.status,
                "model_id": state.model_id,
                "quantization": state.quantization,
                "device": state.device,
                "detail": "mock worker",
                "uptime_seconds": round(state.uptime_seconds, 6),
            }
            self.write_json(state.http_status, payload)

        def do_POST(self):
            if self.path != "/transcribe":
                self.write_json(404, {"error": "not found"})
                return
            if not state.is_ready:
                status_code = state.http_status if state.http_status >= 300 else 503
                self.write_json(status_code, {"error": state.status})
                return

            started_at = time.perf_counter()
            try:
                payload = self.read_json_body()
                audio = validate_transcription_request(payload)
            except ValueError as error:
                self.write_json(400, {"error": str(error)})
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
            self.write_json(200, response)

        def read_json_body(self):
            content_length = self.headers.get("Content-Length")
            if content_length is None:
                raise ValueError("Content-Length is required")
            try:
                length = int(content_length)
            except ValueError as error:
                raise ValueError("Content-Length must be an integer") from error
            if length <= 0:
                raise ValueError("request body is empty")
            raw_body = self.rfile.read(length)
            try:
                return json.loads(raw_body.decode("utf-8"))
            except json.JSONDecodeError as error:
                raise ValueError(f"invalid JSON body: {error.msg}") from error

        def write_json(self, status_code, payload):
            body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
            self.send_response(status_code)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, format_string, *args):
            if state.verbose:
                super().log_message(format_string, *args)

    return NemotronSidecarMockHandler


def validate_transcription_request(payload):
    schema_version = require_int(payload, "schema_version")
    if schema_version != 1:
        raise ValueError(f"unsupported schema_version: {schema_version}")

    sample_rate = require_int(payload, "sample_rate")
    if sample_rate <= 0:
        raise ValueError("sample_rate must be positive")

    audio_format = require_string(payload, "audio_format")
    if audio_format != "f32le":
        raise ValueError(f"unsupported audio_format: {audio_format}")

    require_string(payload, "language")
    audio_base64 = require_string(payload, "audio_base64")
    try:
        audio_bytes = base64.b64decode(audio_base64, validate=True)
    except binascii.Error as error:
        raise ValueError("audio_base64 is not valid base64") from error

    if not audio_bytes:
        raise ValueError("audio_base64 is empty")
    if len(audio_bytes) % 4 != 0:
        raise ValueError("f32le audio byte length must be divisible by 4")

    sample_count = len(audio_bytes) // 4
    audio_seconds = payload.get("audio_seconds")
    if audio_seconds is None:
        audio_seconds = sample_count / sample_rate
    if not isinstance(audio_seconds, (int, float)) or audio_seconds < 0:
        raise ValueError("audio_seconds must be a non-negative number")

    expected_seconds = sample_count / sample_rate
    if abs(float(audio_seconds) - expected_seconds) > 0.01:
        raise ValueError(
            f"audio_seconds does not match payload length: {audio_seconds} vs {expected_seconds:.6f}"
        )

    return {
        "sample_count": sample_count,
        "audio_seconds": float(audio_seconds),
    }


def require_int(payload, key):
    value = payload.get(key)
    if not isinstance(value, int):
        raise ValueError(f"{key} must be an integer")
    return value


def require_string(payload, key):
    value = payload.get(key)
    if not isinstance(value, str) or not value:
        raise ValueError(f"{key} must be a non-empty string")
    return value


def peak_memory_mb():
    usage = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    if usage <= 0:
        return None
    # macOS reports bytes, Linux reports KiB.
    if usage > 1024 * 1024 * 10:
        return usage / 1024 / 1024
    return usage / 1024


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
