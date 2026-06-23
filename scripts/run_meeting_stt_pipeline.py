#!/usr/bin/env python3
import argparse
import json
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path


def parse_args():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(
        description="Run sample/meeting STT benchmarks and write summaries in one step."
    )
    parser.add_argument("--raw-dir", type=Path, default=root / "sample/meeting/raw")
    parser.add_argument("--output-root", type=Path, default=None)
    parser.add_argument("--engines", default="whisper_accurate")
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
        help="Pass --signed-dev-test to the child STT benchmark runner.",
    )
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--timeout-sec", type=float, default=0)
    parser.add_argument("--sort", choices=["name", "duration"], default="name")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--fail-fast", action="store_true")
    parser.add_argument(
        "--isolate-sample-processes",
        action="store_true",
        help=(
            "Run each selected sample through a separate child benchmark process "
            "and merge run manifests."
        ),
    )
    parser.add_argument("--include-unavailable-engines", action="store_true")
    parser.add_argument("--compute-missing-global-cer", action="store_true")
    parser.add_argument("--global-char-limit", type=int, default=20_000)
    parser.add_argument("--global-cell-limit", type=int, default=50_000_000)
    parser.add_argument("--write-segments", action="store_true")
    parser.add_argument("--segment-limit", type=int, default=40)
    parser.add_argument("--segment-min-cer", type=float, default=0.8)
    parser.add_argument("--vad-root", type=Path, default=None)
    parser.add_argument("--vad-engine", default="energy")
    parser.add_argument("--vad-low-overlap", type=float, default=0.5)
    parser.add_argument("--vad-high-overlap", type=float, default=0.8)
    parser.add_argument(
        "--min-free-mb",
        type=float,
        default=1024.0,
        help="Minimum free disk space passed to the child STT benchmark runner.",
    )
    return parser.parse_args()


def default_output_root(root):
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    return root / "tmp" / "stt-meeting-pipeline" / timestamp


def run_command(command, cwd):
    started = time.perf_counter()
    completed = subprocess.run(command, cwd=cwd, text=True)
    return {
        "command": command,
        "returncode": completed.returncode,
        "elapsed_seconds": time.perf_counter() - started,
    }


def write_manifest(output_root, manifest):
    output_root.mkdir(parents=True, exist_ok=True)
    path = output_root / "pipeline_manifest.json"
    path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True),
        encoding="utf-8",
    )
    return path


def child_manifest_status(benchmark_root):
    path = benchmark_root / "run_manifest.json"
    if not path.exists():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None
    return data.get("status")


def child_manifest_summary(benchmark_root):
    path = benchmark_root / "run_manifest.json"
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}
    runs = data.get("runs") or []
    return {
        "status": data.get("status"),
        "run_count": len(runs),
        "passed_count": count_runs_with_status(runs, "passed"),
        "failed_count": count_runs_with_status(runs, "failed"),
        "timeout_count": count_runs_with_status(runs, "timeout"),
        "dry_run_count": count_runs_with_status(runs, "dry_run"),
        "skipped_unavailable_count": count_runs_with_status(runs, "skipped_unavailable"),
        "disk_space_low_count": count_runs_with_status(runs, "disk_space_low"),
        "failed_runs": run_keys_with_status(runs, "failed"),
        "timeout_runs": run_keys_with_status(runs, "timeout"),
        "skipped_unavailable_runs": run_keys_with_status(runs, "skipped_unavailable"),
        "disk_space_low_runs": run_keys_with_status(runs, "disk_space_low"),
        "skipped_unavailable_reasons": skip_reason_counts(runs),
    }


def count_runs_with_status(runs, status):
    return sum(1 for run in runs if run.get("status") == status)


def run_keys_with_status(runs, status):
    return sorted(
        run_key(run)
        for run in runs
        if run.get("status") == status and run_key(run)
    )


def run_key(run):
    engine = run.get("engine")
    sample_id = run.get("sample_id")
    if not engine or not sample_id:
        return ""
    return f"{engine}/{sample_id}"


def skip_reason_counts(runs):
    counts = {}
    for run in runs:
        if run.get("status") != "skipped_unavailable":
            continue
        reason = run.get("skip_reason") or "unknown"
        counts[reason] = counts.get(reason, 0) + 1
    return dict(sorted(counts.items()))


def pipeline_status(benchmark_root, benchmark_result, summary_result):
    child_status = child_manifest_status(benchmark_root)
    if child_status == "timeout":
        return "timeout"
    if child_status == "dry_run":
        return "dry_run"
    if child_status == "skipped_unavailable":
        return "skipped_unavailable"
    if child_status == "disk_space_low":
        return "disk_space_low"
    if child_status == "passed_with_skips":
        return "passed_with_skips"
    if benchmark_result["returncode"] == 124:
        return "timeout"
    if summary_result["returncode"] != 0:
        return "failed_summary"
    if child_status == "failed":
        return "failed_benchmark"
    if benchmark_result["returncode"] == 0:
        return "passed"
    return "failed_benchmark"


