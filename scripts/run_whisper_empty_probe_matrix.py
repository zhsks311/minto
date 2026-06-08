#!/usr/bin/env python3
import argparse
import csv
import json
import os
import re
import subprocess
import time
from datetime import datetime
from pathlib import Path


DEFAULT_LABELS = [
    "silero-empty-jaegyeong-20260429-097",
    "silero-empty-plenary-20260423-411",
    "silero-empty-plenary-20260508-037",
]
DEFAULT_VARIANTS = ["baseline", "logProbNil", "tempFallback0", "windowClip0"]
DEFAULT_PATHS = ["direct", "service"]
TEST_FILTER = "WhisperEmptyClipDiagnosticsTests/rawWhisperKitOutput"


def parse_args():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(
        description="Run Whisper empty-output diagnostic probes across paths and decode variants."
    )
    parser.add_argument("--output-root", type=Path, default=None)
    parser.add_argument("--probe-set", default="sileroFullDuration")
    parser.add_argument("--labels", default=",".join(DEFAULT_LABELS))
    parser.add_argument("--variants", default=",".join(DEFAULT_VARIANTS))
    parser.add_argument("--paths", default=",".join(DEFAULT_PATHS))
    parser.add_argument("--repeats", type=int, default=1)
    parser.add_argument("--model-folder", type=Path, default=None)
    parser.add_argument("--configuration", choices=["debug", "release"], default="debug")
    parser.add_argument(
        "--service-per-variant",
        action="store_true",
        help="Run service path once per variant. By default service runs baseline once because variants affect only direct diagnostics.",
    )
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--fail-fast", action="store_true")
    parser.add_argument("--root", type=Path, default=root)
    return parser.parse_args()


def split_csv(value):
    return [part.strip() for part in value.split(",") if part.strip()]


def safe_path(value):
    return re.sub(r"[^0-9A-Za-z_.-]+", "_", value).strip("_") or "unknown"


def default_output_root(root):
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    return root / "tmp" / "whisper-empty-probe-matrix" / timestamp


def make_command(args):
    return [
        "swift",
        "test",
        "-c",
        args.configuration,
        "--filter",
        TEST_FILTER,
        "--disable-sandbox",
    ]


def make_env(args, labels, diagnostic_path, variant):
    env = os.environ.copy()
    env.update({
        "RUN_STT_TESTS": "1",
        "WHISPER_DIAG_PROBE_SET": args.probe_set,
        "WHISPER_DIAG_PATH": diagnostic_path,
        "WHISPER_DIAG_LABELS": ",".join(labels),
        "WHISPER_DIAG_VARIANT": variant,
        "CLANG_MODULE_CACHE_PATH": env.get("CLANG_MODULE_CACHE_PATH", "/private/tmp/minto2-clang-cache"),
        "SWIFTPM_HOME": env.get("SWIFTPM_HOME", "/private/tmp/minto2-swiftpm-cache"),
        "XDG_CACHE_HOME": env.get("XDG_CACHE_HOME", "/private/tmp/minto2-xdg-cache"),
    })
    if args.model_folder is not None:
        env["WHISPER_MODEL_FOLDER"] = str(args.model_folder.expanduser().resolve())
    return env


def variants_for_path(path, variants, service_per_variant):
    if path == "service" and not service_per_variant:
        return ["baseline"]
    return variants


def parse_diag_rows(output, diagnostic_path, variant, repeat, returncode):
    rows = []
    for line in output.splitlines():
        if not line.startswith("[DIAG][direct] ") and not line.startswith("[DIAG][service] "):
            continue

        parts = line.split(maxsplit=2)
        if len(parts) < 2:
            continue
        channel = "direct" if line.startswith("[DIAG][direct] ") else "service"
        label = parts[1]
        text = line.split(" text=", 1)[1] if " text=" in line else ""
        if " empty=" in line:
            empty = line.split(" empty=", 1)[1].split(maxsplit=1)[0] == "true"
        else:
            empty = not text.strip()

        rows.append({
            "path": diagnostic_path,
            "reported_path": channel,
            "variant": variant,
            "repeat": repeat,
            "label": label,
            "returncode": returncode,
            "empty": empty,
            "text_chars": len(text.strip()),
            "ref_len": capture_value(line, r"refLen=([^ ]+)"),
            "rms_db": capture_value(line, r"rms=([^ ]+)dB"),
            "segments": capture_value(line, r"segments=([0-9]+)"),
            "progress": capture_value(line, r"progress=([0-9]+)"),
            "text_preview": text.strip().replace("|", "\\|")[:120],
        })
    return rows


