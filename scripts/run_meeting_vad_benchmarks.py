#!/usr/bin/env python3
import argparse
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path


DEFAULT_VADS = ["energy"]


def parse_args():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(
        description="Run Minto sample/meeting VAD benchmarks sequentially."
    )
    parser.add_argument("--raw-dir", type=Path, default=root / "sample/meeting/raw")
    parser.add_argument("--output-root", type=Path, default=None)
    parser.add_argument("--engines", default=",".join(DEFAULT_VADS))
    parser.add_argument(
        "--samples",
        default="",
        help="Comma-separated sample ids without _full.wav, for example haengan_20260526.",
    )
    parser.add_argument(
        "--mode",
        choices=["baseline", "stt"],
        default="baseline",
        help="baseline writes VAD recall metrics. stt transcribes VAD chunks and writes CER metrics.",
    )
    parser.add_argument("--stt-engine", default="whisper_accurate")
    parser.add_argument("--max-seconds", type=float, default=120.0)
    parser.add_argument("--frame-sec", type=float, default=None)
    parser.add_argument("--short-utterance-sec", type=float, default=None)
    parser.add_argument("--merge-gap-sec", type=float, default=None)
    parser.add_argument("--merge-max-sec", type=float, default=None)
    parser.add_argument("--vad-stt-max-chunks", type=int, default=None)
    parser.add_argument("--silero-threshold", type=float, default=None)
    parser.add_argument("--silero-min-speech-sec", type=float, default=None)
    parser.add_argument("--silero-min-silence-sec", type=float, default=None)
    parser.add_argument("--silero-speech-padding-sec", type=float, default=None)
    parser.add_argument("--silero-max-speech-sec", type=float, default=None)
    parser.add_argument("--fluidaudio-model-dir", type=Path, default=None)
    parser.add_argument("--configuration", choices=["debug", "release"], default="release")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--list-samples", action="store_true")
    parser.add_argument("--fail-fast", action="store_true")
    return parser.parse_args()


def sample_pairs(raw_dir):
    pairs = []
    for wav in sorted(raw_dir.glob("*_full.wav")):
        sample_id = wav.name.removesuffix("_full.wav")
        smi = raw_dir / f"{sample_id}_smi.json"
        if smi.exists():
            pairs.append((sample_id, wav.name, smi.name))
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


def split_csv(value):
    return [part.strip() for part in value.split(",") if part.strip()]


def safe_path(value):
    return re.sub(r"[^0-9A-Za-z_.-]+", "_", value).strip("_") or "unknown"


def default_output_root(root):
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    return root / "tmp" / "vad-meeting-benchmarks" / timestamp


def test_filter(mode):
    if mode == "stt":
        return "VADBenchmarkTests/vadChunkSTTCER"
    return "VADBenchmarkTests/vadBaselineMetrics"


def make_command(args):
    return [
        "swift",
        "test",
        "-c",
        args.configuration,
        "--filter",
        test_filter(args.mode),
        "--disable-sandbox",
    ]


def set_optional(env, key, value):
    if value is not None:
        env[key] = str(value)


def make_env(args, vad_engine, wav_name, smi_name, output_dir):
    env = os.environ.copy()
    env.update({
        "VAD_ENGINE": vad_engine,
        "MEETING_RAW_DIR": str(args.raw_dir.expanduser().resolve()),
        "MEETING_WAV": wav_name,
        "MEETING_SMI": smi_name,
        "VAD_MAX_SECONDS": str(args.max_seconds),
        "CLANG_MODULE_CACHE_PATH": env.get("CLANG_MODULE_CACHE_PATH", "/private/tmp/minto2-clang-cache"),
        "SWIFTPM_HOME": env.get("SWIFTPM_HOME", "/private/tmp/minto2-swiftpm-cache"),
        "XDG_CACHE_HOME": env.get("XDG_CACHE_HOME", "/private/tmp/minto2-xdg-cache"),
    })

    if args.mode == "stt":
        env.update({
            "RUN_STT_TESTS": "1",
            "RUN_VAD_STT_BENCH": "1",
            "STT_ENGINE": args.stt_engine,
            "VAD_STT_OUTPUT_DIR": str(output_dir),
        })
    else:
        env.update({
            "RUN_VAD_BENCH": "1",
            "VAD_OUTPUT_DIR": str(output_dir),
        })

    set_optional(env, "VAD_FRAME_SEC", args.frame_sec)
    set_optional(env, "VAD_SHORT_UTTERANCE_SEC", args.short_utterance_sec)
    set_optional(env, "VAD_MERGE_GAP_SEC", args.merge_gap_sec)
    set_optional(env, "VAD_MERGE_MAX_SEC", args.merge_max_sec)
    set_optional(env, "VAD_STT_MAX_CHUNKS", args.vad_stt_max_chunks)
    set_optional(env, "SILERO_VAD_THRESHOLD", args.silero_threshold)
    set_optional(env, "SILERO_MIN_SPEECH_SEC", args.silero_min_speech_sec)
    set_optional(env, "SILERO_MIN_SILENCE_SEC", args.silero_min_silence_sec)
    set_optional(env, "SILERO_SPEECH_PADDING_SEC", args.silero_speech_padding_sec)
    set_optional(env, "SILERO_MAX_SPEECH_SEC", args.silero_max_speech_sec)
    if args.fluidaudio_model_dir is not None:
        env["FLUIDAUDIO_MODEL_DIR"] = str(args.fluidaudio_model_dir.expanduser().resolve())
    return env


