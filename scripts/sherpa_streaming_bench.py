#!/usr/bin/env python3
import argparse
import json
import os
import string
import sys
import time
from pathlib import Path

import numpy as np
import soundfile as sf
from huggingface_hub import snapshot_download


SAMPLE_RATE = 16000


def parse_args():
    parser = argparse.ArgumentParser(description="Benchmark sherpa-onnx Korean streaming Zipformer on Minto meeting samples.")
    parser.add_argument("--raw-dir", default="/Users/d66hjkxwt9/Idea/private/minto2/sample/meeting/raw")
    parser.add_argument("--wav", default="haengan_20260526_full.wav")
    parser.add_argument("--smi", default="haengan_20260526_smi.json")
    parser.add_argument("--repo-id", default="kangkyu/icefall-asr-ko-streaming-zipformer-72m")
    parser.add_argument("--model-path", default=os.environ.get("SHERPA_KO_MODEL_PATH", ""))
    parser.add_argument("--download-root", default="/private/tmp/minto2-sherpa-models")
    parser.add_argument("--chunk-size", type=int, default=16, choices=[16, 32, 64])
    parser.add_argument("--audio-chunk-sec", type=float, default=0.64)
    parser.add_argument("--max-seconds", type=float, default=120.0)
    parser.add_argument("--num-threads", type=int, default=2)
    parser.add_argument("--provider", default="cpu")
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def require_sherpa():
    try:
        import sherpa_onnx
    except ImportError as error:
        raise RuntimeError(
            "sherpa_onnx is not installed. Install into a temp target and run with "
            "PYTHONPATH=/private/tmp/minto2-sherpa-python, for example: "
            "python3 -m pip install --target /private/tmp/minto2-sherpa-python sherpa-onnx"
        ) from error
    return sherpa_onnx


def resolve_model_dir(args):
    if args.model_path:
        model_dir = Path(args.model_path).expanduser()
        if not model_dir.exists():
            raise FileNotFoundError(f"--model-path does not exist: {model_dir}")
        return model_dir

    chunk = args.chunk_size
    patterns = [
        "tokens.txt",
        f"encoder-epoch-99-avg-1-chunk-{chunk}-left-128.int8.onnx",
        f"decoder-epoch-99-avg-1-chunk-{chunk}-left-128.int8.onnx",
        f"joiner-epoch-99-avg-1-chunk-{chunk}-left-128.int8.onnx",
    ]
    snapshot = snapshot_download(
        repo_id=args.repo_id,
        allow_patterns=patterns,
        local_dir=args.download_root,
    )
    return Path(snapshot)


def model_files(model_dir, chunk_size):
    return {
        "tokens": model_dir / "tokens.txt",
        "encoder": model_dir / f"encoder-epoch-99-avg-1-chunk-{chunk_size}-left-128.int8.onnx",
        "decoder": model_dir / f"decoder-epoch-99-avg-1-chunk-{chunk_size}-left-128.int8.onnx",
        "joiner": model_dir / f"joiner-epoch-99-avg-1-chunk-{chunk_size}-left-128.int8.onnx",
    }


def validate_files(files):
    missing = [str(path) for path in files.values() if not path.exists()]
    if missing:
        raise FileNotFoundError(f"missing sherpa model files: {missing}")


def read_samples(path):
    samples, rate = sf.read(path, dtype="float32", always_2d=False)
    if rate != SAMPLE_RATE:
        raise ValueError(f"expected 16 kHz WAV, got {rate}: {path}")
    if samples.ndim != 1:
        samples = np.mean(samples, axis=1).astype(np.float32)
    return samples.astype(np.float32)


def parse_smi(path):
    with open(path, "r", encoding="utf-8") as f:
        doc = json.load(f)
    captions = [
        item for item in doc.get("smiList", [])
        if item.get("cc", "").strip()
    ]
    captions.sort(key=lambda item: item["start"])
    return captions


def reference_text(captions, max_seconds):
    texts = []
    for caption in captions:
        if caption["start"] >= max_seconds:
            break
        if caption["end"] <= 0:
            continue
        texts.append(caption["cc"].strip())
    return " ".join(texts)


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