def capture_value(text, pattern):
    match = re.search(pattern, text)
    return match.group(1) if match else ""


def run_case(root, args, labels, output_root, diagnostic_path, variant, repeat):
    case_dir = output_root / safe_path(diagnostic_path) / safe_path(variant) / f"repeat-{repeat}"
    case_dir.mkdir(parents=True, exist_ok=True)
    command = make_command(args)
    env = make_env(args, labels, diagnostic_path, variant)
    log_path = case_dir / "swift-test.log"
    started = time.perf_counter()

    print(f"==> path={diagnostic_path} variant={variant} repeat={repeat}", flush=True)
    if args.dry_run:
        return {
            "path": diagnostic_path,
            "variant": variant,
            "repeat": repeat,
            "status": "dry_run",
            "returncode": None,
            "elapsed_seconds": 0,
            "log_path": str(log_path),
            "rows": [],
            "command": command,
        }

    completed = subprocess.run(
        command,
        cwd=root,
        env=env,
        text=True,
        capture_output=True,
    )
    elapsed = time.perf_counter() - started
    output = completed.stdout + completed.stderr
    log_path.write_text(output, encoding="utf-8")
    rows = parse_diag_rows(output, diagnostic_path, variant, repeat, completed.returncode)
    status = "passed" if completed.returncode == 0 else "failed"
    empty_count = sum(1 for row in rows if row["empty"])
    print(f"    {status}: rows={len(rows)} empty={empty_count} elapsed={elapsed:.1f}s log={log_path}", flush=True)

    return {
        "path": diagnostic_path,
        "variant": variant,
        "repeat": repeat,
        "status": status,
        "returncode": completed.returncode,
        "elapsed_seconds": elapsed,
        "log_path": str(log_path),
        "rows": rows,
        "command": command,
    }


def write_outputs(output_root, manifest, rows):
    output_root.mkdir(parents=True, exist_ok=True)
    manifest_path = output_root / "run_manifest.json"
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True),
        encoding="utf-8",
    )

    csv_path = output_root / "summary.csv"
    fieldnames = [
        "path",
        "reported_path",
        "variant",
        "repeat",
        "label",
        "returncode",
        "empty",
        "text_chars",
        "ref_len",
        "rms_db",
        "segments",
        "progress",
        "text_preview",
    ]
    with csv_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    summary_path = output_root / "summary.md"
    lines = [
        "| Path | Variant | Repeat | Label | Empty | Text chars | Ref len | RMS dB | Segments | Progress | Preview |",
        "| --- | --- | ---: | --- | --- | ---: | ---: | ---: | ---: | ---: | --- |",
    ]
    for row in rows:
        lines.append(
            "| {path} | {variant} | {repeat} | {label} | {empty} | {text_chars} | {ref_len} | {rms_db} | {segments} | {progress} | {text_preview} |".format(
                **row
            )
        )
    summary_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return manifest_path, csv_path, summary_path


def main():
    args = parse_args()
    if args.repeats < 1:
        raise SystemExit("--repeats must be >= 1")

    root = args.root.expanduser().resolve()
    output_root = (args.output_root or default_output_root(root)).expanduser().resolve()
    labels = split_csv(args.labels)
    variants = split_csv(args.variants)
    paths = split_csv(args.paths)
    if not labels:
        raise SystemExit("No labels selected")
    if not variants:
        raise SystemExit("No variants selected")
    if not paths:
        raise SystemExit("No paths selected")

    manifest = {
        "schema_version": 1,
        "started_at": datetime.now().isoformat(timespec="seconds"),
        "root": str(root),
        "output_root": str(output_root),
        "probe_set": args.probe_set,
        "labels": labels,
        "variants": variants,
        "paths": paths,
        "repeats": args.repeats,
        "configuration": args.configuration,
        "service_per_variant": args.service_per_variant,
        "dry_run": args.dry_run,
        "runs": [],
    }
    all_rows = []

    for diagnostic_path in paths:
        for variant in variants_for_path(diagnostic_path, variants, args.service_per_variant):
            for repeat in range(1, args.repeats + 1):
                run = run_case(root, args, labels, output_root, diagnostic_path, variant, repeat)
                all_rows.extend(run["rows"])
                manifest["runs"].append(run)
                write_outputs(output_root, manifest, all_rows)
                if args.fail_fast and run["status"] == "failed":
                    return run["returncode"] or 1

    manifest_path, csv_path, summary_path = write_outputs(output_root, manifest, all_rows)
    print(f"wrote: {manifest_path}", flush=True)
    print(f"wrote: {csv_path}", flush=True)
    print(f"wrote: {summary_path}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