def expected_metrics_file(args, output_dir, sample_id, vad_engine):
    if args.mode == "stt":
        return str(output_dir / f"{sample_id}_vad_{vad_engine}_stt_*.json")
    return str(output_dir / f"{sample_id}_vad_{vad_engine}_metrics.json")


def run_one(root, args, vad_engine, sample_id, wav_name, smi_name, output_root):
    engine_dir = output_root / safe_path(vad_engine)
    engine_dir.mkdir(parents=True, exist_ok=True)
    command = make_command(args)
    env = make_env(args, vad_engine, wav_name, smi_name, engine_dir)
    started = time.perf_counter()

    print(f"==> mode={args.mode} vad={vad_engine} sample={sample_id}")
    print(" ".join(command))
    print(f"output_dir={engine_dir}")

    if args.dry_run:
        return {
            "mode": args.mode,
            "vad_engine": vad_engine,
            "stt_engine": args.stt_engine if args.mode == "stt" else "",
            "sample_id": sample_id,
            "wav": wav_name,
            "smi": smi_name,
            "status": "dry_run",
            "returncode": None,
            "elapsed_seconds": 0,
            "output_dir": str(engine_dir),
            "metrics_file": expected_metrics_file(args, engine_dir, sample_id, vad_engine),
            "command": command,
        }

    completed = subprocess.run(command, cwd=root, env=env, text=True)
    elapsed = time.perf_counter() - started
    status = "passed" if completed.returncode == 0 else "failed"
    return {
        "mode": args.mode,
        "vad_engine": vad_engine,
        "stt_engine": args.stt_engine if args.mode == "stt" else "",
        "sample_id": sample_id,
        "wav": wav_name,
        "smi": smi_name,
        "status": status,
        "returncode": completed.returncode,
        "elapsed_seconds": elapsed,
        "output_dir": str(engine_dir),
        "metrics_file": expected_metrics_file(args, engine_dir, sample_id, vad_engine),
        "command": command,
    }


def write_manifest(output_root, manifest):
    output_root.mkdir(parents=True, exist_ok=True)
    path = output_root / "run_manifest.json"
    path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True),
        encoding="utf-8",
    )
    return path


def main():
    args = parse_args()
    root = Path(__file__).resolve().parents[1]
    args.raw_dir = args.raw_dir.expanduser().resolve()
    pairs = selected_pairs(args.raw_dir, args.samples)
    vad_engines = split_csv(args.engines)

    if args.list_samples:
        for sample_id, wav_name, smi_name in pairs:
            print(f"{sample_id}\t{wav_name}\t{smi_name}")
        return 0

    if not pairs:
        raise SystemExit(f"No *_full.wav + *_smi.json pairs found in {args.raw_dir}")
    if not vad_engines:
        raise SystemExit("No VAD engines selected")

    output_root = (args.output_root or default_output_root(root)).expanduser().resolve()
    manifest = {
        "schema_version": 1,
        "started_at": datetime.now().isoformat(timespec="seconds"),
        "raw_dir": str(args.raw_dir),
        "output_root": str(output_root),
        "mode": args.mode,
        "vad_engines": vad_engines,
        "stt_engine": args.stt_engine if args.mode == "stt" else "",
        "sample_count": len(pairs),
        "max_seconds": args.max_seconds,
        "configuration": args.configuration,
        "dry_run": args.dry_run,
        "runs": [],
    }

    for vad_engine in vad_engines:
        for sample_id, wav_name, smi_name in pairs:
            run = run_one(root, args, vad_engine, sample_id, wav_name, smi_name, output_root)
            manifest["runs"].append(run)
            write_manifest(output_root, manifest)
            if args.fail_fast and run["returncode"] not in (0, None):
                print(f"Fail-fast after {vad_engine}/{sample_id}", file=sys.stderr)
                return run["returncode"]

    manifest["finished_at"] = datetime.now().isoformat(timespec="seconds")
    manifest_path = write_manifest(output_root, manifest)
    failures = [run for run in manifest["runs"] if run["returncode"] not in (0, None)]

    print(f"\nmanifest: {manifest_path}")
    print(f"runs: {len(manifest['runs'])}, failures: {len(failures)}")
    if failures:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
