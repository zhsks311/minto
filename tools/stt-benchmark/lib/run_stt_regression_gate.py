#!/usr/bin/env python3
import argparse
import json
from pathlib import Path

import stt_engine_verdict as verdict
import validate_stt_benchmark_manifest as validator


COMPARABLE_BENCHMARK_FIELDS = [
    "benchmark_kind",
    "product_path",
    "reference_version",
    "sample_set",
    "input_contract",
    "runner_contract",
]


def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        description="Compare an official STT candidate run against a baseline regression run."
    )
    parser.add_argument("--candidate-benchmark-run-manifest", type=Path, required=True)
    parser.add_argument("--candidate-metric-summary", type=Path, required=True)
    parser.add_argument("--baseline-benchmark-run-manifest", type=Path)
    parser.add_argument("--baseline-metric-summary", type=Path)
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--weighted-cer-regression-pp", type=float, default=2.0)
    parser.add_argument("--empty-final-count-delta", type=float, default=0.0)
    parser.add_argument("--timeout-count-delta", type=float, default=0.0)
    parser.add_argument("--crash-count-delta", type=float, default=0.0)
    parser.add_argument("--sidecar-unavailable-count-delta", type=float, default=0.0)
    parser.add_argument("--permission-asset-failure-count-delta", type=float, default=0.0)
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


def thresholds(args):
    return {
        "weighted_cer_regression_pp": args.weighted_cer_regression_pp,
        "empty_final_count_delta": args.empty_final_count_delta,
        "timeout_count_delta": args.timeout_count_delta,
        "crash_count_delta": args.crash_count_delta,
        "sidecar_unavailable_count_delta": args.sidecar_unavailable_count_delta,
        "permission_asset_failure_count_delta": args.permission_asset_failure_count_delta,
    }


def number(value, default=0.0):
    return float(value) if isinstance(value, (int, float)) and not isinstance(value, bool) else default


def count_delta(candidate, baseline, name):
    return number(candidate.get(name)) - number(baseline.get(name))


def permission_asset_failure_count(metric):
    user_impact = metric.get("user_impact_metrics") or {}
    return number(user_impact.get("permission_asset_failure_count"))


def compute_improvement_signal(candidate_metric, baseline_metric):
    # ADR 0004 판정규칙 배선: candidate가 baseline 대비 CI 기준으로 확실히 개선/악화/무승부인지.
    # CI(cer_ci95_half_width)는 반복측정에서 채워진다. 없으면 "unknown_ci" — decision이
    # 기존 2pp regression_state로 fallback(D-a2). 같은 함수를 양방향으로 재사용한다.
    candidate = {
        "cer_mean": candidate_metric.get("weighted_cer"),
        "cer_ci95_half_width": candidate_metric.get("cer_ci95_half_width"),
    }
    baseline = {
        "cer_mean": baseline_metric.get("weighted_cer"),
        "cer_ci95_half_width": baseline_metric.get("cer_ci95_half_width"),
    }
    # 한쪽만 CI가 있어도(예: 후보만 반복측정) 보수적으로 unknown_ci — 양쪽 CI가 모두
    # 있어야 신뢰성 있는 비교가 가능하다.
    if candidate["cer_ci95_half_width"] is None or baseline["cer_ci95_half_width"] is None:
        return "unknown_ci"
    if verdict.is_significant_improvement(candidate, baseline):
        return "significant_improvement"
    if verdict.is_significant_improvement(baseline, candidate):
        return "significant_regression"
    return "tie"


def metric_deltas(candidate_metric, baseline_metric):
    return {
        "weighted_cer_pp": (number(candidate_metric.get("weighted_cer")) - number(baseline_metric.get("weighted_cer"))) * 100,
        "empty_final_count": count_delta(candidate_metric, baseline_metric, "empty_final_count"),
        "timeout_count": count_delta(candidate_metric, baseline_metric, "timeout_count"),
        "crash_count": count_delta(candidate_metric, baseline_metric, "crash_count"),
        "sidecar_unavailable_count": count_delta(candidate_metric, baseline_metric, "sidecar_unavailable_count"),
        "permission_asset_failure_count": (
            permission_asset_failure_count(candidate_metric) - permission_asset_failure_count(baseline_metric)
        ),
    }


def comparability_errors(candidate_benchmark, baseline_benchmark):
    errors = []
    for field in COMPARABLE_BENCHMARK_FIELDS:
        if candidate_benchmark.get(field) != baseline_benchmark.get(field):
            errors.append(
                f"{field} mismatch: candidate={candidate_benchmark.get(field)!r}, "
                f"baseline={baseline_benchmark.get(field)!r}"
            )
    return errors


