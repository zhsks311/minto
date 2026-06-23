#!/usr/bin/env python3
import argparse
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import time
import wave
from datetime import datetime
from pathlib import Path


DEFAULT_ENGINES = [
    "whisper_accurate",
    "speech_analyzer",
    "sf_speech_on_device",
]
LOW_DISK_RETURNCODE = 75


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
        "--min-window-sec",
        type=float,
        default=0.0,
        help="Minimum benchmark window seconds before dense-caption slicing may close a window.",
    )
    parser.add_argument(
        "--max-gap-sec",
        type=float,
        default=1.5,
        help="Maximum SMI caption gap seconds before closing the current benchmark window.",
    )
    parser.add_argument(
        "--audio-pad-sec",
        type=float,
        default=0.0,
        help="Extra audio seconds added before/after each benchmark window without changing the reference text.",
    )
    parser.add_argument(
        "--max-captions-per-window",
        type=int,
        default=0,
        help="0 disables dense-caption slicing. Positive values cap SMI captions per benchmark window.",
    )
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
    parser.add_argument(
        "--product-path",
        action="store_true",
        help="Run the app-route product-path benchmark harness.",
    )
    parser.add_argument(
        "--signed-dev-test",
        action="store_true",
        help="Run Swift tests through ./scripts/dev.sh test so the debug test bundle is signed before execution.",
    )
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument(
        "--timeout-sec",
        type=float,
        default=0,
        help="Per engine/sample timeout. 0 disables the timeout.",
    )
    parser.add_argument("--sort", choices=["name", "duration"], default="name")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--list-samples", action="store_true")
    parser.add_argument("--fail-fast", action="store_true")
    parser.add_argument(
        "--include-unavailable-engines",
        action="store_true",
        help="Run engines even when static preflight can prove they are unavailable on this host.",
    )
    parser.add_argument(
        "--min-free-mb",
        type=float,
        default=1024.0,
        help="Minimum free disk space required before each Swift STT run. Set 0 to disable.",
    )
    return parser.parse_args()


def sample_pairs(raw_dir):
    pairs = []
    for wav in sorted(raw_dir.glob("*_full.wav")):
        sample_id = wav.name.removesuffix("_full.wav")
        smi = raw_dir / f"{sample_id}_smi.json"
        if smi.exists():
            pairs.append((sample_id, wav.name, smi.name))
    return pairs


def wav_duration_seconds(path):
    with wave.open(str(path), "rb") as handle:
        return handle.getnframes() / float(handle.getframerate())


def sort_pairs(raw_dir, pairs, sort_mode):
    if sort_mode == "duration":
        return sorted(pairs, key=lambda pair: wav_duration_seconds(raw_dir / pair[1]))
    return pairs


def selected_pairs(raw_dir, requested_samples, sort_mode):
    pairs = sample_pairs(raw_dir)
    if not requested_samples:
        return sort_pairs(raw_dir, pairs, sort_mode)

    requested = {value.strip() for value in requested_samples.split(",") if value.strip()}
    selected = [pair for pair in pairs if pair[0] in requested]
    missing = sorted(requested - {pair[0] for pair in selected})
    if missing:
        raise SystemExit(f"Missing sample ids in {raw_dir}: {', '.join(missing)}")
    return sort_pairs(raw_dir, selected, sort_mode)


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
    test_filter = args.filter
    if getattr(args, "product_path", False) and test_filter == "MeetingCorpusTests":
        test_filter = "ProductPathMeetingCorpusTests"
    if getattr(args, "signed_dev_test", False):
        return [
            "./scripts/dev.sh",
            "test",
            test_filter,
        ]
    command = [
        "swift",
        "test",
        "-c",
        args.configuration,
    ]
    if getattr(args, "skip_build", False):
        command.append("--skip-build")
    command.extend([
        "--filter",
        test_filter,
        "--disable-sandbox",
    ])
    return command


