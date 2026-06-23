#!/usr/bin/env python3
import argparse
import csv
import json
from pathlib import Path

import stt_engine_verdict as verdict
import validate_stt_benchmark_manifest as validator


CSV_FIELDNAMES = [
    "engine_id",
    "engine_label",
    "lane",
    "benchmark_kind",
    "product_path",
    "default_gate_input",
    "runtime",
    "model_id",
    "requires_sidecar",
    "supports_streaming",
    "reference_version",
    "sample_set",
    "sample_count",
    "weighted_cer",
    "macro_cer",
    "empty_final_count",
    "timeout_count",
    "crash_count",
    "user_impact_metric_complete",
    "health_status",
]


def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        description="Build an official STT engine lane matrix from normalized benchmark manifests."
    )
    parser.add_argument("--run-bundle-manifest", type=Path, action="append", default=[])
    parser.add_argument("--benchmark-run-manifest", type=Path, action="append", default=[])
    parser.add_argument("--metric-summary", type=Path, action="append", default=[])
    parser.add_argument("--engine-manifest", type=Path, action="append", default=[])
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


def validate_input(payload, expected_type, label):
    errors = validator.validate_manifest(payload)
    if errors:
        raise SystemExit(f"{label} is invalid: {'; '.join(errors)}")
    if payload.get("manifest_type") != expected_type:
        raise SystemExit(f"{label} must have manifest_type={expected_type}")


def resolve_bundle_path(bundle_path, value):
    path = Path(value).expanduser()
    if path.is_absolute():
        return path
    return bundle_path.parent / path


def collect_run_specs(args):
    specs = []
    benchmark_paths = getattr(args, "benchmark_run_manifest", []) or []
    metric_paths = getattr(args, "metric_summary", []) or []
    engine_paths = getattr(args, "engine_manifest", []) or []
    if any([benchmark_paths, metric_paths, engine_paths]):
        if not (len(benchmark_paths) == len(metric_paths) == len(engine_paths)):
            raise SystemExit("--benchmark-run-manifest, --metric-summary, and --engine-manifest counts must match")
        for benchmark_path, metric_path, engine_path in zip(benchmark_paths, metric_paths, engine_paths):
            specs.append({
                "benchmark_run_manifest": benchmark_path,
                "metric_summary": metric_path,
                "engine_manifest": engine_path,
            })

    for run_bundle_manifest in getattr(args, "run_bundle_manifest", []) or []:
        bundle_path = run_bundle_manifest.expanduser().resolve()
        bundle = read_json(bundle_path)
        validate_input(bundle, "engine_run_bundle_manifest", f"run bundle {bundle_path}")
        for run in bundle.get("runs", []):
            specs.append({
                "engine_id": run["engine_id"],
                "declared_reference_version": bundle["reference_version"],
                "run_bundle_manifest": bundle_path,
                "benchmark_run_manifest": resolve_bundle_path(bundle_path, run["benchmark_run_manifest"]),
                "metric_summary": resolve_bundle_path(bundle_path, run["metric_summary"]),
                "engine_manifest": resolve_bundle_path(bundle_path, run["engine_manifest"]),
            })

    if not specs:
        raise SystemExit("provide at least one direct run triplet or --run-bundle-manifest")
    return specs


def lane_for(benchmark, engine):
    benchmark_kind = benchmark.get("benchmark_kind", "")
    if benchmark_kind == "product_path_final":
        return "product_path_final"
    if benchmark_kind == "sidecar_final" or engine.get("requires_sidecar") is True:
        return "sidecar_final"
    if benchmark_kind in {"rolling_preview", "true_streaming"}:
        return benchmark_kind
    return benchmark_kind or "unknown"


def default_gate_input(benchmark, metric, engine):
    return (
        benchmark.get("product_path") is True
        and benchmark.get("benchmark_kind") == "product_path_final"
        and (benchmark.get("runner_contract") or {}).get("dry_run") is not True
        and engine.get("health_status") == "ready"
        and engine.get("requires_sidecar") is not True
        and metric.get("user_impact_metric_complete") is True
        and isinstance(metric.get("user_impact_metrics"), dict)
    )