def make_recognizer(sherpa_onnx, files, args):
    return sherpa_onnx.OnlineRecognizer.from_transducer(
        tokens=str(files["tokens"]),
        encoder=str(files["encoder"]),
        decoder=str(files["decoder"]),
        joiner=str(files["joiner"]),
        num_threads=args.num_threads,
        sample_rate=SAMPLE_RATE,
        feature_dim=80,
        enable_endpoint_detection=False,
        decoding_method="greedy_search",
        provider=args.provider,
        modeling_unit="cjkchar",
    )


def run_streaming(recognizer, samples, max_seconds, audio_chunk_sec):
    max_samples = min(len(samples), int(max_seconds * SAMPLE_RATE))
    chunk_samples = max(1, int(audio_chunk_sec * SAMPLE_RATE))
    stream = recognizer.create_stream()
    last_text = ""
    partial_events = 0
    partial_revisions = 0
    first_partial_audio_time = None

    started = time.perf_counter()
    for start in range(0, max_samples, chunk_samples):
        end = min(max_samples, start + chunk_samples)
        stream.accept_waveform(SAMPLE_RATE, samples[start:end])
        while recognizer.is_ready(stream):
            recognizer.decode_stream(stream)
        text = recognizer.get_result(stream)
        audio_time = end / SAMPLE_RATE
        partial_events += 1
        if text and first_partial_audio_time is None:
            first_partial_audio_time = audio_time
        if text != last_text:
            partial_revisions += 1
            last_text = text

    tail_padding = np.zeros(int(0.8 * SAMPLE_RATE), dtype=np.float32)
    stream.accept_waveform(SAMPLE_RATE, tail_padding)
    stream.input_finished()
    while recognizer.is_ready(stream):
        recognizer.decode_stream(stream)
    final_text = recognizer.get_result(stream)
    elapsed = time.perf_counter() - started

    audio_seconds = max_samples / SAMPLE_RATE
    return {
        "final_text": final_text,
        "partial_events": partial_events,
        "partial_revisions": partial_revisions,
        "first_partial_audio_time": first_partial_audio_time,
        "elapsed": elapsed,
        "rtf": elapsed / max(audio_seconds, 0.001),
    }


def main():
    args = parse_args()
    raw_dir = Path(args.raw_dir)
    wav_path = raw_dir / args.wav
    smi_path = raw_dir / args.smi

    if args.dry_run:
        try:
            sherpa_onnx = require_sherpa()
            sherpa_status = getattr(sherpa_onnx, "__version__", "unknown")
        except RuntimeError as error:
            sherpa_status = str(error)
        print(f"sherpa_onnx: {sherpa_status}")
        print(f"raw_dir exists: {raw_dir.exists()} ({raw_dir})")
        print(f"wav exists: {wav_path.exists()} ({wav_path.name})")
        print(f"smi exists: {smi_path.exists()} ({smi_path.name})")
        return 0

    sherpa_onnx = require_sherpa()
    if not wav_path.exists() or not smi_path.exists():
        raise FileNotFoundError(f"missing sample files: {wav_path}, {smi_path}")

    model_dir = resolve_model_dir(args)
    files = model_files(model_dir, args.chunk_size)
    validate_files(files)
    recognizer = make_recognizer(sherpa_onnx, files, args)

    samples = read_samples(wav_path)
    captions = parse_smi(smi_path)
    reference = reference_text(captions, args.max_seconds)
    result = run_streaming(recognizer, samples, args.max_seconds, args.audio_chunk_sec)
    distance, ref_len = cer_stats(reference, result["final_text"])
    cer = distance / max(ref_len, 1)

    print(f"=== sherpa-onnx Korean streaming [{wav_path.name}] ===")
    print(f"repo                   : {args.repo_id}")
    print(f"model_dir              : {model_dir}")
    print(f"chunk_size             : {args.chunk_size}")
    print(f"audio seconds          : {min(args.max_seconds, len(samples) / SAMPLE_RATE):.1f}")
    print(f"audio chunk seconds    : {args.audio_chunk_sec:.2f}")
    print(f"partial events         : {result['partial_events']}")
    print(f"partial revisions      : {result['partial_revisions']}")
    print(f"first partial latency  : {result['first_partial_audio_time']}")
    print(f"elapsed seconds        : {result['elapsed']:.2f}")
    print(f"RTF                    : {result['rtf']:.3f}")
    print(f"global CER             : {cer * 100:.1f}% (distance {distance} / ref {ref_len})")
    print(f"final text             : {result['final_text'][:500]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