def pipeline_returncode(status, benchmark_result, summary_result):
    if status == "timeout":
        return 124
    if status == "dry_run":
        return 0
    if status == "skipped_unavailable":
        return 0
    if status == "disk_space_low":
        return 75
    if status == "passed_with_skips":
        return 0
    if summary_result["returncode"] != 0:
        return summary_result["returncode"]
    return benchmark_result["returncode"]


def split_csv(value):
    return [part.strip() for part in value.split(",") if part.strip()]


def sample_ids_from_raw_dir(raw_dir):
    sample_ids = []
    for wav in sorted(raw_dir.glob("*_full.wav")):
        sample_id = wav.name.removesuffix("_full.wav")
        if (raw_dir / f"{sample_id}_smi.json").exists():
            sample_ids.append(sample_id)
    return sample_ids


def isolated_sample_ids(raw_dir, args):
    return split_csv(args.samples) if args.samples else sample_ids_from_raw_dir(raw_dir)


def benchmark_command(root, raw_dir, benchmark_root, args, samples_override=None):
    command = [
        sys.executable,
        str(root / "scripts/run_meeting_stt_benchmarks.py"),
        "--raw-dir",
        str(raw_dir),
        "--output-root",
        str(benchmark_root),
        "--engines",
        args.engines,
        "--window-sec",
        str(args.window_sec),
        "--min-window-sec",
        str(getattr(args, "min_window_sec", 0.0)),
        "--max-gap-sec",
        str(getattr(args, "max_gap_sec", 1.5)),
        "--audio-pad-sec",
        str(getattr(args, "audio_pad_sec", 0.0)),
        "--max-captions-per-window",
        str(getattr(args, "max_captions_per_window", 0)),
        "--max-windows",
        str(args.max_windows),
        "--skip-swift-global-cer",
        args.skip_swift_global_cer,
        "--configuration",
        args.configuration,
        "--filter",
        args.filter,
        "--timeout-sec",
        str(args.timeout_sec),
        "--sort",
        args.sort,
        "--min-free-mb",
        str(args.min_free_mb),
    ]
    if args.skip_build:
        command.append("--skip-build")
    if getattr(args, "signed_dev_test", False):
        command.append("--signed-dev-test")
    if getattr(args, "product_path", False):
        command.append("--product-path")
    samples = args.samples if samples_override is None else samples_override
    if samples:
        command.extend(["--samples", samples])
    if args.dry_run:
        command.append("--dry-run")
    if args.fail_fast:
        command.append("--fail-fast")
    if args.include_unavailable_engines:
        command.append("--include-unavailable-engines")
    return command


def run_isolated_benchmark_commands(root, raw_dir, benchmark_root, args):
    sample_ids = isolated_sample_ids(raw_dir, args)
    if not sample_ids:
        raise SystemExit(f"No *_full.wav + *_smi.json pairs found in {raw_dir}")

    started = time.perf_counter()
    step_results = []
    combined_runs = []
    child_manifest_paths = []
    base_manifest = None
    for sample_id in sample_ids:
        child_root = benchmark_root / "isolated_samples" / sample_id
        command = benchmark_command(root, raw_dir, child_root, args, samples_override=sample_id)
        result = run_command(command, root)
        child_manifest_path = child_root / "run_manifest.json"
        archived_manifest_path = (
            benchmark_root.parent
            / "isolated_sample_manifests"
            / f"{sample_id}_run_manifest.json"
        )
        step_results.append(
            {
                "sample_id": sample_id,
                "benchmark_root": str(child_root),
                "run_manifest": str(archived_manifest_path),
                **result,
            }
        )
        child_manifest = read_json_if_exists(child_manifest_path)
        if child_manifest:
            base_manifest = base_manifest or child_manifest
            write_json(archived_manifest_path, child_manifest)
            child_manifest_path.unlink(missing_ok=True)
            child_manifest_paths.append(str(archived_manifest_path))
            combined_runs.extend(child_manifest.get("runs") or [])
        if args.fail_fast and result["returncode"] not in (0, None):
            break

    if base_manifest is None:
        base_manifest = {
            "schema_version": 1,
            "raw_dir": str(raw_dir),
            "output_root": str(benchmark_root),
            "engines": split_csv(args.engines),
        }
    combined_manifest = {**base_manifest}
    combined_manifest.update({
        "output_root": str(benchmark_root),
        "sample_count": len(sample_ids),
        "attempted_sample_count": len(step_results),
        "isolated_sample_processes": True,
        "child_manifest_paths": child_manifest_paths,
        "runs": combined_runs,
        "finished_at": datetime.now().isoformat(timespec="seconds"),
        "status": combined_run_status(combined_runs, step_results),
    })
    write_json(benchmark_root / "run_manifest.json", combined_manifest)
    return {
        "command": [
            "isolated-sample-processes",
            *[result["sample_id"] for result in step_results],
        ],
        "returncode": isolated_returncode(combined_manifest["status"], step_results),
        "elapsed_seconds": time.perf_counter() - started,
        "steps": step_results,
    }