def build_row(benchmark, metric, engine, source_paths):
    return {
        "engine_id": benchmark.get("engine_id", engine.get("engine_id", "")),
        "engine_label": benchmark.get("engine_label", ""),
        "lane": lane_for(benchmark, engine),
        "benchmark_kind": benchmark.get("benchmark_kind", ""),
        "product_path": benchmark.get("product_path"),
        "default_gate_input": default_gate_input(benchmark, metric, engine),
        "runtime": engine.get("runtime", benchmark.get("runtime", "")),
        "model_id": benchmark.get("model_id", engine.get("model_id", "")),
        "requires_sidecar": engine.get("requires_sidecar"),
        "supports_streaming": engine.get("supports_streaming"),
        "reference_version": benchmark.get("reference_version", ""),
        "sample_set": benchmark.get("sample_set", ""),
        "sample_count": metric.get("sample_count"),
        "weighted_cer": metric.get("weighted_cer"),
        "cer_ci95_half_width": metric.get("cer_ci95_half_width"),
        "macro_cer": metric.get("macro_cer"),
        "empty_final_count": metric.get("empty_final_count"),
        "timeout_count": metric.get("timeout_count"),
        "crash_count": metric.get("crash_count"),
        "user_impact_metric_complete": bool(metric.get("user_impact_metric_complete")),
        "health_status": engine.get("health_status", ""),
        "source_paths": source_paths,
    }


def build_engine_ranking(rows):
    # ADR 0004 항목③ + 판정규칙: 엔진을 cer 오름차순으로 순위화하되, 95% CI가 겹치면
    # 무승부(tie)로 묶는다 — 순위/무승부 판정은 stt_engine_verdict.rank_with_ties에 위임한다.
    # lane matrix의 rows는 (benchmark × engine) 조합이라 같은 engine_id가 여러 lane으로
    # 들어올 수 있으므로, 엔진별 최저(최선) weighted_cer 1개만 대표로 dedup해 엔진 단위
    # 순위를 보장한다(row 단위가 아니라). weighted_cer None/누락·engine_id 빈값 row는 제외.
    # CI(cer_ci95_half_width)는 반복측정(stt_repeat_statistics)에서 채워지며, 없으면(단일 런)
    # 무승부 없이 단순 순위가 된다 — 실측 전/후 모두 동작하는 호환 구조.
    # 한계: 서로 다른 lane/benchmark_kind를 한 순위에 섞는 것은 comparability상 불완전하므로,
    # 실제 재실행 데이터 확인 후 lane별 분리를 검토한다.
    best_by_engine = {}
    for row in rows:
        cer = row.get("weighted_cer")
        if not isinstance(cer, (int, float)) or isinstance(cer, bool):
            continue
        engine_id = row.get("engine_id", "")
        if not engine_id:
            continue
        if engine_id not in best_by_engine or cer < best_by_engine[engine_id]["cer_mean"]:
            best_by_engine[engine_id] = {
                "engine_id": engine_id,
                "cer_mean": cer,
                "cer_ci95_half_width": row.get("cer_ci95_half_width"),
            }
    ranked = verdict.rank_with_ties(list(best_by_engine.values()))
    return [
        {
            "rank": item["rank"],
            "tie_group": item["tie_group"],
            "engine_id": item["engine_id"],
            "weighted_cer": item["cer_mean"],
        }
        for item in ranked
    ]


