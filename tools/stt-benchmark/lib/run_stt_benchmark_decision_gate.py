#!/usr/bin/env python3
import argparse
import json
from pathlib import Path

import validate_stt_benchmark_manifest as validator


DEFAULT_SANITY_CER_CAP = 0.70


def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        description="Create an official STT benchmark decision manifest from normalized benchmark inputs."
    )
    parser.add_argument("--benchmark-run-manifest", type=Path, required=True)
    parser.add_argument("--metric-summary", type=Path, required=True)
    parser.add_argument("--manual-review-manifest", type=Path, required=True)
    parser.add_argument("--reference-manifest", type=Path, required=True)
    parser.add_argument("--reference-readiness-report", type=Path)
    parser.add_argument("--engine-manifest", type=Path)
    parser.add_argument("--regression-report", type=Path)
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--sanity-cer-cap", type=float, default=None)
    parser.add_argument(
        "--weighted-cer-threshold",
        type=float,
        default=None,
        dest="deprecated_sanity_cer_cap",
        help="Deprecated alias for --sanity-cer-cap.",
    )
    args = parser.parse_args(argv)
    if args.sanity_cer_cap is None:
        args.sanity_cer_cap = (
            args.deprecated_sanity_cer_cap
            if args.deprecated_sanity_cer_cap is not None
            else DEFAULT_SANITY_CER_CAP
        )
    return args


def read_json(path):
    with path.expanduser().open(encoding="utf-8") as handle:
        return json.load(handle)


