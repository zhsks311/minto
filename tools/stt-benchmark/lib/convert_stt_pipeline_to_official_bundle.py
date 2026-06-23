#!/usr/bin/env python3
import argparse
import csv
import json
import platform
from pathlib import Path

import validate_stt_benchmark_manifest as validator


APPLE_ENGINE_IDS = {"speech_analyzer", "sf_speech_on_device"}
SIDECAR_ENGINE_IDS = {"nemotron"}
STREAMING_ENGINE_IDS = {"sherpa", "nemotron"}
PLACEHOLDER_CER = 1.0


def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        description="Convert STT pipeline outputs into official benchmark manifests and a run bundle."
    )
    parser.add_argument("--pipeline-manifest", type=Path, action="append", required=True)
    parser.add_argument("--reference-version", required=True)
    parser.add_argument("--sample-set")
    parser.add_argument("--official-benchmark-kind")
    parser.add_argument(
        "--engine-id-alias",
        action="append",
        default=[],
        metavar="RAW=CANONICAL",
        help="Map a pipeline engine id to the official comparison engine id.",
    )
    parser.add_argument("--product-path", action="store_true")
    parser.add_argument("--output-root", type=Path, required=True)
    return parser.parse_args(argv)


def read_json(path):
    return json.loads(path.expanduser().read_text(encoding="utf-8"))


