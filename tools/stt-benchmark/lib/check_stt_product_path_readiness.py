#!/usr/bin/env python3
import argparse
import json
from pathlib import Path

import validate_stt_benchmark_manifest as validator


def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        description="Check whether product-path STT lanes are ready for default-gate decisions."
    )
    parser.add_argument("--engine-lane-matrix", type=Path, required=True)
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


def stable_unique(values):
    result = []
    seen = set()
    for value in values:
        if not isinstance(value, str) or not value or value in seen:
            continue
        result.append(value)
        seen.add(value)
    return result


def product_path_rows(matrix):
    return [
        row
        for row in matrix.get("lanes", [])
        if row.get("lane") == "product_path_final" and row.get("product_path") is True
    ]


def row_source_path(row, name):
    source_paths = row.get("source_paths") or {}
    value = source_paths.get(name)
    if not value:
        raise SystemExit(f"product path row {row.get('engine_id')!r} is missing source path {name}")
    return Path(value).expanduser().resolve()


def load_product_row_inputs(row):
    benchmark_path = row_source_path(row, "benchmark_run_manifest")
    metric_path = row_source_path(row, "metric_summary")
    benchmark = read_json(benchmark_path)
    metric = read_json(metric_path)
    validate_input(benchmark, "benchmark_run_manifest", f"benchmark {benchmark_path}")
    validate_input(metric, "metric_summary", f"metric {metric_path}")
    return benchmark_path, metric_path, benchmark, metric


def product_row_status(row):
    benchmark_path, metric_path, benchmark, metric = load_product_row_inputs(row)
    user_impact_complete = (
        metric.get("user_impact_metric_complete") is True
        and isinstance(metric.get("user_impact_metrics"), dict)
    )
    return {
        "engine_id": row.get("engine_id", ""),
        "default_gate_input": row.get("default_gate_input") is True,
        "dry_run": (benchmark.get("runner_contract") or {}).get("dry_run") is True,
        "health_not_ready": row.get("health_status") != "ready",
        "requires_sidecar": row.get("requires_sidecar") is True,
        "user_impact_incomplete": not user_impact_complete,
        "evidence_paths": [str(benchmark_path), str(metric_path)],
    }


def readiness_state(counts):
    if counts["product_path_default_gate_input_count"]:
        return "ready_for_product_path_default_gate"
    if counts["product_path_lane_count"] == 0:
        return "blocked_no_product_path_runs"
    if counts["dry_run_product_path_lane_count"] or counts["sidecar_required_lane_count"]:
        return "blocked_product_path_contract"
    if counts["health_not_ready_lane_count"]:
        return "blocked_product_path_health"
    return "blocked_user_impact_metrics"


def reasons_for(state, counts):
    if state == "ready_for_product_path_default_gate":
        return ["at least one product_path_final lane can enter the default gate"]
    reasons = []
    if counts["product_path_lane_count"] == 0:
        reasons.append("no product_path_final lane exists in the engine lane matrix")
    if counts["dry_run_product_path_lane_count"]:
        reasons.append(
            f"product_path_final dry-run lane count={counts['dry_run_product_path_lane_count']}"
        )
    if counts["sidecar_required_lane_count"]:
        reasons.append(
            f"product_path_final sidecar-required lane count={counts['sidecar_required_lane_count']}"
        )
    if counts["health_not_ready_lane_count"]:
        reasons.append(
            f"product_path_final health-not-ready lane count={counts['health_not_ready_lane_count']}"
        )
    if counts["user_impact_incomplete_lane_count"]:
        reasons.append(
            "product_path_final user-impact metric incomplete lane count="
            f"{counts['user_impact_incomplete_lane_count']}"
        )
    if not reasons:
        reasons.append("no product_path_final lane can enter the default gate")
    return reasons


