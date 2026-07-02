#!/usr/bin/env python3
import argparse
import json
import math
import os
import string
import sys
import time
from pathlib import Path

import numpy as np
import soundfile as sf
from faster_whisper import WhisperModel
from huggingface_hub import list_repo_files, snapshot_download


SAMPLE_RATE = 16000
MAX_GAP_SECONDS = 1.5


def parse_args():
    parser = argparse.ArgumentParser(description="Benchmark BatiSay CT2 with faster-whisper on Minto meeting samples.")
    parser.add_argument("--raw-dir", default="~/Idea/private/minto2/sample/meeting/raw")
    parser.add_argument("--wav", default="haengan_20260526_full.wav")
    parser.add_argument("--smi", default="haengan_20260526_smi.json")
    parser.add_argument("--repo-id", default="batiai/batisay-ko-base")
    parser.add_argument("--model-path", default=os.environ.get("BATISAY_MODEL_PATH", ""))
    parser.add_argument("--download-root", default="/private/tmp/minto2-batisay-models")
    parser.add_argument("--window-sec", type=float, default=20.0)
    parser.add_argument("--max-windows", type=int, default=60)
    parser.add_argument("--compute-type", default="int8")
    parser.add_argument("--beam-size", type=int, default=1)
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def resolve_model_path(args):
    if args.model_path:
        model_path = Path(args.model_path).expanduser()
        if not model_path.exists():
            raise FileNotFoundError(f"--model-path does not exist: {model_path}")
        return model_path

    repo_files = list_repo_files(args.repo_id)
    ct2_files = [path for path in repo_files if path.startswith("ct2/")]
    if not ct2_files:
        preview = ", ".join(repo_files[:20])
        raise FileNotFoundError(
            f"{args.repo_id} currently exposes no ct2/ files via huggingface_hub. "
            f"Visible files: {preview}. Provide --model-path if you have a local CT2 export."
        )

    snapshot = snapshot_download(
        repo_id=args.repo_id,
        allow_patterns=["ct2/**"],
        local_dir=args.download_root,
    )
    model_path = Path(snapshot) / "ct2"
    if not model_path.exists():
        raise FileNotFoundError(f"ct2 folder not found after download: {model_path}")
    return model_path


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


def merge_windows(captions, window_sec):
    windows = []
    bucket = []

    def flush():
        nonlocal bucket
        if not bucket:
            return
        text = " ".join(item["cc"].strip() for item in bucket)
        windows.append({
            "start": bucket[0]["start"],
            "end": bucket[-1]["end"],
            "text": text,
        })
        bucket = []

    for caption in captions:
        if bucket and caption["start"] - bucket[-1]["end"] > MAX_GAP_SECONDS:
            flush()
        bucket.append(caption)
        if caption["end"] - bucket[0]["start"] >= window_sec:
            flush()
    flush()
    return windows


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


def transcribe_window(model, samples, start, end, beam_size):
    start_sample = max(0, int(start * SAMPLE_RATE))
    end_sample = min(len(samples), int(end * SAMPLE_RATE))
    if end_sample <= start_sample:
        return "", 0.0, 0.0
    clip = samples[start_sample:end_sample]
    audio_seconds = len(clip) / SAMPLE_RATE
    started = time.perf_counter()
    segments, _ = model.transcribe(
        clip,
        language="ko",
        task="transcribe",
        beam_size=beam_size,
        vad_filter=False,
    )
    text = "".join(segment.text for segment in segments).strip()
    elapsed = time.perf_counter() - started
    rtf = elapsed / max(audio_seconds, 0.001)
    return text, elapsed, rtf


def main():
    args = parse_args()
    raw_dir = Path(args.raw_dir)
    wav_path = raw_dir / args.wav
    smi_path = raw_dir / args.smi

    if args.dry_run:
        print("faster-whisper import: ok")
        print("huggingface_hub import: ok")
        print(f"raw_dir exists: {raw_dir.exists()} ({raw_dir})")
        print(f"wav exists: {wav_path.exists()} ({wav_path.name})")
        print(f"smi exists: {smi_path.exists()} ({smi_path.name})")
        return 0

    if not wav_path.exists() or not smi_path.exists():
        raise FileNotFoundError(f"missing sample files: {wav_path}, {smi_path}")

    model_path = resolve_model_path(args)
    print(f"[BatiSay] model_path={model_path}")
    model = WhisperModel(str(model_path), device="cpu", compute_type=args.compute_type)

    samples = read_samples(wav_path)
    captions = parse_smi(smi_path)
    windows = merge_windows(captions, args.window_sec)
    if args.max_windows > 0:
        windows = windows[:args.max_windows]

    total_distance = 0
    total_ref_len = 0
    all_ref = ""
    all_hyp = ""
    empty_count = 0
    rtfs = []

    print(f"=== BatiSay faster-whisper [{wav_path.name}] window={args.window_sec}s windows={len(windows)} ===")
    for index, window in enumerate(windows):
        text, elapsed, rtf = transcribe_window(model, samples, window["start"], window["end"], args.beam_size)
        distance, ref_len = cer_stats(window["text"], text)
        total_distance += distance
        total_ref_len += ref_len
        all_ref += window["text"] + " "
        all_hyp += text + " "
        rtfs.append(rtf)
        if not text:
            empty_count += 1
        cer = distance / ref_len if ref_len else 0
        print(f"[BatiSay] #{index:03d} {window['start']:6.1f}-{window['end']:6.1f}s CER {cer * 100:5.1f}% RTF {rtf:.2f} text={text[:80]}")

    global_distance, global_ref_len = cer_stats(all_ref, all_hyp)
    micro_cer = total_distance / max(total_ref_len, 1)
    global_cer = global_distance / max(global_ref_len, 1)
    sorted_rtfs = sorted(rtfs)
    p50 = sorted_rtfs[int((len(sorted_rtfs) - 1) * 0.50)] if sorted_rtfs else 0
    p95 = sorted_rtfs[int((len(sorted_rtfs) - 1) * 0.95)] if sorted_rtfs else 0
    print(f"windows                : {len(windows)} (empty {empty_count})")
    print(f"per-window CER         : {micro_cer * 100:.1f}%")
    print(f"global CER             : {global_cer * 100:.1f}%")
    print(f"RTF p50/p95            : {p50:.2f} / {p95:.2f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