def read_json_if_exists(path):
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None


def write_json(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True),
        encoding="utf-8",
    )


def combined_run_status(runs, step_results):
    if any(result["returncode"] == 124 for result in step_results):
        return "timeout"
    if any(run.get("status") == "timeout" for run in runs):
        return "timeout"
    if any(run.get("status") == "disk_space_low" for run in runs):
        return "disk_space_low"
    if any(result["returncode"] not in (0, None) for result in step_results):
        return "failed"
    if any(run.get("status") == "failed" for run in runs):
        return "failed"
    if runs and all(run.get("status") == "dry_run" for run in runs):
        return "dry_run"
    skipped = [run for run in runs if run.get("status") == "skipped_unavailable"]
    if runs and len(skipped) == len(runs):
        return "skipped_unavailable"
    if skipped:
        return "passed_with_skips"
    return "passed"


def isolated_returncode(status, step_results):
    if status == "timeout":
        return 124
    if status == "disk_space_low":
        return 75
    if status in {"dry_run", "skipped_unavailable", "passed_with_skips", "passed"}:
        return 0
    for result in step_results:
        if result["returncode"] not in (0, None):
            return result["returncode"]
    return 1


def summary_command(root, benchmark_root, args):
    command = [
        sys.executable,
        str(root / "scripts/summarize_stt_benchmarks.py"),
        str(benchmark_root),
        "--write",
        "--global-char-limit",
        str(args.global_char_limit),
        "--global-cell-limit",
        str(args.global_cell_limit),
        "--segment-limit",
        str(args.segment_limit),
        "--segment-min-cer",
        str(args.segment_min_cer),
        "--vad-engine",
        args.vad_engine,
        "--vad-low-overlap",
        str(args.vad_low_overlap),
        "--vad-high-overlap",
        str(args.vad_high_overlap),
    ]
    if args.compute_missing_global_cer:
        command.append("--compute-missing-global-cer")
    if args.write_segments:
        command.append("--write-segments")
    if args.vad_root is not None:
        command.extend(["--vad-root", str(args.vad_root.expanduser().resolve())])
    return command


def main():
    args = parse_args()
    root = Path(__file__).resolve().parents[1]
    raw_dir = args.raw_dir.expanduser().resolve()
    output_root = (args.output_root or default_output_root(root)).expanduser().resolve()
    benchmark_root = output_root / "benchmark"

    benchmark = benchmark_command(root, raw_dir, benchmark_root, args)
    summary = summary_command(root, benchmark_root, args)

    manifest = {
        "schema_version": 1,
        "started_at": datetime.now().isoformat(timespec="seconds"),
        "raw_dir": str(raw_dir),
        "output_root": str(output_root),
        "benchmark_root": str(benchmark_root),
        "engines": args.engines,
        "samples": args.samples,
        "window_sec": args.window_sec,
        "min_window_sec": args.min_window_sec,
        "max_gap_sec": args.max_gap_sec,
        "audio_pad_sec": args.audio_pad_sec,
        "max_captions_per_window": args.max_captions_per_window,
        "max_windows": args.max_windows,
        "skip_build": args.skip_build,
        "timeout_sec": args.timeout_sec,
        "min_free_mb": args.min_free_mb,
        "dry_run": args.dry_run,
        "product_path": args.product_path,
        "signed_dev_test": args.signed_dev_test,
        "isolated_sample_processes": args.isolate_sample_processes,
        "include_unavailable_engines": args.include_unavailable_engines,
        "steps": [],
    }

    print("==> STT meeting benchmark", flush=True)
    if args.isolate_sample_processes:
        benchmark_result = run_isolated_benchmark_commands(root, raw_dir, benchmark_root, args)
    else:
        benchmark_result = run_command(benchmark, root)
    manifest["steps"].append({"name": "benchmark", **benchmark_result})
    manifest["benchmark_summary"] = child_manifest_summary(benchmark_root)
    write_manifest(output_root, manifest)

    print("==> STT benchmark summary", flush=True)
    summary_result = run_command(summary, root)
    manifest["steps"].append({"name": "summarize", **summary_result})
    manifest["finished_at"] = datetime.now().isoformat(timespec="seconds")
    manifest["benchmark_summary"] = child_manifest_summary(benchmark_root)
    manifest["status"] = pipeline_status(benchmark_root, benchmark_result, summary_result)
    manifest_path = write_manifest(output_root, manifest)

    print(f"\npipeline manifest: {manifest_path}")
    print(f"benchmark root: {benchmark_root}")
    return pipeline_returncode(manifest["status"], benchmark_result, summary_result)


if __name__ == "__main__":
    raise SystemExit(main())