def make_env(args, engine, sample_id, wav_name, smi_name, output_dir):
    min_window_sec = getattr(args, "min_window_sec", 0.0)
    max_gap_sec = getattr(args, "max_gap_sec", 1.5)
    audio_pad_sec = getattr(args, "audio_pad_sec", 0.0)
    max_captions_per_window = getattr(args, "max_captions_per_window", 0)
    raw_dir = getattr(args, "raw_dir", Path(__file__).resolve().parents[1] / "sample/meeting/raw")
    env = os.environ.copy()
    env.update({
        "RUN_STT_TESTS": "1",
        "STT_ENGINE": engine,
        "MEETING_RAW_DIR": str(raw_dir.expanduser().resolve()),
        "MEETING_WAV": wav_name,
        "MEETING_SMI": smi_name,
        "MEETING_WINDOW_SEC": str(args.window_sec),
        "MEETING_MIN_WINDOW_SEC": str(min_window_sec),
        "MEETING_MAX_GAP_SEC": str(max_gap_sec),
        "MEETING_AUDIO_PAD_SEC": str(audio_pad_sec),
        "MEETING_MAX_CAPTIONS_PER_WINDOW": str(max_captions_per_window),
        "MEETING_MAX_WINDOWS": str(args.max_windows),
        "MEETING_OUTPUT_DIR": str(output_dir),
        "CLANG_MODULE_CACHE_PATH": env.get("CLANG_MODULE_CACHE_PATH", "/private/tmp/minto2-clang-cache"),
        "SWIFTPM_HOME": env.get("SWIFTPM_HOME", "/private/tmp/minto2-swiftpm-cache"),
        "XDG_CACHE_HOME": env.get("XDG_CACHE_HOME", "/private/tmp/minto2-xdg-cache"),
    })
    if getattr(args, "product_path", False):
        env["RUN_PRODUCT_PATH_STT_TESTS"] = "1"
    else:
        env.pop("RUN_PRODUCT_PATH_STT_TESTS", None)
    if getattr(args, "signed_dev_test", False):
        env["MINTO_SWIFT_TEST_DISABLE_SANDBOX"] = "1"
    else:
        env.pop("MINTO_SWIFT_TEST_DISABLE_SANDBOX", None)
    if should_skip_swift_global_cer(args.skip_swift_global_cer, args.max_windows):
        env["MEETING_SKIP_SWIFT_GLOBAL_CER"] = "1"
    else:
        env.pop("MEETING_SKIP_SWIFT_GLOBAL_CER", None)
    return env


def parse_macos_version(value):
    parts = []
    for part in str(value).split("."):
        try:
            parts.append(int(part))
        except ValueError:
            break
    return tuple(parts) if parts else None


def current_macos_version(environment=None):
    environment = environment or os.environ
    if environment.get("MINTO_STT_BENCH_MACOS_VERSION"):
        return parse_macos_version(environment["MINTO_STT_BENCH_MACOS_VERSION"])
    return parse_macos_version(platform.mac_ver()[0])


def engine_unavailable_reason(engine, system=None, macos_version=None, environment=None):
    system = system or sys.platform
    if engine not in {"speech_analyzer", "sf_speech_on_device"}:
        return None

    if system != "darwin":
        return "Apple speech engines require macOS"

    version = (
        macos_version
        if macos_version is not None
        else current_macos_version(environment=environment)
    )
    if version is None:
        return "macOS version could not be determined"

    if engine == "speech_analyzer" and version < (26, 0):
        return f"SpeechAnalyzer requires macOS 26+ (current {format_version(version)})"

    if engine == "sf_speech_on_device" and version < (10, 15):
        return f"SFSpeechRecognizer requires macOS 10.15+ (current {format_version(version)})"

    return None


def format_version(version):
    return ".".join(str(part) for part in version)