def regression_failures(deltas, limits):
    failures = []
    checks = [
        ("weighted_cer_regression", "weighted_cer_pp", "weighted_cer_regression_pp"),
        ("empty_final_regression", "empty_final_count", "empty_final_count_delta"),
        ("timeout_regression", "timeout_count", "timeout_count_delta"),
        ("crash_regression", "crash_count", "crash_count_delta"),
        ("sidecar_unavailable_regression", "sidecar_unavailable_count", "sidecar_unavailable_count_delta"),
        ("permission_asset_failure_regression", "permission_asset_failure_count", "permission_asset_failure_count_delta"),
    ]
    for gate, delta_name, threshold_name in checks:
        if deltas.get(delta_name, 0.0) > limits[threshold_name]:
            failures.append(gate)
    return failures


def report_payload(state, candidate_benchmark, baseline_benchmark, limits, deltas, gates, reasons, next_actions, evidence_paths, improvement_signal="unknown"):
    return {
        "manifest_type": "regression_report",
        "schema_version": 1,
        "reference_version": candidate_benchmark.get("reference_version", ""),
        "candidate_run_id": candidate_benchmark.get("run_id", ""),
        "baseline_run_id": (baseline_benchmark or {}).get("run_id"),
        "regression_state": state,
        "eligible_for_default_gate": state == "passed",
        "blocking_gates": gates,
        "reasons": reasons,
        "next_actions": next_actions,
        "thresholds": limits,
        "deltas": deltas,
        "evidence_paths": [str(path.expanduser()) for path in evidence_paths if path],
        "improvement_signal": improvement_signal,
    }


def build_report(args):
    candidate_benchmark = read_json(args.candidate_benchmark_run_manifest)
    candidate_metric = read_json(args.candidate_metric_summary)
    validate_input(candidate_benchmark, "benchmark_run_manifest", "candidate benchmark run manifest")
    validate_input(candidate_metric, "metric_summary", "candidate metric summary")
    limits = thresholds(args)

    if not args.baseline_benchmark_run_manifest or not args.baseline_metric_summary:
        return report_payload(
            "missing_baseline",
            candidate_benchmark,
            None,
            limits,
            {},
            ["missing_regression_baseline"],
            ["baseline benchmark run or metric summary is missing"],
            ["Attach a comparable baseline before using this candidate for default decisions."],
            [args.candidate_benchmark_run_manifest, args.candidate_metric_summary],
        )

    baseline_benchmark = read_json(args.baseline_benchmark_run_manifest)
    baseline_metric = read_json(args.baseline_metric_summary)
    validate_input(baseline_benchmark, "benchmark_run_manifest", "baseline benchmark run manifest")
    validate_input(baseline_metric, "metric_summary", "baseline metric summary")

    compare_errors = comparability_errors(candidate_benchmark, baseline_benchmark)
    deltas = metric_deltas(candidate_metric, baseline_metric)
    evidence_paths = [
        args.candidate_benchmark_run_manifest,
        args.candidate_metric_summary,
        args.baseline_benchmark_run_manifest,
        args.baseline_metric_summary,
    ]
    if compare_errors:
        return report_payload(
            "not_comparable",
            candidate_benchmark,
            baseline_benchmark,
            limits,
            deltas,
            ["regression_not_comparable"],
            compare_errors,
            ["Rerun candidate and baseline with the same reference, sample set, benchmark kind, and runner contract."],
            evidence_paths,
        )

    failures = regression_failures(deltas, limits)
    improvement_signal = compute_improvement_signal(candidate_metric, baseline_metric)
    if failures:
        return report_payload(
            "failed",
            candidate_benchmark,
            baseline_benchmark,
            limits,
            deltas,
            failures,
            [f"{name} delta exceeded threshold" for name in failures],
            ["Keep current default and investigate the regression before release."],
            evidence_paths,
            improvement_signal=improvement_signal,
        )

    return report_payload(
        "passed",
        candidate_benchmark,
        baseline_benchmark,
        limits,
        deltas,
        [],
        ["candidate is within regression thresholds"],
        ["Use this regression report as default-change evidence."],
        evidence_paths,
        improvement_signal=improvement_signal,
    )


def run(args):
    payload = build_report(args)
    errors = validator.validate_manifest(payload)
    if errors:
        for error in errors:
            print(f"validation error: {error}")
        raise SystemExit("regression report is invalid")

    output_path = args.output_root.expanduser().resolve() / "regression_report.json"
    write_json(output_path, payload)
    print(f"wrote: {output_path}")
    print(f"regression_state: {payload['regression_state']}")
    print(f"eligible_for_default_gate: {payload['eligible_for_default_gate']}")
    return {"payload": payload, "output_path": output_path}


def main(argv=None):
    return 0 if run(parse_args(argv)) else 1


if __name__ == "__main__":
    raise SystemExit(main())