def blocking_gates_for(state, counts):
    if state == "ready_for_product_path_default_gate":
        return []
    gates = []
    if counts["product_path_lane_count"] == 0:
        gates.append("missing_product_path_run")
    if counts["dry_run_product_path_lane_count"]:
        gates.append("product_path_dry_run")
    if counts["sidecar_required_lane_count"]:
        gates.append("product_path_requires_sidecar")
    if counts["health_not_ready_lane_count"]:
        gates.append("product_path_engine_not_ready")
    if counts["user_impact_incomplete_lane_count"]:
        gates.append("missing_user_impact_metric")
    if not gates:
        gates.append("missing_product_path_default_gate_input")
    return sorted(set(gates))


def next_actions_for(state):
    if state == "ready_for_product_path_default_gate":
        return ["Use the product-path default gate candidate in the official decision workflow."]
    if state == "blocked_no_product_path_runs":
        return ["Run a real product-path STT benchmark and convert it into the official run bundle."]
    if state == "blocked_product_path_contract":
        return ["Rerun product-path benchmarks without dry-run mode and without sidecar-only default candidates."]
    if state == "blocked_product_path_health":
        return ["Fix engine availability, permissions, model assets, or runtime failures before default decisions."]
    return ["Add complete user-impact metrics for at least one ready product-path run."]


def build_report(args):
    matrix_path = args.engine_lane_matrix.expanduser().resolve()
    matrix = read_json(matrix_path)
    validate_input(matrix, "engine_lane_matrix", "engine lane matrix")

    product_rows = product_path_rows(matrix)
    statuses = [product_row_status(row) for row in product_rows]
    counts = {
        "product_path_lane_count": len(product_rows),
        "product_path_default_gate_input_count": sum(
            1 for status in statuses if status["default_gate_input"]
        ),
        "dry_run_product_path_lane_count": sum(1 for status in statuses if status["dry_run"]),
        "user_impact_incomplete_lane_count": sum(
            1 for status in statuses if status["user_impact_incomplete"]
        ),
        "health_not_ready_lane_count": sum(1 for status in statuses if status["health_not_ready"]),
        "sidecar_required_lane_count": sum(1 for status in statuses if status["requires_sidecar"]),
    }
    state = readiness_state(counts)
    evidence_paths = [str(matrix_path)]
    for status in statuses:
        evidence_paths.extend(status["evidence_paths"])

    return {
        "manifest_type": "product_path_readiness_report",
        "schema_version": 1,
        "readiness_state": state,
        "eligible_for_default_gate": state == "ready_for_product_path_default_gate",
        "engine_lane_matrix_path": str(matrix_path),
        "reference_versions": matrix.get("reference_versions", []),
        "product_path_engine_ids": stable_unique(row.get("engine_id") for row in product_rows),
        "candidate_engine_ids": stable_unique(
            row.get("engine_id")
            for row in product_rows
            if row.get("default_gate_input") is True
        ),
        **counts,
        "blocking_gates": blocking_gates_for(state, counts),
        "reasons": reasons_for(state, counts),
        "next_actions": next_actions_for(state),
        "evidence_paths": stable_unique(evidence_paths),
    }


def run(args):
    payload = build_report(args)
    errors = validator.validate_manifest(payload)
    if errors:
        for error in errors:
            print(f"validation error: {error}")
        raise SystemExit("product path readiness report is invalid")

    output_path = args.output_root.expanduser().resolve() / "product_path_readiness_report.json"
    write_json(output_path, payload)
    print(f"wrote: {output_path}")
    print(f"readiness_state: {payload['readiness_state']}")
    print(f"eligible_for_default_gate: {payload['eligible_for_default_gate']}")
    if payload["blocking_gates"]:
        print("blocking_gates: " + ", ".join(payload["blocking_gates"]))
    return {"payload": payload, "output_path": output_path}


def main(argv=None):
    result = run(parse_args(argv))
    return 0 if result["payload"]["eligible_for_default_gate"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
