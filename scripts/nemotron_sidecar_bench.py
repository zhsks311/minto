#!/usr/bin/env python3
import argparse
import base64
import json
import statistics
import string
import struct
import sys
import time
import urllib.error
import urllib.request
import wave
from datetime import datetime
from pathlib import Path


SAMPLE_RATE = 16000
MAX_GAP_SECONDS = 1.5


def parse_args():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(
        description="Benchmark a running Nemotron HTTP sidecar on sample/meeting WAV+SMI pairs."
    )
    parser.add_argument("--raw-dir", type=Path, default=root / "sample/meeting/raw")
    parser.add_argument("--base-url", default="http://127.0.0.1:8765")
    parser.add_argument("--output-root", type=Path, default=None)
    parser.add_argument(
        "--samples",
        default="",
        help="Comma-separated sample ids without _full.wav. Empty means all pairs.",
    )
    parser.add_argument("--window-sec", type=float, default=60.0)
    parser.add_argument(
        "--max-windows",
        type=int,
        default=0,
        help="0 means all merged caption windows.",
    )
    parser.add_argument(
        "--max-seconds",
        type=float,
        default=0,
        help="0 means full sample. Positive values stop before captions starting after this time.",
    )
    parser.add_argument("--language", default="ko")
    parser.add_argument("--timeout", type=float, default=120.0)
    parser.add_argument("--list-samples", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--fail-fast", action="store_true")
    return parser.parse_args()


class MeetingWavReader:
    def __init__(self, path):
        self.path = Path(path)
        self.handle = wave.open(str(path), "rb")
        self.channels = self.handle.getnchannels()
        self.sample_rate = self.handle.getframerate()
        self.sample_width = self.handle.getsampwidth()
        self.total_frames = self.handle.getnframes()
        if self.sample_rate != SAMPLE_RATE:
            raise ValueError(f"expected 16 kHz WAV, got {self.sample_rate}: {path}")
        if self.channels <= 0:
            raise ValueError(f"invalid channel count: {self.channels}")
        if self.sample_width not in (1, 2, 4):
            raise ValueError(f"unsupported sample width: {self.sample_width}")

    @property
    def duration_seconds(self):
        return self.total_frames / self.sample_rate

    def read_f32le_window(self, start_seconds, end_seconds):
        start_frame = max(0, min(self.total_frames, int(start_seconds * self.sample_rate)))
        end_frame = max(start_frame, min(self.total_frames, int(end_seconds * self.sample_rate)))
        frame_count = end_frame - start_frame
        if frame_count <= 0:
            return b"", 0.0, 0

        self.handle.setpos(start_frame)
        raw = self.handle.readframes(frame_count)
        samples = bytearray()
        frame_size = self.sample_width * self.channels
        for offset in range(0, len(raw), frame_size):
            total = 0.0
            for channel in range(self.channels):
                sample_offset = offset + (channel * self.sample_width)
                total += self._sample_to_float(raw, sample_offset)
            samples.extend(struct.pack("<f", total / self.channels))

        audio_seconds = frame_count / self.sample_rate
        return bytes(samples), audio_seconds, frame_count

    def _sample_to_float(self, raw, offset):
        if self.sample_width == 1:
            value = raw[offset] - 128
            return value / 128.0
        if self.sample_width == 2:
            value = struct.unpack_from("<h", raw, offset)[0]
            return value / 32768.0
        value = struct.unpack_from("<i", raw, offset)[0]
        return value / 2147483648.0

    def close(self):
        self.handle.close()

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        self.close()


def sample_pairs(raw_dir):
    pairs = []
    for wav in sorted(raw_dir.glob("*_full.wav")):
        sample_id = wav.name.removesuffix("_full.wav")
        smi = raw_dir / f"{sample_id}_smi.json"
        if smi.exists():
            pairs.append((sample_id, wav, smi))
    return pairs


def selected_pairs(raw_dir, requested_samples):
    pairs = sample_pairs(raw_dir)
    if not requested_samples:
        return pairs
    requested = {value.strip() for value in requested_samples.split(",") if value.strip()}
    selected = [pair for pair in pairs if pair[0] in requested]
    missing = sorted(requested - {pair[0] for pair in selected})
    if missing:
        raise SystemExit(f"Missing sample ids in {raw_dir}: {', '.join(missing)}")
    return selected


def parse_smi(path):
    with open(path, "r", encoding="utf-8") as handle:
        doc = json.load(handle)
    captions = [
        item for item in doc.get("smiList", [])
        if item.get("cc", "").strip()
    ]
    captions.sort(key=lambda item: item["start"])
    return captions


def merge_windows(captions, window_sec, max_seconds):
    windows = []
    bucket = []

    def flush():
        nonlocal bucket
        if not bucket:
            return
        windows.append({
            "start": bucket[0]["start"],
            "end": bucket[-1]["end"],
            "text": " ".join(item["cc"].strip() for item in bucket),
        })
        bucket = []

    for caption in captions:
        if max_seconds > 0 and caption["start"] >= max_seconds:
            break
        if bucket and caption["start"] - bucket[-1]["end"] > MAX_GAP_SECONDS:
            flush()
        bucket.append(caption)
        if caption["end"] - bucket[0]["start"] >= window_sec:
            flush()
    flush()
    return windows


def get_health(base_url, timeout):
    try:
        with urllib.request.urlopen(f"{base_url}/health", timeout=timeout) as response:
            return {
                "http_status": response.status,
                "body": decode_json_bytes(response.read()),
            }
    except urllib.error.HTTPError as error:
        return {
            "http_status": error.code,
            "body": decode_json_bytes(error.read()),
        }
    except urllib.error.URLError as error:
        return {
            "http_status": None,
            "body": {
                "error": "url_error",
                "detail": str(error),
            },
        }


def transcribe_window(base_url, timeout, language, request_id, f32le_audio, audio_seconds):
    payload = {
        "schema_version": 1,
        "request_id": request_id,
        "language": language,
        "sample_rate": SAMPLE_RATE,
        "audio_format": "f32le",
        "audio_base64": base64.b64encode(f32le_audio).decode("ascii"),
        "audio_seconds": audio_seconds,
    }
    body = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        f"{base_url}/transcribe",
        data=body,
        headers={
            "Accept": "application/json",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    started_at = time.perf_counter()
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            elapsed = time.perf_counter() - started_at
            return {
                "ok": True,
                "http_status": response.status,
                "client_elapsed_seconds": elapsed,
                "body": decode_json_bytes(response.read()),
            }
    except urllib.error.HTTPError as error:
        elapsed = time.perf_counter() - started_at
        return {
            "ok": False,
            "http_status": error.code,
            "client_elapsed_seconds": elapsed,
            "body": decode_json_bytes(error.read()),
        }
    except urllib.error.URLError as error:
        elapsed = time.perf_counter() - started_at
        return {
            "ok": False,
            "http_status": None,
            "client_elapsed_seconds": elapsed,
            "body": {
                "error": "url_error",
                "detail": str(error),
            },
        }


def decode_json_bytes(raw):
    text = raw.decode("utf-8", errors="replace")
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return {"raw": text}


def normalize_chars(text):
    punctuation = set(string.punctuation)
    return [ch for ch in text if not ch.isspace() and ch not in punctuation and not _is_unicode_punctuation(ch)]


def _is_unicode_punctuation(ch):
    return ch in "。、，．！？：；「」『』（）()[]【】《》〈〉·…"


def edit_distance(a, b):
    if not a:
        return len(b)
    if not b:
        return len(a)
    dp = list(range(len(b) + 1))
    for i, ca in enumerate(a, start=1):
        prev = dp[0]
        dp[0] = i
        for j, cb in enumerate(b, start=1):
            old = dp[j]
            if ca == cb:
                dp[j] = prev
            else:
                dp[j] = min(prev, dp[j], dp[j - 1]) + 1
            prev = old
    return dp[-1]


def cer_stats(reference, hypothesis):
    ref = normalize_chars(reference)
    hyp = normalize_chars(hypothesis)
    return edit_distance(ref, hyp), len(ref)


def percentile(values, ratio):
    if not values:
        return None
    sorted_values = sorted(values)
    index = int((len(sorted_values) - 1) * ratio)
    return sorted_values[index]


def safe_path(value):
    sanitized = "".join(
        "_" if ch in "/\\" or ord(ch) < 32 else ch
        for ch in value
    ).strip()
    return sanitized or "unknown"


def default_output_root(root):
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    return root / "tmp" / "nemotron-sidecar-benchmarks" / timestamp


def write_json_file(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True),
        encoding="utf-8",
    )


def benchmark_sample(args, sample_id, wav_path, smi_path, output_root):
    captions = parse_smi(smi_path)
    windows = merge_windows(captions, args.window_sec, args.max_seconds)
    if args.max_windows > 0:
        windows = windows[:args.max_windows]

    window_results = []
    total_distance = 0
    total_ref_len = 0
    all_reference = []
    all_hypothesis = []
    error_count = 0
    empty_count = 0
    client_latencies = []
    server_rtfs = []
    peak_memory_values = []

    with MeetingWavReader(wav_path) as reader:
        print(f"==> sample={sample_id} duration={reader.duration_seconds:.1f}s windows={len(windows)}")
        for index, window in enumerate(windows):
            f32le_audio, audio_seconds, sample_count = reader.read_f32le_window(
                window["start"],
                window["end"],
            )
            request_id = f"{sample_id}-{index:04d}"
            result = transcribe_window(
                args.base_url.rstrip("/"),
                args.timeout,
                args.language,
                request_id,
                f32le_audio,
                audio_seconds,
            )
            body = result["body"]
            text = body.get("text", "").strip() if result["ok"] else ""
            distance, ref_len = cer_stats(window["text"], text)
            cer = distance / ref_len if ref_len else 0

            total_distance += distance
            total_ref_len += ref_len
            all_reference.append(window["text"])
            all_hypothesis.append(text)
            client_latencies.append(result["client_elapsed_seconds"])
            if result["ok"] and "rtf" in body:
                server_rtfs.append(body["rtf"])
            if result["ok"] and body.get("peak_memory_mb") is not None:
                peak_memory_values.append(body["peak_memory_mb"])
            if not result["ok"]:
                error_count += 1
            if not text:
                empty_count += 1

            window_result = {
                "index": index,
                "request_id": request_id,
                "start": window["start"],
                "end": window["end"],
                "audio_seconds": audio_seconds,
                "sample_count": sample_count,
                "reference": window["text"],
                "hypothesis": text,
                "cer": cer,
                "edit_distance": distance,
                "reference_length": ref_len,
                "ok": result["ok"],
                "http_status": result["http_status"],
                "client_elapsed_seconds": result["client_elapsed_seconds"],
                "response": body,
            }
            window_results.append(window_result)
            print(
                f"[sidecar] {sample_id} #{index:03d} "
                f"{window['start']:7.1f}-{window['end']:7.1f}s "
                f"ok={result['ok']} CER={cer * 100:5.1f}% "
                f"client={result['client_elapsed_seconds']:.2f}s text={text[:80]}"
            )
            if args.fail_fast and not result["ok"]:
                break

    global_distance, global_ref_len = cer_stats(" ".join(all_reference), " ".join(all_hypothesis))
    sample_result = {
        "schema_version": 1,
        "sample_id": sample_id,
        "wav": str(wav_path),
        "smi": str(smi_path),
        "base_url": args.base_url,
        "window_sec": args.window_sec,
        "max_windows": args.max_windows,
        "max_seconds": args.max_seconds,
        "window_count": len(window_results),
        "error_count": error_count,
        "empty_count": empty_count,
        "micro_cer": total_distance / max(total_ref_len, 1),
        "global_cer": global_distance / max(global_ref_len, 1),
        "edit_distance_total": total_distance,
        "reference_length_total": total_ref_len,
        "global_edit_distance": global_distance,
        "global_reference_length": global_ref_len,
        "client_latency_seconds": {
            "mean": statistics.fmean(client_latencies) if client_latencies else None,
            "p50": percentile(client_latencies, 0.50),
            "p95": percentile(client_latencies, 0.95),
        },
        "server_rtf": {
            "mean": statistics.fmean(server_rtfs) if server_rtfs else None,
            "p50": percentile(server_rtfs, 0.50),
            "p95": percentile(server_rtfs, 0.95),
        },
        "peak_memory_mb": max(peak_memory_values) if peak_memory_values else None,
        "windows": window_results,
    }
    write_json_file(output_root / f"{safe_path(sample_id)}.json", sample_result)
    return sample_result


def summarize(results, health_before, health_after, output_root):
    total_distance = sum(result["edit_distance_total"] for result in results)
    total_ref_len = sum(result["reference_length_total"] for result in results)
    global_distance = sum(result["global_edit_distance"] for result in results)
    global_ref_len = sum(result["global_reference_length"] for result in results)
    window_count = sum(result["window_count"] for result in results)
    error_count = sum(result["error_count"] for result in results)
    empty_count = sum(result["empty_count"] for result in results)
    peak_values = [
        result["peak_memory_mb"] for result in results
        if result["peak_memory_mb"] is not None
    ]
    rtf_values = [
        window["response"]["rtf"]
        for result in results
        for window in result["windows"]
        if window["ok"] and "rtf" in window["response"]
    ]
    client_values = [
        window["client_elapsed_seconds"]
        for result in results
        for window in result["windows"]
    ]
    summary = {
        "schema_version": 1,
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "output_root": str(output_root),
        "health_before": health_before,
        "health_after": health_after,
        "sample_count": len(results),
        "window_count": window_count,
        "error_count": error_count,
        "empty_count": empty_count,
        "micro_cer": total_distance / max(total_ref_len, 1),
        "global_cer": global_distance / max(global_ref_len, 1),
        "edit_distance_total": total_distance,
        "reference_length_total": total_ref_len,
        "client_latency_seconds": {
            "mean": statistics.fmean(client_values) if client_values else None,
            "p50": percentile(client_values, 0.50),
            "p95": percentile(client_values, 0.95),
        },
        "server_rtf": {
            "mean": statistics.fmean(rtf_values) if rtf_values else None,
            "p50": percentile(rtf_values, 0.50),
            "p95": percentile(rtf_values, 0.95),
        },
        "peak_memory_mb": max(peak_values) if peak_values else None,
        "samples": [
            {
                "sample_id": result["sample_id"],
                "window_count": result["window_count"],
                "micro_cer": result["micro_cer"],
                "global_cer": result["global_cer"],
                "error_count": result["error_count"],
                "empty_count": result["empty_count"],
                "peak_memory_mb": result["peak_memory_mb"],
            }
            for result in results
        ],
    }
    write_json_file(output_root / "summary.json", summary)
    return summary


def main():
    args = parse_args()
    raw_dir = args.raw_dir.expanduser().resolve()
    pairs = selected_pairs(raw_dir, args.samples)

    if args.list_samples:
        for sample_id, wav_path, smi_path in pairs:
            print(f"{sample_id}\t{wav_path.name}\t{smi_path.name}")
        return 0

    if not pairs:
        raise SystemExit(f"No *_full.wav + *_smi.json pairs found in {raw_dir}")

    root = Path(__file__).resolve().parents[1]
    output_root = (args.output_root or default_output_root(root)).expanduser().resolve()
    output_root.mkdir(parents=True, exist_ok=True)

    if args.dry_run:
        print(f"raw_dir={raw_dir}")
        print(f"base_url={args.base_url}")
        print(f"output_root={output_root}")
        for sample_id, wav_path, smi_path in pairs:
            print(f"{sample_id}\t{wav_path.name}\t{smi_path.name}")
        return 0

    health_before = get_health(args.base_url.rstrip("/"), args.timeout)
    results = []
    for sample_id, wav_path, smi_path in pairs:
        result = benchmark_sample(args, sample_id, wav_path, smi_path, output_root)
        results.append(result)
        if args.fail_fast and result["error_count"] > 0:
            break
    health_after = get_health(args.base_url.rstrip("/"), args.timeout)
    summary = summarize(results, health_before, health_after, output_root)

    print("=== Nemotron Sidecar Benchmark Summary ===")
    print(f"output_root       : {output_root}")
    print(f"samples/windows   : {summary['sample_count']} / {summary['window_count']}")
    print(f"errors/empty      : {summary['error_count']} / {summary['empty_count']}")
    print(f"micro/global CER  : {summary['micro_cer'] * 100:.2f}% / {summary['global_cer'] * 100:.2f}%")
    print(f"RTF mean/p95      : {summary['server_rtf']['mean']} / {summary['server_rtf']['p95']}")
    print(f"peak memory MB    : {summary['peak_memory_mb']}")
    return 0 if summary["error_count"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