def write_json(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def read_csv_rows(path):
    with path.open(encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def validate_manifest(payload, label):
    errors = validator.validate_manifest(payload)
    if errors:
        raise SystemExit(f"{label} is invalid: {'; '.join(errors)}")


def float_or_none(value):
    if value in (None, ""):
        return None
    try:
        return float(value)
    except ValueError:
        return None


def int_or_zero(value):
    number = float_or_none(value)
    return int(number) if number is not None else 0


def non_negative_float_or_none(value):
    number = float_or_none(value)
    if number is None or number < 0:
        return None
    return number


def non_negative_int_or_none(value):
    number = float_or_none(value)
    if number is None or number < 0 or int(number) != number:
        return None
    return int(number)


def ratio_or_none(value):
    number = float_or_none(value)
    if number is None or number < 0 or number > 1:
        return None
    return number


def safe_id(value):
    return "".join(char if char.isalnum() or char in "._-" else "_" for char in str(value)).strip("_") or "run"


def summary_csv_path(pipeline_manifest_path, pipeline):
    benchmark_root = pipeline.get("benchmark_root")
    if benchmark_root:
        return Path(benchmark_root).expanduser() / "summary.csv"
    return pipeline_manifest_path.parent / "benchmark" / "summary.csv"


def child_run_manifest_path(pipeline_manifest_path, pipeline):
    benchmark_root = pipeline.get("benchmark_root")
    if benchmark_root:
        return Path(benchmark_root).expanduser() / "run_manifest.json"
    return pipeline_manifest_path.parent / "benchmark" / "run_manifest.json"


def load_child_run_manifest(pipeline_manifest_path, pipeline):
    path = child_run_manifest_path(pipeline_manifest_path, pipeline)
    if not path.exists():
        return path, {}
    return path, read_json(path)


def split_engines(value):
    if isinstance(value, list):
        return [str(item) for item in value if str(item)]
    return [part.strip() for part in str(value or "").split(",") if part.strip()]


def engine_aliases(args):
    aliases = {}
    for item in getattr(args, "engine_id_alias", []) or []:
        if "=" not in item:
            raise SystemExit(f"--engine-id-alias must be RAW=CANONICAL; got {item!r}")
        raw, canonical = item.split("=", 1)
        raw = raw.strip()
        canonical = canonical.strip()
        if not raw or not canonical:
            raise SystemExit(f"--engine-id-alias must be RAW=CANONICAL; got {item!r}")
        aliases[raw] = canonical
    return aliases


def canonical_engine_id(engine_id, aliases):
    return aliases.get(engine_id, engine_id)


def runs_by_engine(child_manifest, aliases):
    grouped = {}
    for run in child_manifest.get("runs") or []:
        engine = run.get("engine")
        if not engine:
            continue
        engine = canonical_engine_id(engine, aliases)
        grouped.setdefault(engine, []).append(run)
    return grouped


def status_counts(runs):
    counts = {}
    for run in runs:
        status = run.get("status") or "unknown"
        counts[status] = counts.get(status, 0) + 1
    return counts


def engine_health_status(runs, pipeline_status):
    counts = status_counts(runs)
    if counts.get("passed") and not any(
        counts.get(status)
        for status in ["failed", "timeout", "disk_space_low", "skipped_unavailable"]
    ):
        return "ready"
    if counts.get("skipped_unavailable") and counts.get("passed", 0) == 0:
        return "skipped_unavailable"
    if counts.get("disk_space_low"):
        return "disk_space_low"
    if counts.get("timeout"):
        return "timeout"
    if counts.get("failed"):
        return "failed"
    if counts.get("dry_run") and len(counts) == 1:
        return "dry_run"
    return pipeline_status or "unknown"


def failure_modes_for(runs):
    modes = []
    for status, count in sorted(status_counts(runs).items()):
        if status == "passed":
            continue
        modes.append(f"{status}:{count}")
    reasons = sorted({
        run.get("skip_reason")
        for run in runs
        if run.get("skip_reason")
    })
    modes.extend(f"skip_reason:{reason}" for reason in reasons)
    return modes


def official_benchmark_kind(row, engine_id, args):
    if args.product_path:
        return "product_path_final"
    if args.official_benchmark_kind:
        return args.official_benchmark_kind

    raw_kind = row.get("benchmark_kind") or ""
    if raw_kind == "rolling_preview_final":
        return "rolling_preview"
    if raw_kind == "true_streaming_session":
        return "true_streaming"
    if engine_id in SIDECAR_ENGINE_IDS:
        return "sidecar_final"
    return "offline_final"


def runtime_for(engine_id):
    if engine_id.startswith("whisper_"):
        return "whisperkit_coreml"
    if engine_id in APPLE_ENGINE_IDS:
        return "apple_speech"
    if engine_id == "sherpa":
        return "sherpa_onnx"
    if engine_id == "nemotron":
        return "mlx_sidecar"
    return engine_id


def requires_os_version(engine_id):
    if engine_id == "speech_analyzer":
        return "macOS 26"
    if engine_id == "sf_speech_on_device":
        return "macOS 10.15"
    return "macOS"


def supports_streaming(engine_id, benchmark_kind):
    return benchmark_kind == "true_streaming" or engine_id in STREAMING_ENGINE_IDS


def sample_set(args, pipeline, child_manifest):
    if args.sample_set:
        return args.sample_set
    samples = pipeline.get("samples") or child_manifest.get("samples")
    if samples:
        return str(samples)
    sample_count = child_manifest.get("sample_count")
    if sample_count:
        return f"meeting-{sample_count}sample"
    summary = pipeline.get("benchmark_summary") or {}
    run_count = summary.get("run_count")
    return f"meeting-{run_count}run" if run_count else "meeting-sample-set"


def input_contract():
    return {
        "sample_rate_hz": 16000,
        "channels": 1,
        "format": "wav",
    }


def runner_contract(pipeline, child_manifest):
    return {
        "window_sec": pipeline.get("window_sec", child_manifest.get("window_sec")),
        "min_window_sec": pipeline.get("min_window_sec", child_manifest.get("min_window_sec")),
        "max_gap_sec": pipeline.get("max_gap_sec", child_manifest.get("max_gap_sec")),
        "audio_pad_sec": pipeline.get("audio_pad_sec", child_manifest.get("audio_pad_sec")),
        "max_captions_per_window": pipeline.get(
            "max_captions_per_window",
            child_manifest.get("max_captions_per_window"),
        ),
        "max_windows": pipeline.get("max_windows", child_manifest.get("max_windows")),
        "timeout_sec": pipeline.get("timeout_sec", child_manifest.get("timeout_sec")),
        "configuration": child_manifest.get("configuration"),
        "skip_build": pipeline.get("skip_build", child_manifest.get("skip_build")),
        "dry_run": pipeline.get("dry_run", child_manifest.get("dry_run")) is True,
    }


def pipeline_engine_ids(pipeline, child_manifest):
    ids = []
    ids.extend(split_engines(pipeline.get("engines")))
    ids.extend(split_engines(child_manifest.get("engines")))
    if pipeline.get("engine"):
        ids.append(str(pipeline["engine"]))
    if child_manifest.get("engine"):
        ids.append(str(child_manifest["engine"]))
    result = []
    seen = set()
    for engine_id in ids:
        if engine_id and engine_id not in seen:
            result.append(engine_id)
            seen.add(engine_id)
    return result


def canonical_summary_row(row, aliases):
    engine_id = row.get("engine_id")
    canonical_id = canonical_engine_id(engine_id, aliases) if engine_id else engine_id
    if canonical_id == engine_id:
        return row
    updated = dict(row)
    updated["engine_id"] = canonical_id
    updated["source_engine_id"] = engine_id
    return updated


def build_benchmark_manifest(
    pipeline_manifest_path,
    pipeline,
    child_manifest_path,
    child_manifest,
    summary_path,
    row,
    engine_id,
    benchmark_kind,
    run_suffix,
    args,
):
    product_path = benchmark_kind == "product_path_final"
    run_id = "-".join([
        safe_id(args.reference_version),
        safe_id(engine_id),
        safe_id(benchmark_kind),
        safe_id(run_suffix),
    ])
    return {
        "manifest_type": "benchmark_run_manifest",
        "schema_version": 1,
        "run_id": run_id,
        "created_at": pipeline.get("finished_at") or pipeline.get("started_at") or "",
        "benchmark_kind": benchmark_kind,
        "product_path": product_path,
        "engine_id": engine_id,
        "engine_label": row.get("engine_label") or engine_id,
        "model_id": row.get("model_id") or f"{engine_id}-model",
        "model_version": "",
        "model_hash": "",
        "runtime": runtime_for(engine_id),
        "os_version": platform.mac_ver()[0] or platform.platform(),
        "hardware": platform.machine() or "unknown",
        "reference_version": args.reference_version,
        "sample_set": sample_set(args, pipeline, child_manifest),
        "input_contract": input_contract(),
        "runner_contract": runner_contract(pipeline, child_manifest),
        "output_paths": [
            str(pipeline_manifest_path.resolve()),
            str(child_manifest_path.resolve()),
            str(summary_path.resolve()),
        ],
    }


def build_metric_summary(row, runs, pipeline):
    status = engine_health_status(runs, pipeline.get("status"))
    has_summary_metric = bool(row.get("weighted_micro_cer") or row.get("sample_macro_cer"))
    sample_count = int_or_zero(row.get("sample_count")) if has_summary_metric else 0
    weighted_cer = float_or_none(row.get("weighted_micro_cer"))
    macro_cer = float_or_none(row.get("sample_macro_cer"))
    user_impact_metrics = build_user_impact_metrics(row)
    payload = {
        "manifest_type": "metric_summary",
        "schema_version": 1,
        # baseline_cer is filled only after official runs expose raw uncorrected CER.
        # phantom_rate is filled only after official runs expose phantom segment counts.
        "sample_count": sample_count,
        "weighted_cer": weighted_cer if weighted_cer is not None else PLACEHOLDER_CER,
        "macro_cer": macro_cer if macro_cer is not None else PLACEHOLDER_CER,
        "empty_final_count": int_or_zero(row.get("empty_final_count")),
        "timeout_count": sum(1 for run in runs if run.get("status") == "timeout"),
        "crash_count": sum(1 for run in runs if run.get("status") == "failed"),
        "sidecar_unavailable_count": sum(
            1 for run in runs if run.get("status") == "skipped_unavailable"
        ),
        "global_cer": float_or_none(row.get("global_cer_mean")),
        "full_reference_global_cer": float_or_none(row.get("full_reference_global_cer")),
        "false_positive_chars": int_or_zero(row.get("false_positive_chars")),
        "rtf_mean": float_or_none(row.get("rtf")),
        "peak_memory_mb": float_or_none(row.get("peak_memory_mb")),
        "metric_status": "measured" if has_summary_metric else status,
        "metric_placeholder": not has_summary_metric,
        "user_impact_metric_complete": user_impact_metrics is not None,
    }
    if user_impact_metrics is not None:
        payload["user_impact_metrics"] = user_impact_metrics
    return payload


def build_user_impact_metrics(row):
    fields = {
        "time_to_first_visible_text_seconds": non_negative_float_or_none(
            row.get("time_to_first_visible_text_seconds")
        ),
        "final_transcript_delay_seconds": non_negative_float_or_none(
            row.get("final_transcript_delay_seconds")
        ),
        "preview_revision_count": non_negative_int_or_none(
            row.get("preview_revision_count")
        ),
        "unstable_partial_ratio": ratio_or_none(row.get("unstable_partial_ratio")),
        "empty_visible_transcript_count": non_negative_int_or_none(
            row.get("empty_visible_transcript_count")
        ),
        "permission_asset_failure_count": non_negative_int_or_none(
            row.get("permission_asset_failure_count")
        ),
        "sidecar_startup_failure_count": non_negative_int_or_none(
            row.get("sidecar_startup_failure_count")
        ),
        "peak_memory_mb": non_negative_float_or_none(row.get("peak_memory_mb")),
        "cold_start_seconds": non_negative_float_or_none(row.get("cold_start_seconds")),
        "user_visible_fallback_event_count": non_negative_int_or_none(
            row.get("user_visible_fallback_event_count")
        ),
    }
    if any(value is None for value in fields.values()):
        return None
    return fields


def build_engine_manifest(row, runs, engine_id, benchmark_kind, pipeline):
    return {
        "manifest_type": "engine_manifest",
        "schema_version": 1,
        "engine_id": engine_id,
        "model_id": row.get("model_id") or f"{engine_id}-model",
        "runtime": runtime_for(engine_id),
        "supports_offline": benchmark_kind != "true_streaming",
        "supports_streaming": supports_streaming(engine_id, benchmark_kind),
        "requires_network": False,
        "requires_sidecar": engine_id in SIDECAR_ENGINE_IDS,
        "requires_os_version": requires_os_version(engine_id),
        "requires_user_permission": engine_id in APPLE_ENGINE_IDS,
        "health_status": engine_health_status(runs, pipeline.get("status")),
        "failure_modes": failure_modes_for(runs),
    }


def placeholder_row(engine_id):
    return {
        "engine_id": engine_id,
        "engine_label": engine_id,
        "model_id": f"{engine_id}-model",
        "benchmark_kind": "",
    }


def write_run(output_root, payloads, run_suffix):
    engine_id = payloads["benchmark"]["engine_id"]
    benchmark_kind = payloads["benchmark"]["benchmark_kind"]
    run_root = output_root / f"{safe_id(engine_id)}_{safe_id(benchmark_kind)}_{safe_id(run_suffix)}"
    benchmark_path = run_root / "benchmark_run_manifest.json"
    metric_path = run_root / "metric_summary.json"
    engine_path = run_root / "engine_manifest.json"
    write_json(benchmark_path, payloads["benchmark"])
    write_json(metric_path, payloads["metric"])
    write_json(engine_path, payloads["engine"])
    return {
        "engine_id": engine_id,
        "benchmark_run_manifest": str(benchmark_path.relative_to(output_root)),
        "metric_summary": str(metric_path.relative_to(output_root)),
        "engine_manifest": str(engine_path.relative_to(output_root)),
    }


def build_for_pipeline(args, output_root, pipeline_manifest_path):
    pipeline_path = pipeline_manifest_path.expanduser().resolve()
    aliases = engine_aliases(args)
    pipeline = read_json(pipeline_path)
    summary_path = summary_csv_path(pipeline_path, pipeline)
    child_path, child_manifest = load_child_run_manifest(pipeline_path, pipeline)
    summary_rows = read_csv_rows(summary_path) if summary_path.exists() else []
    grouped_runs = runs_by_engine(child_manifest, aliases)
    expected_engines = [
        canonical_engine_id(engine_id, aliases)
        for engine_id in pipeline_engine_ids(pipeline, child_manifest)
    ]
    rows = [canonical_summary_row(row, aliases) for row in summary_rows]
    row_engine_ids = {row.get("engine_id") for row in rows}
    for engine_id in expected_engines:
        if engine_id not in row_engine_ids:
            rows.append(placeholder_row(engine_id))

    bundle_runs = []
    for index, row in enumerate(rows, start=1):
        engine_id = row.get("engine_id")
        if not engine_id:
            continue
        runs = grouped_runs.get(engine_id, [])
        benchmark_kind = official_benchmark_kind(row, engine_id, args)
        run_suffix = f"run{index}"
        payloads = {
            "benchmark": build_benchmark_manifest(
                pipeline_path,
                pipeline,
                child_path,
                child_manifest,
                summary_path,
                row,
                engine_id,
                benchmark_kind,
                run_suffix,
                args,
            ),
            "metric": build_metric_summary(row, runs, pipeline),
            "engine": build_engine_manifest(row, runs, engine_id, benchmark_kind, pipeline),
        }
        for name, payload in payloads.items():
            validate_manifest(payload, f"{engine_id} {name}")
        bundle_runs.append(write_run(output_root, payloads, run_suffix))
    return bundle_runs


def build_bundle(args):
    output_root = args.output_root.expanduser().resolve()
    bundle_runs = []
    for pipeline_manifest_path in args.pipeline_manifest:
        bundle_runs.extend(build_for_pipeline(args, output_root, pipeline_manifest_path))
    payload = {
        "manifest_type": "engine_run_bundle_manifest",
        "schema_version": 1,
        "reference_version": args.reference_version,
        "bundle_count": len(bundle_runs),
        "runs": bundle_runs,
    }
    validate_manifest(payload, "engine run bundle")
    return output_root, payload


def run(args):
    output_root, payload = build_bundle(args)
    output_path = output_root / "engine_run_bundle_manifest.json"
    write_json(output_path, payload)
    print(f"wrote: {output_path}")
    print(f"bundle_count: {payload['bundle_count']}")
    return {"payload": payload, "output_path": output_path}


def main(argv=None):
    return 0 if run(parse_args(argv)) else 1


if __name__ == "__main__":
    raise SystemExit(main())