def run_one(root, args, engine, sample_id, wav_name, smi_name, output_root):
    engine_dir = output_root / safe_path(engine)
    engine_dir.mkdir(parents=True, exist_ok=True)
    metrics_file = engine_dir / f"{sample_id}_metrics.json"
    log_file = engine_dir / f"{sample_id}_run.log"
    unavailable_marker = engine_dir / f"{sample_id}_unavailable.json"
    command = make_command(args)
    env = make_env(args, engine, sample_id, wav_name, smi_name, engine_dir)
    started = time.perf_counter()

    print(f"==> engine={engine} sample={sample_id}")
    print(" ".join(command))
    print(f"MEETING_OUTPUT_DIR={engine_dir}")
    print(f"RUN_LOG={log_file}")

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
            "metrics_file": str(metrics_file),
            "log_file": str(log_file),
            "skip_swift_global_cer": env.get("MEETING_SKIP_SWIFT_GLOBAL_CER") == "1",
            "min_window_sec": getattr(args, "min_window_sec", 0.0),
            "max_gap_sec": getattr(args, "max_gap_sec", 1.5),
            "audio_pad_sec": getattr(args, "audio_pad_sec", 0.0),
            "max_captions_per_window": getattr(args, "max_captions_per_window", 0),
            "product_path": getattr(args, "product_path", False),
            "mode": "product_path" if getattr(args, "product_path", False) else "meeting_corpus",
            "signed_dev_test": getattr(args, "signed_dev_test", False),
            "timeout_sec": args.timeout_sec,
            "command": command,
        }

    unavailable_reason = None
    if not args.include_unavailable_engines:
        unavailable_reason = engine_unavailable_reason(engine)
    if unavailable_reason:
        print(f"skip unavailable: {unavailable_reason}")
        return {
            "engine": engine,
            "sample_id": sample_id,
            "wav": wav_name,
            "smi": smi_name,
            "status": "skipped_unavailable",
            "returncode": None,
            "elapsed_seconds": 0,
            "output_dir": str(engine_dir),
            "metrics_file": str(metrics_file),
            "log_file": str(log_file),
            "skip_swift_global_cer": env.get("MEETING_SKIP_SWIFT_GLOBAL_CER") == "1",
            "min_window_sec": getattr(args, "min_window_sec", 0.0),
            "max_gap_sec": getattr(args, "max_gap_sec", 1.5),
            "audio_pad_sec": getattr(args, "audio_pad_sec", 0.0),
            "max_captions_per_window": getattr(args, "max_captions_per_window", 0),
            "product_path": getattr(args, "product_path", False),
            "mode": "product_path" if getattr(args, "product_path", False) else "meeting_corpus",
            "signed_dev_test": getattr(args, "signed_dev_test", False),
            "timeout_sec": args.timeout_sec,
            "command": command,
            "skip_reason": unavailable_reason,
        }

    disk_issue = disk_space_issue(engine_dir, getattr(args, "min_free_mb", 0))
    if disk_issue is not None:
        reason = (
            f"free={format_mb(disk_issue['free_mb'])}MB < "
            f"required={format_mb(disk_issue['required_mb'])}MB "
            f"at {disk_issue['path']}"
        )
        append_log(log_file, f"[disk_space_low] {reason}\n")
        print(f"skip disk_space_low: {reason}")
        return {
            "engine": engine,
            "sample_id": sample_id,
            "wav": wav_name,
            "smi": smi_name,
            "status": "disk_space_low",
            "returncode": LOW_DISK_RETURNCODE,
            "elapsed_seconds": time.perf_counter() - started,
            "output_dir": str(engine_dir),
            "metrics_file": str(metrics_file),
            "log_file": str(log_file),
            "skip_swift_global_cer": env.get("MEETING_SKIP_SWIFT_GLOBAL_CER") == "1",
            "min_window_sec": getattr(args, "min_window_sec", 0.0),
            "max_gap_sec": getattr(args, "max_gap_sec", 1.5),
            "audio_pad_sec": getattr(args, "audio_pad_sec", 0.0),
            "max_captions_per_window": getattr(args, "max_captions_per_window", 0),
            "product_path": getattr(args, "product_path", False),
            "mode": "product_path" if getattr(args, "product_path", False) else "meeting_corpus",
            "signed_dev_test": getattr(args, "signed_dev_test", False),
            "timeout_sec": args.timeout_sec,
            "command": command,
            "disk_free_mb": disk_issue["free_mb"],
            "disk_required_mb": disk_issue["required_mb"],
            "disk_path": disk_issue["path"],
            "disk_space_reason": reason,
        }

    timeout = args.timeout_sec if args.timeout_sec > 0 else None
    try:
        completed = run_logged_command(command, root, env, timeout, log_file)
        returncode = completed.returncode
        status = "passed" if returncode == 0 else "failed"
    except subprocess.TimeoutExpired:
        returncode = 124
        status = "timeout"
        append_log(log_file, f"\n[timeout] exceeded {args.timeout_sec} seconds\n")
    elapsed = time.perf_counter() - started
    unavailable = load_unavailable_marker(unavailable_marker)
    if unavailable is not None:
        status = "skipped_unavailable"
        returncode = None
    if status in {"failed", "timeout"}:
        print_log_tail(log_file)
    return {
        "engine": engine,
        "sample_id": sample_id,
        "wav": wav_name,
        "smi": smi_name,
        "status": status,
        "returncode": returncode,
        "elapsed_seconds": elapsed,
        "output_dir": str(engine_dir),
        "metrics_file": str(metrics_file),
        "log_file": str(log_file),
        "skip_swift_global_cer": env.get("MEETING_SKIP_SWIFT_GLOBAL_CER") == "1",
        "min_window_sec": getattr(args, "min_window_sec", 0.0),
        "max_gap_sec": getattr(args, "max_gap_sec", 1.5),
        "audio_pad_sec": getattr(args, "audio_pad_sec", 0.0),
        "max_captions_per_window": getattr(args, "max_captions_per_window", 0),
        "product_path": getattr(args, "product_path", False),
        "mode": "product_path" if getattr(args, "product_path", False) else "meeting_corpus",
        "signed_dev_test": getattr(args, "signed_dev_test", False),
        "timeout_sec": args.timeout_sec,
        "command": command,
        **({"skip_reason": unavailable["reason"]} if unavailable is not None else {}),
    }