def build_matrix(args):
    run_specs = collect_run_specs(args)
    rows = []
    source_paths = []
    for index, spec in enumerate(run_specs):
        benchmark_path = spec["benchmark_run_manifest"]
        metric_path = spec["metric_summary"]
        engine_path = spec["engine_manifest"]
        benchmark = read_json(benchmark_path)
        metric = read_json(metric_path)
        engine = read_json(engine_path)
        validate_input(benchmark, "benchmark_run_manifest", f"benchmark[{index}]")
        validate_input(metric, "metric_summary", f"metric[{index}]")
        validate_input(engine, "engine_manifest", f"engine[{index}]")
        validate_run_spec_alignment(spec, benchmark, engine, index)
        paths = {
            "benchmark_run_manifest": str(benchmark_path.expanduser().resolve()),
            "metric_summary": str(metric_path.expanduser().resolve()),
            "engine_manifest": str(engine_path.expanduser().resolve()),
        }
        if spec.get("run_bundle_manifest"):
            paths["run_bundle_manifest"] = str(spec["run_bundle_manifest"])
        rows.append(build_row(benchmark, metric, engine, paths))
        source_paths.extend(paths.values())

    reference_versions = sorted({row["reference_version"] for row in rows if row.get("reference_version")})
    payload = {
        "manifest_type": "engine_lane_matrix",
        "schema_version": 1,
        "reference_versions": reference_versions,
        "entry_count": len(rows),
        "lanes": rows,
        "engine_ranking": build_engine_ranking(rows),
        "source_paths": source_paths,
    }
    errors = validator.validate_manifest(payload)
    if errors:
        raise SystemExit("engine lane matrix is invalid: " + "; ".join(errors))
    return payload


def validate_run_spec_alignment(spec, benchmark, engine, index):
    benchmark_engine_id = benchmark.get("engine_id")
    engine_manifest_id = engine.get("engine_id")
    if benchmark_engine_id != engine_manifest_id:
        raise SystemExit(
            f"run[{index}] engine_id mismatch: "
            f"benchmark_run_manifest={benchmark_engine_id!r}, engine_manifest={engine_manifest_id!r}"
        )
    declared_engine_id = spec.get("engine_id")
    if declared_engine_id and declared_engine_id != benchmark_engine_id:
        raise SystemExit(
            f"run[{index}] bundle engine_id={declared_engine_id!r} "
            f"does not match benchmark engine_id={benchmark_engine_id!r}"
        )
    declared_reference_version = spec.get("declared_reference_version")
    if declared_reference_version and declared_reference_version != benchmark.get("reference_version"):
        raise SystemExit(
            f"run[{index}] bundle reference_version={declared_reference_version!r} "
            f"does not match benchmark reference_version={benchmark.get('reference_version')!r}"
        )


def write_csv(path, rows):
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=CSV_FIELDNAMES, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def write_markdown(path, rows):
    lines = [
        "# STT Engine Lane Matrix",
        "",
        "| Engine | Lane | Product path | Default gate input | CER | Empty | Runtime | Sidecar |",
        "| --- | --- | --- | --- | ---: | ---: | --- | --- |",
    ]
    for row in rows:
        lines.append(
            "| {engine} | {lane} | {product} | {default_gate} | {cer} | {empty} | {runtime} | {sidecar} |".format(
                engine=escape_cell(row["engine_id"]),
                lane=escape_cell(row["lane"]),
                product=str(row["product_path"]).lower(),
                default_gate=str(row["default_gate_input"]).lower(),
                cer=row["weighted_cer"],
                empty=row["empty_final_count"],
                runtime=escape_cell(row["runtime"]),
                sidecar=str(row["requires_sidecar"]).lower(),
            )
        )
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def escape_cell(value):
    return str(value or "").replace("|", "\\|").replace("\n", " ")


def run(args):
    payload = build_matrix(args)
    output_root = args.output_root.expanduser().resolve()
    json_path = output_root / "engine_lane_matrix.json"
    csv_path = output_root / "engine_lane_matrix.csv"
    md_path = output_root / "engine_lane_matrix.md"
    write_json(json_path, payload)
    write_csv(csv_path, payload["lanes"])
    write_markdown(md_path, payload["lanes"])
    print(f"wrote: {json_path}")
    print(f"wrote: {csv_path}")
    print(f"wrote: {md_path}")
    print(f"entry_count: {payload['entry_count']}")
    return {"payload": payload, "json_path": json_path, "csv_path": csv_path, "md_path": md_path}


def main(argv=None):
    return 0 if run(parse_args(argv)) else 1


if __name__ == "__main__":
    raise SystemExit(main())
