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


DEFAULT_ENGINES = [
    "whisper_accurate",
    "speech_analyzer",
    "sf_speech_on_device",
]


def parse_args():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(
        description="Run Minto sample/meeting STT benchmarks sequentially with the common JSON schema."
    )
    parser.add_argument("--raw-dir", type=Path, default=root / "sample/meeting/raw")
    parser.add_argument("--output-root", type=Path, default=None)
    parser.add_argument("--engines", default=",".join(DEFAULT_ENGINES))
    parser.add_argument(
        "--samples",
        default="",
        help="Comma-separated sample ids without _full.wav, for example haengan_20260526.",
    )
    parser.add_argument("--window-sec", type=float, default=20.0)
    parser.add_argument(
        "--max-windows",
        type=int,
        default=0,
        help="0 means full meeting duration. Use a small number for smoke tests.",
    )
    parser.add_argument(
        "--skip-swift-global-cer",
        choices=["auto", "always", "never"],
        default="auto",
        help="auto skips global Levenshtein only for full-duration runs to avoid O(n*m) blowups.",
    )
    parser.add_argument("--configuration", choices=["debug", "release"], default="release")
    parser.add_argument("--filter", default="MeetingCorpusTests")
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
    return root / "tmp" / "stt-meeting-benchmarks" / timestamp


def should_skip_swift_global_cer(mode, max_windows):
    if mode == "always":
        return True
    if mode == "never":
        return False
    return max_windows <= 0


def make_command(args):
    return [
        "swift",
        "test",
        "-c",
        args.configuration,
        "--filter",
        args.filter,
        "--disable-sandbox",
    ]


def make_env(args, engine, sample_id, wav_name, smi_name, output_dir):
    env = os.environ.copy()
    env.update({
        "RUN_STT_TESTS": "1",
        "STT_ENGINE": engine,
        "MEETING_WAV": wav_name,
        "MEETING_SMI": smi_name,
        "MEETING_WINDOW_SEC": str(args.window_sec),
        "MEETING_MAX_WINDOWS": str(args.max_windows),
        "MEETING_OUTPUT_DIR": str(output_dir),
        "CLANG_MODULE_CACHE_PATH": env.get("CLANG_MODULE_CACHE_PATH", "/private/tmp/minto2-clang-cache"),
        "SWIFTPM_HOME": env.get("SWIFTPM_HOME", "/private/tmp/minto2-swiftpm-cache"),
        "XDG_CACHE_HOME": env.get("XDG_CACHE_HOME", "/private/tmp/minto2-xdg-cache"),
    })
    if should_skip_swift_global_cer(args.skip_swift_global_cer, args.max_windows):
        env["MEETING_SKIP_SWIFT_GLOBAL_CER"] = "1"
    else:
        env.pop("MEETING_SKIP_SWIFT_GLOBAL_CER", None)
    return env


def run_one(root, args, engine, sample_id, wav_name, smi_name, output_root):
    engine_dir = output_root / safe_path(engine)
    engine_dir.mkdir(parents=True, exist_ok=True)
    command = make_command(args)
    env = make_env(args, engine, sample_id, wav_name, smi_name, engine_dir)
    started = time.perf_counter()

    print(f"==> engine={engine} sample={sample_id}")
    print(" ".join(command))
    print(f"MEETING_OUTPUT_DIR={engine_dir}")

    if args.dry_run:
        return {
            "engine": engine,
            "sample_id": sample_id,
            "wav": wav_name,
            "smi": smi_name,
            "status": "dry_run",
            "returncode": None,
            "elapsed_seconds": 0,
            "output_dir": str(engine_dir),
            "metrics_file": str(engine_dir / f"{sample_id}_metrics.json"),
            "skip_swift_global_cer": env.get("MEETING_SKIP_SWIFT_GLOBAL_CER") == "1",
            "command": command,
        }

    completed = subprocess.run(command, cwd=root, env=env, text=True)
    elapsed = time.perf_counter() - started
    status = "passed" if completed.returncode == 0 else "failed"
    return {
        "engine": engine,
        "sample_id": sample_id,
        "wav": wav_name,
        "smi": smi_name,
        "status": status,
        "returncode": completed.returncode,
        "elapsed_seconds": elapsed,
        "output_dir": str(engine_dir),
        "metrics_file": str(engine_dir / f"{sample_id}_metrics.json"),
        "skip_swift_global_cer": env.get("MEETING_SKIP_SWIFT_GLOBAL_CER") == "1",
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
    raw_dir = args.raw_dir.expanduser().resolve()
    pairs = selected_pairs(raw_dir, args.samples)
    engines = split_csv(args.engines)

    if args.list_samples:
        for sample_id, wav_name, smi_name in pairs:
            print(f"{sample_id}\t{wav_name}\t{smi_name}")
        return 0

    if not pairs:
        raise SystemExit(f"No *_full.wav + *_smi.json pairs found in {raw_dir}")
    if not engines:
        raise SystemExit("No engines selected")

    output_root = (args.output_root or default_output_root(root)).expanduser().resolve()
    manifest = {
        "schema_version": 1,
        "started_at": datetime.now().isoformat(timespec="seconds"),
        "raw_dir": str(raw_dir),
        "output_root": str(output_root),
        "engines": engines,
        "sample_count": len(pairs),
        "window_sec": args.window_sec,
        "max_windows": args.max_windows,
        "skip_swift_global_cer": args.skip_swift_global_cer,
        "configuration": args.configuration,
        "dry_run": args.dry_run,
        "runs": [],
    }

    for engine in engines:
        for sample_id, wav_name, smi_name in pairs:
            run = run_one(root, args, engine, sample_id, wav_name, smi_name, output_root)
            manifest["runs"].append(run)
            write_manifest(output_root, manifest)
            if args.fail_fast and run["returncode"] not in (0, None):
                print(f"Fail-fast after {engine}/{sample_id}", file=sys.stderr)
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