def disk_space_issue(path, required_mb):
    if required_mb <= 0:
        return None
    path.mkdir(parents=True, exist_ok=True)
    usage = shutil.disk_usage(path)
    free_mb = usage.free / 1024 / 1024
    if free_mb >= required_mb:
        return None
    return {
        "path": str(path),
        "free_mb": free_mb,
        "required_mb": required_mb,
    }


def format_mb(value):
    return f"{float(value):.1f}"


def run_logged_command(command, root, env, timeout, log_file):
    with log_file.open("w", encoding="utf-8") as handle:
        handle.write("$ " + " ".join(command) + "\n\n")
        handle.flush()
        return subprocess.run(
            command,
            cwd=root,
            env=env,
            text=True,
            timeout=timeout,
            stdout=handle,
            stderr=subprocess.STDOUT,
        )


def append_log(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(text)


def print_log_tail(path, limit=4000):
    if not path.exists():
        return
    text = path.read_text(encoding="utf-8", errors="replace")
    tail = text[-limit:].strip()
    if not tail:
        return
    print(f"--- log tail: {path} ---")
    print(tail)


def load_unavailable_marker(path):
    if not path.exists():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {"reason": "invalid unavailable marker"}
    if data.get("status") != "skipped_unavailable":
        return None
    return {"reason": data.get("reason") or "unknown"}


def write_manifest(output_root, manifest):
    output_root.mkdir(parents=True, exist_ok=True)
    path = output_root / "run_manifest.json"
    path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True),
        encoding="utf-8",
    )
    return path


def run_summary(runs):
    failures = [run for run in runs if run["returncode"] not in (0, None)]
    timeouts = [run for run in runs if run["status"] == "timeout"]
    disk_lows = [run for run in runs if run["status"] == "disk_space_low"]
    dry_runs = [run for run in runs if run["status"] == "dry_run"]
    skipped = [run for run in runs if run["status"] == "skipped_unavailable"]
    if timeouts:
        status = "timeout"
    elif disk_lows:
        status = "disk_space_low"
    elif failures:
        status = "failed"
    elif runs and len(dry_runs) == len(runs):
        status = "dry_run"
    elif runs and len(skipped) == len(runs):
        status = "skipped_unavailable"
    elif skipped:
        status = "passed_with_skips"
    else:
        status = "passed"
    return status, failures, timeouts


def main():
    args = parse_args()
    root = Path(__file__).resolve().parents[1]
    raw_dir = args.raw_dir.expanduser().resolve()
    pairs = selected_pairs(raw_dir, args.samples, args.sort)
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
        "min_window_sec": args.min_window_sec,
        "max_gap_sec": args.max_gap_sec,
        "audio_pad_sec": args.audio_pad_sec,
        "max_captions_per_window": args.max_captions_per_window,
        "max_windows": args.max_windows,
        "skip_swift_global_cer": args.skip_swift_global_cer,
        "configuration": args.configuration,
        "skip_build": args.skip_build,
        "timeout_sec": args.timeout_sec,
        "sort": args.sort,
        "dry_run": args.dry_run,
        "product_path": args.product_path,
        "signed_dev_test": args.signed_dev_test,
        "include_unavailable_engines": args.include_unavailable_engines,
        "runs": [],
    }

    for engine in engines:
        for sample_id, wav_name, smi_name in pairs:
            run = run_one(root, args, engine, sample_id, wav_name, smi_name, output_root)
            manifest["runs"].append(run)
            write_manifest(output_root, manifest)
            if args.fail_fast and run["returncode"] not in (0, None):
                manifest["finished_at"] = datetime.now().isoformat(timespec="seconds")
                manifest["status"] = run["status"]
                write_manifest(output_root, manifest)
                print(f"Fail-fast after {engine}/{sample_id}", file=sys.stderr)
                return run["returncode"]

    manifest["finished_at"] = datetime.now().isoformat(timespec="seconds")
    manifest["status"], failures, timeouts = run_summary(manifest["runs"])
    manifest_path = write_manifest(output_root, manifest)
    skipped = [run for run in manifest["runs"] if run["status"] == "skipped_unavailable"]

    print(f"\nmanifest: {manifest_path}")
    disk_lows = [run for run in manifest["runs"] if run["status"] == "disk_space_low"]
    print(
        f"runs: {len(manifest['runs'])}, failures: {len(failures)}, "
        f"timeouts: {len(timeouts)}, skipped: {len(skipped)}, "
        f"disk_space_low: {len(disk_lows)}"
    )
    if manifest["status"] == "disk_space_low":
        return LOW_DISK_RETURNCODE
    if failures:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
