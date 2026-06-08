import base64
import binascii
import json
import math
import resource
import struct
import wave


DEFAULT_MODEL_ID = "mlx-community/nemotron-3.5-asr-streaming-0.6b-8bit"


def read_json_body(handler):
    content_length = handler.headers.get("Content-Length")
    if content_length is None:
        raise ValueError("Content-Length is required")
    try:
        length = int(content_length)
    except ValueError as error:
        raise ValueError("Content-Length must be an integer") from error
    if length <= 0:
        raise ValueError("request body is empty")
    raw_body = handler.rfile.read(length)
    try:
        return json.loads(raw_body.decode("utf-8"))
    except json.JSONDecodeError as error:
        raise ValueError(f"invalid JSON body: {error.msg}") from error


def write_json(handler, status_code, payload):
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    handler.send_response(status_code)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(body)))
    handler.end_headers()
    handler.wfile.write(body)


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

    language = require_string(payload, "language")
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
        "audio_bytes": audio_bytes,
        "audio_seconds": float(audio_seconds),
        "language": language,
        "sample_count": sample_count,
        "sample_rate": sample_rate,
    }


def write_f32le_wav(audio, path):
    pcm16 = bytearray()
    for (sample,) in struct.iter_unpack("<f", audio["audio_bytes"]):
        if not math.isfinite(sample):
            sample = 0.0
        sample = max(-1.0, min(1.0, sample))
        pcm16.extend(struct.pack("<h", int(sample * 32767)))

    with wave.open(path, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(audio["sample_rate"])
        wav.writeframes(bytes(pcm16))


def peak_memory_mb():
    usage = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    if usage <= 0:
        return None
    # macOS reports bytes, Linux reports KiB.
    if usage > 1024 * 1024 * 10:
        return usage / 1024 / 1024
    return usage / 1024


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