def write_json(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def int_value(value, default=0):
    return value if isinstance(value, int) and not isinstance(value, bool) else default


def float_value(value, default=None):
    return value if isinstance(value, (int, float)) and not isinstance(value, bool) else default


def count(mapping, key):
    return int_value((mapping or {}).get(key), default=0)


def without_manifest_type(payload):
    result = dict(payload)
    result.pop("manifest_type", None)
    return result


def validate_input(payload, expected_type, label):
    errors = validator.validate_manifest(payload)
    if errors:
        raise SystemExit(f"{label} is invalid: {'; '.join(errors)}")
    if payload.get("manifest_type") != expected_type:
        raise SystemExit(f"{label} must have manifest_type={expected_type}")


def build_decision(benchmark, metric, manual, reference, readiness, engine, regression, sanity_cer_cap):
    next_buckets = manual.get("next_bucket_counts") or {}
    reference_issue_count = int_value(reference.get("reference_quality_issue_count"))
    reference_bucket_count = count(next_buckets, "reference_quality_issue")
    boundary_count = count(next_buckets, "boundary_slicing_issue")
    manual_followup_count = int_value(manual.get("manual_followup_count"))
    weighted_cer = float_value(metric.get("weighted_cer"))
    timeout_count = int_value(metric.get("timeout_count"))
    crash_count = int_value(metric.get("crash_count"))
    sidecar_unavailable_count = int_value(metric.get("sidecar_unavailable_count"))
    user_impact_complete = bool(metric.get("user_impact_metric_complete"))
    requires_sidecar = bool((engine or {}).get("requires_sidecar"))
    engine_health_status = (engine or {}).get("health_status")
    benchmark_reference_version = benchmark.get("reference_version")
    reference_version = reference.get("reference_version")

    if benchmark_reference_version != reference_version:
        return decision_payload(
            "blocked_reference_quality",
            "defer_until_reference_audit",
            [
                f"benchmark reference_version={benchmark_reference_version}",
                f"reference manifest reference_version={reference_version}",
            ],
            ["Rerun benchmark metrics against the current reviewed reference manifest."],
            ["stale_reference_version"],
        )

    if manual.get("complete") is not True or manual_followup_count:
        return decision_payload(
            "blocked_manual_review",
            "not_allowed",
            [
                "manual review gate is incomplete",
                f"manual_followup_count={manual_followup_count}",
            ],
            ["Complete manual residual review before official product decisions."],
            ["manual_review_incomplete"],
        )

    if reference.get("review_status") != "reviewed":
        return decision_payload(
            "blocked_reference_quality",
            "defer_until_reference_audit",
            [f"reference review_status={reference.get('review_status')}"],
            ["Complete reviewed gold reference audit before official default decisions."],
            ["reference_unreviewed"],
        )

    if reference_issue_count or reference_bucket_count:
        return decision_payload(
            "blocked_reference_quality",
            "defer_until_reference_audit",
            [
                f"reference_quality_issue_count={reference_issue_count}",
                f"reference_quality_issue bucket count={reference_bucket_count}",
            ],
            ["Audit or correct reference rows before official default decisions."],
            ["reference_quality_issue"] + (["boundary_slicing_issue"] if boundary_count else []),
        )

    quality_sanity_blocker_payload = quality_sanity_blocker(weighted_cer, sanity_cer_cap)
    if quality_sanity_blocker_payload:
        return quality_sanity_blocker_payload

    if timeout_count or crash_count:
        return decision_payload(
            "rejected",
            "not_allowed",
            [f"timeout_count={timeout_count}", f"crash_count={crash_count}"],
            ["Fix timeout/crash stability before product decisions."],
            ["runtime_stability_failed"],
        )

    if engine_health_status and engine_health_status != "ready":
        return decision_payload(
            "research_only",
            "not_allowed",
            [f"engine health_status={engine_health_status}"],
            ["Resolve engine availability before product or default decisions."],
            ["engine_unavailable"],
        )

    if requires_sidecar and sidecar_unavailable_count:
        return decision_payload(
            "research_only",
            "not_allowed",
            [f"sidecar_unavailable_count={sidecar_unavailable_count}"],
            ["Stabilize sidecar health before promoting to sidecar_candidate."],
            ["sidecar_unavailable"],
        )

    if requires_sidecar and benchmark.get("product_path") is not True:
        return decision_payload(
            "sidecar_candidate",
            "not_allowed",
            ["sidecar quality gate passed but product path is not validated"],
            ["Run sidecar product-path validation, cold/warm latency, memory, and long-run stability gates."],
            ["product_path_missing"],
        )

    if boundary_count:
        return decision_payload(
            "experimental_flag_only",
            "not_allowed",
            [f"boundary_slicing_issue remains: {boundary_count}"],
            ["Validate the same boundary strategy in product path before default changes."],
            ["boundary_slicing_issue"],
        )

    if benchmark.get("product_path") is not True:
        return decision_payload(
            "experimental_flag_only",
            "not_allowed",
            ["benchmark run is not product_path=true"],
            ["Run product-path validation before default changes."],
            ["product_path_missing"],
        )

    if (benchmark.get("runner_contract") or {}).get("dry_run") is True:
        return decision_payload(
            "experimental_flag_only",
            "not_allowed",
            ["product path manifest is dry_run=true"],
            ["Run a real product-path benchmark before default changes."],
            ["product_path_dry_run"],
        )

    if not user_impact_complete:
        return decision_payload(
            "experimental_flag_only",
            "not_allowed",
            ["user impact metric is missing"],
            ["Collect first visible text, preview stability, final delay, and fallback event metrics."],
            ["missing_user_impact_metric"],
        )

    readiness_blocker = reference_readiness_blocker(readiness, reference)
    if readiness_blocker:
        return readiness_blocker

    regression_blocker = regression_report_blocker(regression, benchmark)
    if regression_blocker:
        return regression_blocker

    # ADR 0004 판정규칙(A 배선): regression이 통과(악화 아님)해도, CI 기준으로 baseline보다
    # '확실히 개선'이 아니면 제품 default를 교체하지 않는다(현 default 유지). tie=무승부,
    # significant_regression=확실한 악화. CI 없으면(unknown_ci) 또는 신호 부재(unknown)면
    # 기존 2pp regression 통과로 fallback해 채택한다(D-a2).
    improvement_signal = (regression or {}).get("improvement_signal", "unknown")
    if improvement_signal == "significant_regression":
        # 확실한 악화(CI 분리)는 2pp 임계를 통과했더라도 채택은 물론 실험도 허용하지 않는다.
        return decision_payload(
            "rejected",
            "not_allowed",
            ["candidate is significantly worse than baseline by CI; do not adopt"],
            ["Keep current default; do not adopt a regressed candidate."],
            ["candidate_regressed"],
        )
    if improvement_signal == "tie":
        # 무승부(CI 겹침)는 차이가 노이즈 안 — default 교체는 안 하되 실험 플래그는 허용.
        return decision_payload(
            "experimental_flag_only",
            "not_allowed",
            ["candidate is not a confident improvement over baseline (tie)"],
            ["Keep current default; adopt only when the candidate CI is clearly better than the baseline CI."],
            ["not_confident_improvement"],
        )

    return decision_payload(
        "default_allowed",
        "allowed",
        ["all official default gates passed"],
        ["Prepare a default-change review with this decision manifest as evidence."],
        [],
    )


def quality_sanity_blocker(weighted_cer, sanity_cer_cap):
    if weighted_cer is None:
        return decision_payload(
            "rejected",
            "not_allowed",
            [f"weighted_cer is missing; cannot evaluate sanity ceiling={sanity_cer_cap:.4f}"],
            ["Keep current default and rerun quality sanity check after changes."],
            ["quality_sanity_failed"],
        )
    if weighted_cer > sanity_cer_cap:
        return decision_payload(
            "rejected",
            "not_allowed",
            [f"weighted_cer={weighted_cer} exceeds sanity ceiling={sanity_cer_cap:.4f}"],
            ["Keep current default and rerun quality sanity check after changes."],
            ["quality_sanity_failed"],
        )
    return None


def decision_payload(state, default_change, reasons, next_actions, blocking_gates):
    return {
        "decision_state": state,
        "default_change": default_change,
        "reasons": [item for item in unique(reasons) if item],
        "next_actions": [item for item in unique(next_actions) if item],
        "blocking_gates": [item for item in unique(blocking_gates) if item],
        "eligible_for_default": state == "default_allowed",
        "eligible_for_experimental_flag": state == "experimental_flag_only",
        "eligible_for_fallback": state == "fallback_only",
        "eligible_for_sidecar_candidate": state == "sidecar_candidate",
    }


def reference_readiness_blocker(readiness, reference):
    if not readiness:
        return decision_payload(
            "blocked_reference_quality",
            "defer_until_reference_audit",
            ["reference readiness report is missing"],
            ["Run check_stt_reference_readiness.py and attach a ready_for_default_gate report."],
            ["missing_reference_readiness_report"],
        )

    if readiness.get("reference_version") != reference.get("reference_version"):
        return decision_payload(
            "blocked_reference_quality",
            "defer_until_reference_audit",
            [
                f"readiness reference_version={readiness.get('reference_version')}",
                f"reference manifest reference_version={reference.get('reference_version')}",
            ],
            ["Regenerate reference readiness report for the current reference manifest."],
            ["stale_reference_readiness_report"],
        )

    if readiness.get("readiness_state") != "ready_for_default_gate":
        return decision_payload(
            "blocked_reference_quality",
            "defer_until_reference_audit",
            [
                f"reference readiness_state={readiness.get('readiness_state')}",
                *readiness.get("reasons", []),
            ],
            readiness.get("next_actions") or [
                "Resolve reference readiness blockers before official default decisions."
            ],
            ["reference_readiness_not_ready", *readiness.get("blocking_gates", [])],
        )

    return None


def regression_report_blocker(regression, benchmark):
    if not regression:
        return decision_payload(
            "experimental_flag_only",
            "not_allowed",
            ["regression report is missing"],
            ["Run run_stt_regression_gate.py against a comparable baseline before default decisions."],
            ["missing_regression_report"],
        )

    if regression.get("reference_version") != benchmark.get("reference_version"):
        return decision_payload(
            "experimental_flag_only",
            "not_allowed",
            [
                f"regression reference_version={regression.get('reference_version')}",
                f"benchmark reference_version={benchmark.get('reference_version')}",
            ],
            ["Regenerate regression report for the current benchmark reference version."],
            ["stale_regression_report"],
        )

    if regression.get("regression_state") != "passed":
        state = "rejected" if regression.get("regression_state") == "failed" else "experimental_flag_only"
        return decision_payload(
            state,
            "not_allowed",
            [
                f"regression_state={regression.get('regression_state')}",
                *regression.get("reasons", []),
            ],
            regression.get("next_actions") or [
                "Resolve regression report blockers before default decisions."
            ],
            ["regression_not_passed", *regression.get("blocking_gates", [])],
        )

    return None


def unique(items):
    result = []
    for item in items:
        if item not in result:
            result.append(item)
    return result


def build_manifest(benchmark, metric, manual, reference, readiness, engine, regression, args):
    decision = build_decision(
        benchmark,
        metric,
        manual,
        reference,
        readiness,
        engine,
        regression,
        args.sanity_cer_cap,
    )
    payload = {
        "manifest_type": "decision_manifest",
        "schema_version": 1,
        **decision,
        "evidence_paths": [
            str(args.benchmark_run_manifest.expanduser()),
            str(args.metric_summary.expanduser()),
            str(args.manual_review_manifest.expanduser()),
            str(args.reference_manifest.expanduser()),
        ],
        "benchmark_run_manifest": without_manifest_type(benchmark),
        "metric_summary": without_manifest_type(metric),
        "manual_review_manifest": without_manifest_type(manual),
        "reference_manifest": without_manifest_type(reference),
    }
    if readiness:
        payload["reference_readiness_report"] = without_manifest_type(readiness)
        payload["evidence_paths"].append(str(args.reference_readiness_report.expanduser()))
    if engine:
        payload["engine_manifest"] = without_manifest_type(engine)
        payload["evidence_paths"].append(str(args.engine_manifest.expanduser()))
    if regression:
        payload["regression_report"] = without_manifest_type(regression)
        payload["evidence_paths"].append(str(args.regression_report.expanduser()))
    return payload


def run(args):
    benchmark = read_json(args.benchmark_run_manifest)
    metric = read_json(args.metric_summary)
    manual = read_json(args.manual_review_manifest)
    reference = read_json(args.reference_manifest)
    readiness = read_json(args.reference_readiness_report) if args.reference_readiness_report else None
    engine = read_json(args.engine_manifest) if args.engine_manifest else None
    regression = read_json(args.regression_report) if args.regression_report else None

    validate_input(benchmark, "benchmark_run_manifest", "benchmark run manifest")
    validate_input(metric, "metric_summary", "metric summary")
    validate_input(manual, "manual_review_manifest", "manual review manifest")
    validate_input(reference, "reference_manifest", "reference manifest")
    if readiness:
        validate_input(readiness, "reference_readiness_report", "reference readiness report")
    if engine:
        validate_input(engine, "engine_manifest", "engine manifest")
    if regression:
        validate_input(regression, "regression_report", "regression report")

    payload = build_manifest(benchmark, metric, manual, reference, readiness, engine, regression, args)
    errors = validator.validate_manifest(payload)
    if errors:
        for error in errors:
            print(f"validation error: {error}")
        raise SystemExit("official decision manifest is invalid")

    output_path = args.output_root.expanduser().resolve() / "official_stt_decision_manifest.json"
    write_json(output_path, payload)
    print(f"wrote: {output_path}")
    print(f"decision_state: {payload['decision_state']}")
    print(f"default_change: {payload['default_change']}")
    return {"payload": payload, "output_path": output_path}


def main(argv=None):
    return 0 if run(parse_args(argv)) else 1


if __name__ == "__main__":
    raise SystemExit(main())
