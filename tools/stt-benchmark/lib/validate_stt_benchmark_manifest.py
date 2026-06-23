#!/usr/bin/env python3
import argparse
import json
import shlex
from pathlib import Path


DECISION_STATES = {
    "default_allowed",
    "experimental_flag_only",
    "fallback_only",
    "sidecar_candidate",
    "research_only",
    "blocked_reference_quality",
    "blocked_manual_review",
    "rejected",
}

BENCHMARK_KINDS = {
    "offline_final",
    "rolling_preview",
    "true_streaming",
    "sidecar_final",
    "product_path_final",
    "llm_postprocess",
}

DEFAULT_CHANGE_VALUES = {
    "allowed",
    "not_allowed",
    "defer_until_reference_audit",
    "allowed_after_product_path_validation",
}

MANIFEST_TYPES = {
    "benchmark_run_manifest",
    "decision_manifest",
    "engine_comparability_report",
    "engine_comparability_rerun_plan",
    "engine_coverage_report",
    "engine_lane_matrix",
    "engine_reference_alignment_plan",
    "engine_run_bundle_manifest",
    "engine_run_bundle_workflow_report",
    "engine_manifest",
    "manual_review_manifest",
    "metric_summary",
    "official_decision_workflow_report",
    "official_comparison_adoption_checklist_report",
    "official_comparison_adoption_remediation_plan",
    "official_comparison_engine_evidence_audit_report",
    "official_comparison_next_action_execution_status_report",
    "official_comparison_next_action_artifact_prep_report",
    "official_comparison_operator_evidence_intake_report",
    "official_comparison_operator_evidence_execution_plan",
    "official_comparison_operator_evidence_request_report",
    "official_comparison_operator_evidence_return_template",
    "official_comparison_operator_evidence_return_workflow_report",
    "official_comparison_operator_evidence_submission_checklist",
    "official_comparison_operator_evidence_submission_status_report",
    "official_comparison_operator_evidence_submission_values_template",
    "official_comparison_operator_handoff_report",
    "official_comparison_preflight_resume_plan",
    "official_comparison_release_gate_report",
    "official_release_artifact_audit_report",
    "official_release_workflow_report",
    "official_comparison_next_action_plan",
    "official_comparison_readiness_report",
    "official_comparison_preflight_workflow_report",
    "product_path_official_run_plan",
    "product_path_readiness_report",
    "reference_manifest",
    "reference_manifest_raw_dir_report",
    "reference_readiness_report",
    "reference_review_batch_workflow_report",
    "reference_review_decision_scaffold_report",
    "reference_review_progress_report",
    "reference_review_preflight_report",
    "reference_review_submission_readiness_report",
    "regression_report",
}

REFERENCE_SPLITS = {"gold", "dev", "stress"}
REFERENCE_REVIEW_STATUSES = {"unreviewed", "reviewed", "excluded"}
REFERENCE_READINESS_STATES = {
    "ready_for_default_gate",
    "blocked_reference_review",
    "blocked_reference_quality",
    "insufficient_gold_reference",
}
REFERENCE_REVIEW_PREFLIGHT_STATES = {
    "ready_to_apply",
    "blocked_review_decision_incomplete",
    "blocked_review_decision_errors",
}
REFERENCE_REVIEW_PROGRESS_STATES = {
    "review_not_started",
    "review_in_progress",
    "review_complete",
}
REFERENCE_REVIEW_BATCH_WORKFLOW_STATES = {
    "blocked_preflight",
    "applied",
}
REFERENCE_REVIEW_DECISION_SCAFFOLD_STATES = {
    "prepared",
    "blocked_insufficient_gold_candidates",
    "blocked_insufficient_target_split_candidates",
}
REFERENCE_REVIEW_SUBMISSION_READINESS_STATES = {
    "blocked_preflight",
    "blocked_readiness",
    "ready_for_workflow",
}
REFERENCE_REVIEW_GOLD_REQUIREMENT_STATES = {
    "blocked_gold_review_incomplete",
    "blocked_insufficient_planned_gold_duration",
    "blocked_no_gold_target",
    "satisfied",
}
REGRESSION_STATES = {
    "passed",
    "failed",
    "missing_baseline",
    "not_comparable",
}
ENGINE_COVERAGE_STATES = {
    "ready_for_official_comparison",
    "blocked_engine_coverage",
}
ENGINE_COMPARABILITY_STATES = {
    "ready_for_official_comparison",
    "blocked_comparability",
}
ENGINE_COMPARABILITY_RERUN_PLAN_STATES = {
    "ready_to_rerun",
    "no_rerun_needed",
}
ENGINE_REFERENCE_ALIGNMENT_PLAN_STATES = {
    "ready_to_align_reference",
    "no_alignment_needed",
}

# Free-form engine decoding settings. Known keys are documented here for later
# phantom-suppression analysis, but validator compatibility stays open-ended.
# Bundle converters should populate this only after STT reruns emit concrete
# engine decode settings in their source artifacts.
KNOWN_DECODING_PARAMETER_KEYS = {
    "no_speech_threshold",
    "logprob_threshold",
    "compression_ratio_threshold",
    "condition_on_previous_text",
    "temperature",
    "beam_size",
    "vad",
    "language",
}
OFFICIAL_COMPARISON_READINESS_STATES = {
    "ready_for_official_comparison",
    "blocked_reference",
    "blocked_engine_comparability",
    "blocked_engine_coverage",
    "blocked_product_path",
}
PRODUCT_PATH_READINESS_STATES = {
    "ready_for_product_path_default_gate",
    "blocked_no_product_path_runs",
    "blocked_product_path_contract",
    "blocked_product_path_health",
    "blocked_user_impact_metrics",
}
PRODUCT_PATH_OFFICIAL_RUN_PLAN_STATES = {
    "ready_to_prepare_product_path_run",
    "no_product_path_run_needed",
}
PRODUCT_PATH_DRY_RUN_CONTRACT_STATES = {
    "missing",
    "valid",
    "invalid",
}
OFFICIAL_COMPARISON_PREFLIGHT_WORKFLOW_STATES = {
    "ready_for_official_comparison",
    "blocked_preflight",
}
OFFICIAL_COMPARISON_NEXT_ACTION_PLAN_STATES = {
    "ready_for_official_comparison",
    "blocked_next_actions",
}
OFFICIAL_COMPARISON_NEXT_ACTION_TASK_STATES = {
    "open",
    "waiting",
    "not_needed",
}
OFFICIAL_COMPARISON_NEXT_ACTION_ARTIFACT_PREP_STATES = {
    "prepared_next_action_artifacts",
    "prepared_reference_review_pack",
    "nothing_to_prepare",
    "blocked_missing_reference_manifest",
}
OFFICIAL_COMPARISON_NEXT_ACTION_EXECUTION_STATES = {
    "ready_to_execute",
    "blocked_waiting_for_evidence",
    "no_action_needed",
}
OFFICIAL_COMPARISON_NEXT_ACTION_TASK_EXECUTION_STATUSES = {
    "ready_to_execute",
    "waiting_for_manual_input",
    "waiting_for_target_reference",
    "waiting_for_real_run",
    "not_needed",
}
OFFICIAL_COMPARISON_OPERATOR_HANDOFF_STATES = {
    "ready_for_operator",
    "blocked_waiting_for_operator_evidence",
    "no_handoff_needed",
}
OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_INTAKE_STATES = {
    "ready_to_rerun_preflight",
    "blocked_missing_operator_evidence",
    "no_handoff_needed",
}
OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_ITEM_STATES = {
    "accepted",
    "missing",
    "rejected",
    "not_needed",
}
OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_REQUEST_STATES = {
    "needs_operator_evidence",
    "operator_evidence_already_accepted",
    "no_operator_evidence_needed",
}
OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_REQUEST_ITEM_STATES = {
    "requested",
    "already_accepted",
    "not_needed",
}
OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_RETURN_WORKFLOW_STATES = {
    "ready_to_rerun_preflight",
    "blocked_operator_evidence",
    "no_operator_evidence_needed",
}
OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_EXECUTION_PLAN_STATES = {
    "ready_to_collect_operator_evidence",
    "ready_to_rerun_preflight",
    "no_operator_evidence_needed",
    "blocked_no_execution_path",
}
OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_EXECUTION_STEP_STATES = {
    "open",
    "blocked",
    "completed",
    "not_needed",
}
OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_SUBMISSION_CHECKLIST_STATES = {
    "ready_to_collect_operator_submissions",
    "ready_to_rerun_preflight",
    "no_operator_evidence_needed",
    "blocked_no_submission_path",
}
OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_SUBMISSION_SLOT_STATES = {
    "open",
    "accepted",
    "blocked",
    "not_needed",
}
OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_SUBMISSION_SLOT_TYPES = {
    "reference_review_workflow_report",
    "target_reference_engine_bundle",
    "comparability_rerun_bundle",
    "product_path_run_bundle",
    "generic_operator_evidence",
}
OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_SUBMISSION_STATUS_STATES = {
    "waiting_for_submissions",
    "partially_submitted",
    "blocked_invalid_submissions",
    "all_slots_submitted",
    "no_operator_evidence_needed",
}
OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_SUBMISSION_SLOT_STATUS_STATES = {
    "missing",
    "submitted",
    "rejected",
    "not_needed",
}
OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_SUBMISSION_VALUES_FILL_STATES = {
    "ready_to_fill_return_template",
    "blocked_empty_submission_values",
    "blocked_invalid_submission_values",
    "no_submission_values_needed",
}
OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_SUBMISSION_COMPLETION_STATES = {
    "waiting_for_required_submissions",
    "partial_submission_ready",
    "blocked_invalid_submissions",
    "complete_submission_ready",
    "no_operator_evidence_needed",
}
OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_EXPECTED_SUBMISSION_PATH_STATES = {
    "known_from_command_template",
    "no_submission_manifest_command_template",
    "missing_output_root_in_submission_command",
    "unsupported_return_field",
}
OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_EXPECTED_SUBMISSION_PATH_FILE_STATES = {
    "exists",
    "missing",
    "not_applicable",
}
OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_SOURCE_CANDIDATE_STATES = {
    "usable_as_submission",
    "rejected_candidate",
    "not_matching_candidate",
    "not_submission_manifest",
    "blocked_missing_file",
    "blocked_invalid_json",
}
OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_SOURCE_CANDIDATE_STATE_ORDER = [
    "usable_as_submission",
    "rejected_candidate",
    "not_matching_candidate",
    "not_submission_manifest",
    "blocked_missing_file",
    "blocked_invalid_json",
]
OFFICIAL_COMPARISON_RETURN_FIELD_RESOLUTION_STATES = {
    "accepted",
    "missing",
    "rejected",
    "not_needed",
    "partially_accepted",
    "no_tasks",
}
OFFICIAL_COMPARISON_RETURN_FIELD_VALUE_CONTRACT_STATES = {
    "valid",
    "invalid",
    "missing",
    "unchecked",
}
OFFICIAL_COMPARISON_RETURN_FIELD_RESOLUTION_STATES = {
    "accepted",
    "missing",
    "rejected",
    "not_needed",
    "partially_accepted",
    "no_tasks",
}
OFFICIAL_RELEASE_RETURN_BLOCKER_SUMMARY_STATES = {
    "blocking_adoption",
    "field_contract_blocked",
    "field_verdict_blocked",
    "not_blocking",
    "unknown",
}
OFFICIAL_RELEASE_ADOPTION_BLOCKER_EVIDENCE_RESOLUTION_STATES = {
    "blocked_by_operator_evidence",
    "operator_evidence_accepted_pending_preflight",
    "not_mapped_to_operator_evidence",
}
OFFICIAL_COMPARISON_PREFLIGHT_RESUME_PLAN_STATES = {
    "ready_to_rerun_preflight",
    "blocked_operator_evidence",
    "no_resume_needed",
}
OFFICIAL_COMPARISON_RELEASE_GATE_STATES = {
    "ready_for_default_release",
    "blocked_preflight",
    "blocked_regression",
    "blocked_decision",
}
OFFICIAL_COMPARISON_ADOPTION_STATES = {
    "ready_for_official_adoption",
    "blocked_official_adoption",
}
OFFICIAL_COMPARISON_ADOPTION_CHECKLIST_ITEM_STATES = {
    "passed",
    "blocked",
    "unknown",
}
OFFICIAL_COMPARISON_ADOPTION_REMEDIATION_PLAN_STATES = {
    "ready_to_collect_evidence",
    "ready_for_official_adoption",
    "blocked_no_remediation_path",
}
OFFICIAL_COMPARISON_ADOPTION_REMEDIATION_TASK_STATES = {
    "open",
    "not_needed",
}
OFFICIAL_RELEASE_WORKFLOW_STATES = {
    "ready_for_default_release",
    "ready_to_rerun_preflight",
    "blocked_operator_evidence",
    "blocked_release",
}
OFFICIAL_RELEASE_ARTIFACT_AUDIT_STATES = {
    "ready_for_artifact_review",
    "blocked_missing_artifact",
    "blocked_invalid_artifact",
}
OFFICIAL_RELEASE_ARTIFACT_STATES = {
    "valid",
    "missing",
    "invalid",
    "not_applicable",
}
OFFICIAL_RELEASE_ARTIFACT_KINDS = {
    "json_manifest",
    "file",
}
OFFICIAL_COMPARISON_ENGINE_EVIDENCE_AUDIT_STATES = {
    "ready_to_convert",
    "blocked_evidence_gaps",
    "no_candidates",
}
OFFICIAL_COMPARISON_ENGINE_EVIDENCE_TARGET_STATES = {
    "ready_to_convert",
    "needs_converter_or_mapping",
    "blocked_candidate",
    "missing_candidate",
}
USER_IMPACT_METRIC_FIELDS = [
    "time_to_first_visible_text_seconds",
    "final_transcript_delay_seconds",
    "preview_revision_count",
    "unstable_partial_ratio",
    "empty_visible_transcript_count",
    "permission_asset_failure_count",
    "sidecar_startup_failure_count",
    "peak_memory_mb",
    "cold_start_seconds",
    "user_visible_fallback_event_count",
]
GENERIC_OPERATOR_COMMAND_PATH_MARKERS = (
    "/operator_evidence_request/",
    "/operator_evidence_submission_status/",
)
SUBMISSION_OUTPUT_FILENAMES_BY_RETURN_FIELD = {
    "reference_review_workflow_report_path": "reference_review_batch_workflow_report.json",
    "run_bundle_manifest_paths": "engine_run_bundle_manifest.json",
}
SUBMISSION_COMMAND_MARKERS_BY_RETURN_FIELD = {
    "reference_review_workflow_report_path": [
        "run_stt_reference_review_batch_workflow.py",
    ],
    "run_bundle_manifest_paths": [
        "convert_stt_pipeline_to_official_bundle.py",
        "convert_nemotron_summary_to_official_bundle.py",
    ],
}


def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        description="Validate official STT benchmark manifest contracts."
    )
    parser.add_argument("manifest", nargs="+", type=Path)
    return parser.parse_args(argv)


def read_json(path):
    with path.expanduser().open(encoding="utf-8") as handle:
        return json.load(handle)


def read_json_if_available(path_value):
    if not isinstance(path_value, str) or not path_value:
        return None
    path = Path(path_value).expanduser()
    if not path.is_file():
        return None
    try:
        return read_json(path)
    except (OSError, json.JSONDecodeError):
        return None


def read_linked_manifest_if_available(
    payload,
    path_field,
    expected_manifest_type,
    errors,
    prefix,
):
    linked = read_json_if_available(payload.get(path_field))
    if not isinstance(linked, dict):
        return None
    if linked.get("manifest_type") != expected_manifest_type:
        errors.append(
            f"{prefix}.{path_field} must reference {expected_manifest_type}; "
            f"got {linked.get('manifest_type')!r}"
        )
        return None
    return linked


def validate_manifest(payload):
    errors = []
    manifest_type = payload.get("manifest_type")
    if manifest_type not in MANIFEST_TYPES:
        errors.append(
            f"manifest_type must be one of {sorted(MANIFEST_TYPES)}; got {manifest_type!r}"
        )
        return errors

    require_fields(errors, payload, ["schema_version"], manifest_type)

    validators = {
        "benchmark_run_manifest": validate_benchmark_run_manifest,
        "decision_manifest": validate_decision_manifest,
        "engine_comparability_report": validate_engine_comparability_report,
        "engine_comparability_rerun_plan": validate_engine_comparability_rerun_plan,
        "engine_coverage_report": validate_engine_coverage_report,
        "engine_lane_matrix": validate_engine_lane_matrix,
        "engine_reference_alignment_plan": validate_engine_reference_alignment_plan,
        "engine_run_bundle_manifest": validate_engine_run_bundle_manifest,
        "engine_run_bundle_workflow_report": validate_engine_run_bundle_workflow_report,
        "engine_manifest": validate_engine_manifest,
        "manual_review_manifest": validate_manual_review_manifest,
        "metric_summary": validate_metric_summary,
        "official_decision_workflow_report": validate_official_decision_workflow_report,
        "official_comparison_adoption_checklist_report": (
            validate_official_comparison_adoption_checklist_report
        ),
        "official_comparison_adoption_remediation_plan": (
            validate_official_comparison_adoption_remediation_plan
        ),
        "official_comparison_engine_evidence_audit_report": (
            validate_official_comparison_engine_evidence_audit_report
        ),
        "official_comparison_next_action_artifact_prep_report": (
            validate_official_comparison_next_action_artifact_prep_report
        ),
        "official_comparison_next_action_execution_status_report": (
            validate_official_comparison_next_action_execution_status_report
        ),
        "official_comparison_operator_handoff_report": (
            validate_official_comparison_operator_handoff_report
        ),
        "official_comparison_operator_evidence_intake_report": (
            validate_official_comparison_operator_evidence_intake_report
        ),
        "official_comparison_operator_evidence_execution_plan": (
            validate_official_comparison_operator_evidence_execution_plan
        ),
        "official_comparison_operator_evidence_request_report": (
            validate_official_comparison_operator_evidence_request_report
        ),
        "official_comparison_operator_evidence_return_template": (
            validate_official_comparison_operator_evidence_return_template
        ),
        "official_comparison_operator_evidence_return_workflow_report": (
            validate_official_comparison_operator_evidence_return_workflow_report
        ),
        "official_comparison_operator_evidence_submission_checklist": (
            validate_official_comparison_operator_evidence_submission_checklist
        ),
        "official_comparison_operator_evidence_submission_status_report": (
            validate_official_comparison_operator_evidence_submission_status_report
        ),
        "official_comparison_operator_evidence_submission_values_template": (
            validate_official_comparison_operator_evidence_submission_values_template
        ),
        "official_comparison_preflight_resume_plan": (
            validate_official_comparison_preflight_resume_plan
        ),
        "official_comparison_release_gate_report": (
            validate_official_comparison_release_gate_report
        ),
        "official_release_artifact_audit_report": (
            validate_official_release_artifact_audit_report
        ),
        "official_release_workflow_report": validate_official_release_workflow_report,
        "official_comparison_next_action_plan": validate_official_comparison_next_action_plan,
        "official_comparison_readiness_report": validate_official_comparison_readiness_report,
        "official_comparison_preflight_workflow_report": validate_official_comparison_preflight_workflow_report,
        "product_path_official_run_plan": validate_product_path_official_run_plan,
        "product_path_readiness_report": validate_product_path_readiness_report,
        "reference_manifest": validate_reference_manifest,
        "reference_manifest_raw_dir_report": validate_reference_manifest_raw_dir_report,
        "reference_readiness_report": validate_reference_readiness_report,
        "reference_review_batch_workflow_report": validate_reference_review_batch_workflow_report,
        "reference_review_decision_scaffold_report": (
            validate_reference_review_decision_scaffold_report
        ),
        "reference_review_progress_report": validate_reference_review_progress_report,
        "reference_review_preflight_report": validate_reference_review_preflight_report,
        "reference_review_submission_readiness_report": (
            validate_reference_review_submission_readiness_report
        ),
        "regression_report": validate_regression_report,
    }
    validators[manifest_type](payload, errors, manifest_type)
    return errors


def validate_decision_manifest(payload, errors, prefix):
    require_fields(
        errors,
        payload,
        [
            "decision_state",
            "default_change",
            "reasons",
            "next_actions",
            "blocking_gates",
            "eligible_for_default",
            "eligible_for_experimental_flag",
            "eligible_for_fallback",
            "eligible_for_sidecar_candidate",
            "evidence_paths",
            "benchmark_run_manifest",
            "metric_summary",
            "manual_review_manifest",
            "reference_manifest",
        ],
        prefix,
    )

    decision_state = payload.get("decision_state")
    if decision_state not in DECISION_STATES:
        errors.append(f"{prefix}.decision_state is invalid: {decision_state!r}")

    default_change = payload.get("default_change")
    if default_change not in DEFAULT_CHANGE_VALUES:
        errors.append(f"{prefix}.default_change is invalid: {default_change!r}")

    for name in [
        "reasons",
        "next_actions",
        "blocking_gates",
        "evidence_paths",
    ]:
        require_type(errors, payload.get(name), list, f"{prefix}.{name}")

    for name in [
        "eligible_for_default",
        "eligible_for_experimental_flag",
        "eligible_for_fallback",
        "eligible_for_sidecar_candidate",
    ]:
        require_type(errors, payload.get(name), bool, f"{prefix}.{name}")

    nested = {
        "benchmark_run_manifest": validate_benchmark_run_manifest,
        "metric_summary": validate_metric_summary,
        "manual_review_manifest": validate_manual_review_manifest,
        "reference_manifest": validate_reference_manifest,
    }
    for name, validator in nested.items():
        value = payload.get(name)
        if isinstance(value, dict):
            validator(value, errors, f"{prefix}.{name}")
        else:
            errors.append(f"{prefix}.{name} must be an object")
    if "engine_manifest" in payload:
        value = payload.get("engine_manifest")
        if isinstance(value, dict):
            validate_engine_manifest(value, errors, f"{prefix}.engine_manifest")
        else:
            errors.append(f"{prefix}.engine_manifest must be an object")
    if "reference_readiness_report" in payload:
        value = payload.get("reference_readiness_report")
        if isinstance(value, dict):
            validate_reference_readiness_report(value, errors, f"{prefix}.reference_readiness_report")
        else:
            errors.append(f"{prefix}.reference_readiness_report must be an object")
    if "regression_report" in payload:
        value = payload.get("regression_report")
        if isinstance(value, dict):
            validate_regression_report(value, errors, f"{prefix}.regression_report")
        else:
            errors.append(f"{prefix}.regression_report must be an object")

    enforce_decision_invariants(payload, errors, prefix)


def validate_benchmark_run_manifest(payload, errors, prefix):
    require_fields(
        errors,
        payload,
        [
            "run_id",
            "created_at",
            "benchmark_kind",
            "product_path",
            "engine_id",
            "engine_label",
            "model_id",
            "runtime",
            "os_version",
            "hardware",
            "reference_version",
            "sample_set",
            "input_contract",
            "runner_contract",
            "output_paths",
        ],
        prefix,
    )
    if payload.get("benchmark_kind") not in BENCHMARK_KINDS:
        errors.append(f"{prefix}.benchmark_kind is invalid: {payload.get('benchmark_kind')!r}")
    require_type(errors, payload.get("product_path"), bool, f"{prefix}.product_path")
    if payload.get("product_path") is True and payload.get("benchmark_kind") != "product_path_final":
        errors.append(f"{prefix}.product_path=true requires benchmark_kind=product_path_final")
    if payload.get("benchmark_kind") == "product_path_final" and payload.get("product_path") is not True:
        errors.append(f"{prefix}.benchmark_kind=product_path_final requires product_path=true")
    require_type(errors, payload.get("input_contract"), dict, f"{prefix}.input_contract")
    require_type(errors, payload.get("runner_contract"), dict, f"{prefix}.runner_contract")
    require_type(errors, payload.get("output_paths"), list, f"{prefix}.output_paths")
    if "repeat_index" in payload:
        require_non_negative_int(
            errors,
            payload.get("repeat_index"),
            f"{prefix}.repeat_index",
        )


def validate_engine_manifest(payload, errors, prefix):
    require_fields(
        errors,
        payload,
        [
            "engine_id",
            "model_id",
            "runtime",
            "supports_offline",
            "supports_streaming",
            "requires_network",
            "requires_sidecar",
            "requires_os_version",
            "requires_user_permission",
            "health_status",
            "failure_modes",
        ],
        prefix,
    )
    for name in [
        "supports_offline",
        "supports_streaming",
        "requires_network",
        "requires_sidecar",
        "requires_user_permission",
    ]:
        require_type(errors, payload.get(name), bool, f"{prefix}.{name}")
    require_type(errors, payload.get("failure_modes"), list, f"{prefix}.failure_modes")


def validate_engine_comparability_report(payload, errors, prefix):
    require_fields(
        errors,
        payload,
        [
            "comparability_state",
            "eligible_for_official_comparison",
            "run_bundle_manifest_paths",
            "checked_group_count",
            "comparable_fields",
            "comparison_groups",
            "incompatible_groups",
            "blocking_gates",
            "reasons",
            "next_actions",
            "evidence_paths",
        ],
        prefix,
    )
    comparability_state = payload.get("comparability_state")
    if comparability_state not in ENGINE_COMPARABILITY_STATES:
        errors.append(f"{prefix}.comparability_state is invalid: {comparability_state!r}")
    require_type(
        errors,
        payload.get("eligible_for_official_comparison"),
        bool,
        f"{prefix}.eligible_for_official_comparison",
    )
    require_non_negative_int(
        errors,
        payload.get("checked_group_count"),
        f"{prefix}.checked_group_count",
    )
    for name in [
        "run_bundle_manifest_paths",
        "comparable_fields",
        "blocking_gates",
        "reasons",
        "next_actions",
        "evidence_paths",
    ]:
        require_string_list(errors, payload.get(name), f"{prefix}.{name}")

    comparison_groups = payload.get("comparison_groups")
    require_type(errors, comparison_groups, list, f"{prefix}.comparison_groups")
    if isinstance(comparison_groups, list):
        if (
            isinstance(payload.get("checked_group_count"), int)
            and payload.get("checked_group_count") != len(comparison_groups)
        ):
            errors.append(f"{prefix}.checked_group_count must equal comparison_groups length")
        for index, group in enumerate(comparison_groups):
            validate_engine_comparability_group(
                group,
                errors,
                f"{prefix}.comparison_groups[{index}]",
            )

    incompatible_groups = payload.get("incompatible_groups")
    require_type(errors, incompatible_groups, list, f"{prefix}.incompatible_groups")
    if isinstance(incompatible_groups, list):
        for index, group in enumerate(incompatible_groups):
            validate_engine_comparability_group(
                group,
                errors,
                f"{prefix}.incompatible_groups[{index}]",
            )
        if incompatible_groups:
            if comparability_state != "blocked_comparability":
                errors.append(f"{prefix}.incompatible groups require comparability_state=blocked_comparability")
            if payload.get("eligible_for_official_comparison") is not False:
                errors.append(f"{prefix}.incompatible groups require eligible_for_official_comparison=false")
            if "incomparable_engine_runs" not in (payload.get("blocking_gates") or []):
                errors.append(
                    f"{prefix}.incompatible groups require incomparable_engine_runs blocking gate"
                )
        else:
            if comparability_state != "ready_for_official_comparison":
                errors.append(
                    f"{prefix}.complete comparability requires "
                    "comparability_state=ready_for_official_comparison"
                )
            if payload.get("eligible_for_official_comparison") is not True:
                errors.append(f"{prefix}.complete comparability requires eligible_for_official_comparison=true")
            if payload.get("blocking_gates"):
                errors.append(f"{prefix}.complete comparability requires empty blocking_gates")


def validate_engine_comparability_group(group, errors, prefix):
    if not isinstance(group, dict):
        errors.append(f"{prefix} must be an object")
        return
    require_fields(
        errors,
        group,
        [
            "benchmark_kind",
            "run_count",
            "engine_ids",
            "comparable",
            "mismatched_fields",
        ],
        prefix,
    )
    if group.get("benchmark_kind") not in BENCHMARK_KINDS:
        errors.append(f"{prefix}.benchmark_kind is invalid: {group.get('benchmark_kind')!r}")
    require_non_negative_int(errors, group.get("run_count"), f"{prefix}.run_count")
    require_type(errors, group.get("comparable"), bool, f"{prefix}.comparable")
    require_string_list(errors, group.get("engine_ids"), f"{prefix}.engine_ids")
    require_string_list(
        errors,
        group.get("mismatched_fields"),
        f"{prefix}.mismatched_fields",
    )
    if isinstance(group.get("engine_ids"), list) and isinstance(group.get("run_count"), int):
        if group.get("run_count") < len(group["engine_ids"]):
            errors.append(f"{prefix}.run_count must be at least engine_ids length")
    if group.get("comparable") is True and group.get("mismatched_fields"):
        errors.append(f"{prefix}.comparable=true requires empty mismatched_fields")
    if group.get("comparable") is False and not group.get("mismatched_fields"):
        errors.append(f"{prefix}.comparable=false requires mismatched_fields")


def validate_engine_comparability_rerun_plan(payload, errors, prefix):
    require_fields(
        errors,
        payload,
        [
            "plan_state",
            "workflow_report_path",
            "engine_lane_matrix_path",
            "engine_comparability_report_path",
            "reference_version",
            "target_reference_version",
            "incompatible_group_count",
            "groups",
            "commands",
            "command_template_paths",
            "next_actions",
            "evidence_paths",
            "markdown_report_path",
            "html_report_path",
        ],
        prefix,
    )
    if payload.get("plan_state") not in ENGINE_COMPARABILITY_RERUN_PLAN_STATES:
        errors.append(f"{prefix}.plan_state is invalid: {payload.get('plan_state')!r}")
    for name in [
        "workflow_report_path",
        "engine_lane_matrix_path",
        "engine_comparability_report_path",
        "reference_version",
        "target_reference_version",
        "markdown_report_path",
        "html_report_path",
    ]:
        require_non_empty_string(errors, payload.get(name), f"{prefix}.{name}")
    require_non_negative_int(
        errors,
        payload.get("incompatible_group_count"),
        f"{prefix}.incompatible_group_count",
    )
    require_type(errors, payload.get("groups"), list, f"{prefix}.groups")
    if isinstance(payload.get("groups"), list):
        for index, group in enumerate(payload["groups"]):
            validate_engine_comparability_rerun_group(group, errors, f"{prefix}.groups[{index}]")
        if payload.get("incompatible_group_count") != len(payload["groups"]):
            errors.append(f"{prefix}.incompatible_group_count must equal groups length")
    for name in ["commands", "command_template_paths", "next_actions", "evidence_paths"]:
        require_string_list(errors, payload.get(name), f"{prefix}.{name}")
    if payload.get("plan_state") == "no_rerun_needed":
        if payload.get("groups"):
            errors.append(f"{prefix}.no_rerun_needed requires empty groups")
    if payload.get("plan_state") == "ready_to_rerun":
        if not payload.get("groups"):
            errors.append(f"{prefix}.ready_to_rerun requires groups")
        if payload.get("commands") and not payload.get("command_template_paths"):
            errors.append(
                f"{prefix}.ready_to_rerun with commands requires command_template_paths"
            )


def validate_engine_comparability_rerun_group(group, errors, prefix):
    if not isinstance(group, dict):
        errors.append(f"{prefix} must be an object")
        return
    require_fields(
        errors,
        group,
        [
            "benchmark_kind",
            "engine_ids",
            "mismatched_fields",
            "baseline_engine_id",
            "target_reference_version",
            "target_sample_set",
            "target_runner_contract",
            "actions",
        ],
        prefix,
    )
    require_non_empty_string(errors, group.get("benchmark_kind"), f"{prefix}.benchmark_kind")
    if group.get("benchmark_kind") not in BENCHMARK_KINDS:
        errors.append(f"{prefix}.benchmark_kind is invalid: {group.get('benchmark_kind')!r}")
    for name in ["engine_ids", "mismatched_fields"]:
        require_string_list(errors, group.get(name), f"{prefix}.{name}")
    for name in ["baseline_engine_id", "target_reference_version", "target_sample_set"]:
        require_non_empty_string(errors, group.get(name), f"{prefix}.{name}")
    require_type(errors, group.get("target_runner_contract"), dict, f"{prefix}.target_runner_contract")
    require_type(errors, group.get("actions"), list, f"{prefix}.actions")
    if isinstance(group.get("actions"), list):
        if not group["actions"]:
            errors.append(f"{prefix}.actions must not be empty")
        for index, action in enumerate(group["actions"]):
            validate_engine_comparability_rerun_action(action, errors, f"{prefix}.actions[{index}]")


def validate_engine_comparability_rerun_action(action, errors, prefix):
    if not isinstance(action, dict):
        errors.append(f"{prefix} must be an object")
        return
    require_fields(
        errors,
        action,
        [
            "engine_id",
            "benchmark_kind",
            "current_sample_set",
            "current_reference_version",
            "health_status",
            "mismatched_fields",
            "benchmark_run_manifest",
            "rerun_command",
            "convert_command",
            "next_action",
        ],
        prefix,
    )
    for name in [
        "engine_id",
        "benchmark_kind",
        "current_sample_set",
        "current_reference_version",
        "health_status",
        "next_action",
    ]:
        require_non_empty_string(errors, action.get(name), f"{prefix}.{name}")
    require_type(errors, action.get("benchmark_run_manifest"), str, f"{prefix}.benchmark_run_manifest")
    require_type(errors, action.get("rerun_command"), str, f"{prefix}.rerun_command")
    require_type(errors, action.get("convert_command"), str, f"{prefix}.convert_command")
    require_string_list(errors, action.get("mismatched_fields"), f"{prefix}.mismatched_fields")


def validate_engine_reference_alignment_plan(payload, errors, prefix):
    require_fields(
        errors,
        payload,
        [
            "plan_state",
            "workflow_report_path",
            "engine_lane_matrix_path",
            "reference_version",
            "target_reference_version",
            "stale_lane_count",
            "actions",
            "commands",
            "command_template_paths",
            "manual_evidence_needed",
            "next_actions",
            "evidence_paths",
            "runner_capability_gap_summary",
            "markdown_report_path",
            "html_report_path",
        ],
        prefix,
    )
    plan_state = payload.get("plan_state")
    if plan_state not in ENGINE_REFERENCE_ALIGNMENT_PLAN_STATES:
        errors.append(f"{prefix}.plan_state is invalid: {plan_state!r}")
    for name in [
        "workflow_report_path",
        "engine_lane_matrix_path",
        "reference_version",
        "target_reference_version",
        "markdown_report_path",
        "html_report_path",
    ]:
        require_non_empty_string(errors, payload.get(name), f"{prefix}.{name}")
    require_non_negative_int(errors, payload.get("stale_lane_count"), f"{prefix}.stale_lane_count")
    require_type(errors, payload.get("actions"), list, f"{prefix}.actions")
    if isinstance(payload.get("actions"), list):
        for index, action in enumerate(payload["actions"]):
            validate_engine_reference_alignment_action(action, errors, f"{prefix}.actions[{index}]")
        if payload.get("stale_lane_count") != len(payload["actions"]):
            errors.append(f"{prefix}.stale_lane_count must equal actions length")
    for name in [
        "commands",
        "command_template_paths",
        "manual_evidence_needed",
        "next_actions",
        "evidence_paths",
        "runner_capability_gap_summary",
    ]:
        require_string_list(errors, payload.get(name), f"{prefix}.{name}")
    enforce_engine_reference_alignment_plan_invariants(payload, errors, prefix)


def validate_engine_reference_alignment_action(action, errors, prefix):
    if not isinstance(action, dict):
        errors.append(f"{prefix} must be an object")
        return
    require_fields(
        errors,
        action,
        [
            "engine_id",
            "benchmark_kind",
            "current_reference_version",
            "target_reference_version",
            "current_sample_set",
            "health_status",
            "benchmark_run_manifest",
            "source_output_paths",
            "relabel_allowed",
            "rerun_required",
            "rerun_command",
            "conversion_command",
            "raw_dir_command_template",
            "rerun_command_template",
            "conversion_command_template",
            "rerun_blocking_reasons",
            "required_runner_capabilities",
            "next_action",
        ],
        prefix,
    )
    for name in [
        "engine_id",
        "benchmark_kind",
        "current_reference_version",
        "target_reference_version",
        "current_sample_set",
        "health_status",
        "next_action",
    ]:
        require_non_empty_string(errors, action.get(name), f"{prefix}.{name}")
    if action.get("benchmark_kind") not in BENCHMARK_KINDS:
        errors.append(f"{prefix}.benchmark_kind is invalid: {action.get('benchmark_kind')!r}")
    require_type(errors, action.get("benchmark_run_manifest"), str, f"{prefix}.benchmark_run_manifest")
    require_string_list(errors, action.get("source_output_paths"), f"{prefix}.source_output_paths")
    require_type(errors, action.get("relabel_allowed"), bool, f"{prefix}.relabel_allowed")
    require_type(errors, action.get("rerun_required"), bool, f"{prefix}.rerun_required")
    require_type(errors, action.get("rerun_command"), str, f"{prefix}.rerun_command")
    require_type(errors, action.get("conversion_command"), str, f"{prefix}.conversion_command")
    for name in [
        "raw_dir_command_template",
        "rerun_command_template",
        "conversion_command_template",
    ]:
        require_non_empty_string(errors, action.get(name), f"{prefix}.{name}")
    require_string_list(
        errors,
        action.get("rerun_blocking_reasons"),
        f"{prefix}.rerun_blocking_reasons",
    )
    require_string_list(
        errors,
        action.get("required_runner_capabilities"),
        f"{prefix}.required_runner_capabilities",
    )
    if action.get("current_reference_version") == action.get("target_reference_version"):
        errors.append(f"{prefix} must describe a stale reference lane")
    if action.get("relabel_allowed") is not False:
        errors.append(f"{prefix}.relabel_allowed must be false for stale reference alignment")
    if action.get("conversion_command"):
        errors.append(f"{prefix}.conversion_command must be empty until target-reference evidence exists")
    if action.get("rerun_required") is True:
        if not action.get("rerun_blocking_reasons"):
            errors.append(f"{prefix}.rerun_required requires rerun_blocking_reasons")
        if not action.get("required_runner_capabilities"):
            errors.append(f"{prefix}.rerun_required requires required_runner_capabilities")


def enforce_engine_reference_alignment_plan_invariants(payload, errors, prefix):
    plan_state = payload.get("plan_state")
    actions = payload.get("actions") if isinstance(payload.get("actions"), list) else []
    commands = payload.get("commands") if isinstance(payload.get("commands"), list) else []
    command_templates = (
        payload.get("command_template_paths")
        if isinstance(payload.get("command_template_paths"), list)
        else []
    )
    manual_evidence = (
        payload.get("manual_evidence_needed")
        if isinstance(payload.get("manual_evidence_needed"), list)
        else []
    )
    if plan_state == "no_alignment_needed":
        if actions:
            errors.append(f"{prefix}.no_alignment_needed requires empty actions")
        if commands:
            errors.append(f"{prefix}.no_alignment_needed requires empty commands")
        if command_templates:
            errors.append(f"{prefix}.no_alignment_needed requires empty command_template_paths")
        if manual_evidence:
            errors.append(f"{prefix}.no_alignment_needed requires empty manual_evidence_needed")
    if plan_state == "ready_to_align_reference":
        if not actions:
            errors.append(f"{prefix}.ready_to_align_reference requires actions")
        if commands:
            errors.append(f"{prefix}.ready_to_align_reference requires empty commands")
        if not command_templates:
            errors.append(f"{prefix}.ready_to_align_reference requires command_template_paths")
        if not manual_evidence:
            errors.append(f"{prefix}.ready_to_align_reference requires manual_evidence_needed")
        gap_summary = (
            payload.get("runner_capability_gap_summary")
            if isinstance(payload.get("runner_capability_gap_summary"), list)
            else []
        )
        if not gap_summary:
            errors.append(
                f"{prefix}.ready_to_align_reference requires runner_capability_gap_summary"
            )


def validate_engine_coverage_report(payload, errors, prefix):
    require_fields(
        errors,
        payload,
        [
            "coverage_state",
            "eligible_for_official_comparison",
            "engine_lane_matrix_path",
            "reference_versions",
            "entry_count",
            "required_engine_ids",
            "present_engine_ids",
            "missing_engine_ids",
            "ready_engine_ids",
            "unavailable_engine_ids",
            "default_gate_input_engine_ids",
            "required_engine_lane_counts",
            "blocking_gates",
            "reasons",
            "next_actions",
            "evidence_paths",
        ],
        prefix,
    )
    coverage_state = payload.get("coverage_state")
    if coverage_state not in ENGINE_COVERAGE_STATES:
        errors.append(f"{prefix}.coverage_state is invalid: {coverage_state!r}")
    require_type(
        errors,
        payload.get("eligible_for_official_comparison"),
        bool,
        f"{prefix}.eligible_for_official_comparison",
    )
    require_non_empty_string(
        errors,
        payload.get("engine_lane_matrix_path"),
        f"{prefix}.engine_lane_matrix_path",
    )
    require_non_negative_int(errors, payload.get("entry_count"), f"{prefix}.entry_count")

    for name in [
        "reference_versions",
        "required_engine_ids",
        "present_engine_ids",
        "missing_engine_ids",
        "ready_engine_ids",
        "unavailable_engine_ids",
        "default_gate_input_engine_ids",
        "blocking_gates",
        "reasons",
        "next_actions",
        "evidence_paths",
    ]:
        require_string_list(errors, payload.get(name), f"{prefix}.{name}")

    lane_counts = payload.get("required_engine_lane_counts")
    require_type(errors, lane_counts, dict, f"{prefix}.required_engine_lane_counts")
    if isinstance(lane_counts, dict):
        for engine_id, count in lane_counts.items():
            require_non_empty_string(
                errors,
                engine_id,
                f"{prefix}.required_engine_lane_counts key",
            )
            require_non_negative_int(
                errors,
                count,
                f"{prefix}.required_engine_lane_counts.{engine_id}",
            )

    if all(
        isinstance(payload.get(name), list)
        for name in ["required_engine_ids", "present_engine_ids", "missing_engine_ids"]
    ):
        expected_missing = sorted(
            set(payload["required_engine_ids"]) - set(payload["present_engine_ids"])
        )
        if sorted(payload["missing_engine_ids"]) != expected_missing:
            errors.append(f"{prefix}.missing_engine_ids must equal required_engine_ids minus present_engine_ids")

    missing = payload.get("missing_engine_ids")
    blocking_gates = payload.get("blocking_gates")
    eligible = payload.get("eligible_for_official_comparison")
    if isinstance(missing, list):
        if missing:
            if coverage_state != "blocked_engine_coverage":
                errors.append(f"{prefix}.missing engines require coverage_state=blocked_engine_coverage")
            if eligible is not False:
                errors.append(f"{prefix}.missing engines require eligible_for_official_comparison=false")
            if isinstance(blocking_gates, list) and "missing_required_engine" not in blocking_gates:
                errors.append(f"{prefix}.missing engines require missing_required_engine blocking gate")
        else:
            if coverage_state != "ready_for_official_comparison":
                errors.append(f"{prefix}.complete coverage requires coverage_state=ready_for_official_comparison")
            if eligible is not True:
                errors.append(f"{prefix}.complete coverage requires eligible_for_official_comparison=true")
            if isinstance(blocking_gates, list) and blocking_gates:
                errors.append(f"{prefix}.complete coverage requires empty blocking_gates")


def validate_engine_lane_matrix(payload, errors, prefix):
    require_fields(
        errors,
        payload,
        [
            "reference_versions",
            "entry_count",
            "lanes",
            "source_paths",
        ],
        prefix,
    )
    reference_versions = payload.get("reference_versions")
    require_type(errors, reference_versions, list, f"{prefix}.reference_versions")
    if isinstance(reference_versions, list):
        for index, reference_version in enumerate(reference_versions):
            require_non_empty_string(
                errors,
                reference_version,
                f"{prefix}.reference_versions[{index}]",
            )
        if len(reference_versions) != 1:
            errors.append(
                f"{prefix}.reference_versions must contain exactly one reference version "
                "for official comparison"
            )

    require_non_negative_int(errors, payload.get("entry_count"), f"{prefix}.entry_count")
    lanes = payload.get("lanes")
    require_type(errors, lanes, list, f"{prefix}.lanes")
    if isinstance(lanes, list):
        if isinstance(payload.get("entry_count"), int) and payload.get("entry_count") != len(lanes):
            errors.append(f"{prefix}.entry_count must equal lanes length")
        row_reference_versions = []
        for index, row in enumerate(lanes):
            if not isinstance(row, dict):
                errors.append(f"{prefix}.lanes[{index}] must be an object")
                continue
            validate_engine_lane_row(row, errors, f"{prefix}.lanes[{index}]")
            if isinstance(row.get("reference_version"), str) and row.get("reference_version"):
                row_reference_versions.append(row["reference_version"])
        if isinstance(reference_versions, list):
            expected = sorted(set(row_reference_versions))
            if reference_versions != expected:
                errors.append(f"{prefix}.reference_versions must match lane reference_version values")

    source_paths = payload.get("source_paths")
    require_type(errors, source_paths, list, f"{prefix}.source_paths")
    if isinstance(source_paths, list):
        for index, source_path in enumerate(source_paths):
            require_non_empty_string(errors, source_path, f"{prefix}.source_paths[{index}]")


def validate_engine_lane_row(row, errors, prefix):
    require_fields(
        errors,
        row,
        [
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
            "source_paths",
        ],
        prefix,
    )
    for name in [
        "engine_id",
        "engine_label",
        "lane",
        "benchmark_kind",
        "runtime",
        "model_id",
        "reference_version",
        "sample_set",
        "health_status",
    ]:
        require_non_empty_string(errors, row.get(name), f"{prefix}.{name}")
    if row.get("lane") not in BENCHMARK_KINDS:
        errors.append(f"{prefix}.lane is invalid: {row.get('lane')!r}")
    if row.get("benchmark_kind") not in BENCHMARK_KINDS:
        errors.append(f"{prefix}.benchmark_kind is invalid: {row.get('benchmark_kind')!r}")
    for name in [
        "product_path",
        "default_gate_input",
        "requires_sidecar",
        "supports_streaming",
        "user_impact_metric_complete",
    ]:
        require_type(errors, row.get(name), bool, f"{prefix}.{name}")
    for name in ["sample_count", "empty_final_count", "timeout_count", "crash_count"]:
        require_non_negative_int(errors, row.get(name), f"{prefix}.{name}")
    for name in ["weighted_cer", "macro_cer"]:
        require_number(errors, row.get(name), f"{prefix}.{name}")
    source_paths = row.get("source_paths")
    require_type(errors, source_paths, dict, f"{prefix}.source_paths")
    if isinstance(source_paths, dict):
        require_fields(
            errors,
            source_paths,
            ["benchmark_run_manifest", "metric_summary", "engine_manifest"],
            f"{prefix}.source_paths",
        )
        for name in ["benchmark_run_manifest", "metric_summary", "engine_manifest"]:
            require_non_empty_string(
                errors,
                source_paths.get(name),
                f"{prefix}.source_paths.{name}",
            )


def validate_engine_run_bundle_workflow_report(payload, errors, prefix):
    require_fields(
        errors,
        payload,
        [
            "workflow_state",
            "engine_lane_matrix_path",
            "engine_lane_matrix_csv_path",
            "engine_lane_matrix_markdown_path",
            "engine_comparability_report_path",
            "engine_comparability_state",
            "incompatible_comparison_groups",
            "engine_coverage_report_path",
            "engine_coverage_state",
            "required_engine_ids",
            "missing_engine_ids",
            "selected_engine_id",
            "selected_lane",
            "selected_default_gate_input",
            "candidate_benchmark_run_manifest_path",
            "candidate_metric_summary_path",
            "candidate_engine_manifest_path",
            "official_decision_workflow_report_path",
            "decision_state",
            "default_change",
            "regression_state",
            "blocking_gates",
            "next_actions",
        ],
        prefix,
    )
    if payload.get("workflow_state") != "completed":
        errors.append(f"{prefix}.workflow_state is invalid: {payload.get('workflow_state')!r}")
    for name in [
        "engine_lane_matrix_path",
        "engine_lane_matrix_csv_path",
        "engine_lane_matrix_markdown_path",
        "engine_comparability_report_path",
        "engine_coverage_report_path",
        "selected_engine_id",
        "selected_lane",
        "candidate_benchmark_run_manifest_path",
        "candidate_metric_summary_path",
        "candidate_engine_manifest_path",
        "official_decision_workflow_report_path",
    ]:
        require_non_empty_string(errors, payload.get(name), f"{prefix}.{name}")
    if payload.get("selected_lane") not in BENCHMARK_KINDS:
        errors.append(f"{prefix}.selected_lane is invalid: {payload.get('selected_lane')!r}")
    if payload.get("engine_comparability_state") not in ENGINE_COMPARABILITY_STATES:
        errors.append(
            f"{prefix}.engine_comparability_state is invalid: "
            f"{payload.get('engine_comparability_state')!r}"
        )
    elif payload.get("engine_comparability_state") != "ready_for_official_comparison":
        errors.append(f"{prefix}.completed workflow requires ready engine comparability")
    incompatible_groups = payload.get("incompatible_comparison_groups")
    require_type(
        errors,
        incompatible_groups,
        list,
        f"{prefix}.incompatible_comparison_groups",
    )
    if isinstance(incompatible_groups, list):
        if incompatible_groups:
            errors.append(f"{prefix}.completed workflow requires empty incompatible_comparison_groups")
        for index, group in enumerate(incompatible_groups):
            validate_engine_comparability_group(
                group,
                errors,
                f"{prefix}.incompatible_comparison_groups[{index}]",
            )
    if payload.get("engine_coverage_state") not in ENGINE_COVERAGE_STATES:
        errors.append(
            f"{prefix}.engine_coverage_state is invalid: {payload.get('engine_coverage_state')!r}"
        )
    elif payload.get("engine_coverage_state") != "ready_for_official_comparison":
        errors.append(f"{prefix}.completed workflow requires ready engine coverage")
    for name in ["required_engine_ids", "missing_engine_ids"]:
        require_string_list(errors, payload.get(name), f"{prefix}.{name}")
    if payload.get("missing_engine_ids"):
        errors.append(f"{prefix}.completed workflow requires empty missing_engine_ids")
    require_type(
        errors,
        payload.get("selected_default_gate_input"),
        bool,
        f"{prefix}.selected_default_gate_input",
    )
    if payload.get("decision_state") not in DECISION_STATES:
        errors.append(f"{prefix}.decision_state is invalid: {payload.get('decision_state')!r}")
    if payload.get("default_change") not in DEFAULT_CHANGE_VALUES:
        errors.append(f"{prefix}.default_change is invalid: {payload.get('default_change')!r}")
    if payload.get("regression_state") not in REGRESSION_STATES:
        errors.append(f"{prefix}.regression_state is invalid: {payload.get('regression_state')!r}")
    require_type(errors, payload.get("blocking_gates"), list, f"{prefix}.blocking_gates")
    require_type(errors, payload.get("next_actions"), list, f"{prefix}.next_actions")


def validate_engine_run_bundle_manifest(payload, errors, prefix):
    require_fields(
        errors,
        payload,
        [
            "reference_version",
            "bundle_count",
            "runs",
        ],
        prefix,
    )
    require_non_empty_string(errors, payload.get("reference_version"), f"{prefix}.reference_version")
    require_non_negative_int(errors, payload.get("bundle_count"), f"{prefix}.bundle_count")
    runs = payload.get("runs")
    require_type(errors, runs, list, f"{prefix}.runs")
    if isinstance(runs, list):
        if isinstance(payload.get("bundle_count"), int) and payload.get("bundle_count") != len(runs):
            errors.append(f"{prefix}.bundle_count must equal runs length")
        for index, run in enumerate(runs):
            validate_engine_run_bundle_entry(run, errors, f"{prefix}.runs[{index}]")
    if "repeat_count" in payload:
        repeat_count = payload.get("repeat_count")
        if (
            not isinstance(repeat_count, int)
            or isinstance(repeat_count, bool)
            or repeat_count < 1
        ):
            errors.append(f"{prefix}.repeat_count must be an integer >= 1")
    if "engine_ranking" in payload:
        validate_engine_ranking(
            payload.get("engine_ranking"),
            errors,
            f"{prefix}.engine_ranking",
        )
    if "relative_improvement" in payload:
        validate_relative_improvement(
            payload.get("relative_improvement"),
            errors,
            f"{prefix}.relative_improvement",
        )


def validate_engine_ranking(ranking, errors, prefix):
    if not isinstance(ranking, list):
        errors.append(f"{prefix} must be list")
        return
    for index, item in enumerate(ranking):
        validate_engine_ranking_item(item, errors, f"{prefix}[{index}]")


def validate_engine_ranking_item(item, errors, prefix):
    if not isinstance(item, dict):
        errors.append(f"{prefix} must be an object")
        return
    rank = item.get("rank")
    if not isinstance(rank, int) or isinstance(rank, bool) or rank < 1:
        errors.append(f"{prefix}.rank must be an integer >= 1")
    require_non_empty_string(errors, item.get("engine_id"), f"{prefix}.engine_id")
    require_ratio(errors, item.get("weighted_cer"), f"{prefix}.weighted_cer")
    if "tie_group" in item:
        tie_group = item.get("tie_group")
        if not isinstance(tie_group, int) or isinstance(tie_group, bool) or tie_group < 1:
            errors.append(f"{prefix}.tie_group must be an integer >= 1")


def validate_relative_improvement(relative_improvement, errors, prefix):
    if not isinstance(relative_improvement, dict):
        errors.append(f"{prefix} must be dict")
        return
    has_cer_improvement_rate = "cer_improvement_rate" in relative_improvement
    has_baseline_engine_id = "baseline_engine_id" in relative_improvement
    if has_cer_improvement_rate != has_baseline_engine_id:
        errors.append(
            f"{prefix} must include both cer_improvement_rate and baseline_engine_id"
        )
        return
    if not has_cer_improvement_rate:
        return
    cer_improvement_rate = relative_improvement.get("cer_improvement_rate")
    if (
        not isinstance(cer_improvement_rate, (int, float))
        or isinstance(cer_improvement_rate, bool)
        or cer_improvement_rate < -1.0
        or cer_improvement_rate > 1.0
    ):
        errors.append(f"{prefix}.cer_improvement_rate must be a number between -1 and 1")
    require_non_empty_string(
        errors,
        relative_improvement.get("baseline_engine_id"),
        f"{prefix}.baseline_engine_id",
    )


def validate_engine_run_bundle_entry(run, errors, prefix):
    if not isinstance(run, dict):
        errors.append(f"{prefix} must be an object")
        return
    require_fields(
        errors,
        run,
        [
            "engine_id",
            "benchmark_run_manifest",
            "metric_summary",
            "engine_manifest",
        ],
        prefix,
    )
    for name in [
        "engine_id",
        "benchmark_run_manifest",
        "metric_summary",
        "engine_manifest",
    ]:
        require_non_empty_string(errors, run.get(name), f"{prefix}.{name}")
    if "decoding_parameters" in run:
        require_type(
            errors,
            run.get("decoding_parameters"),
            dict,
            f"{prefix}.decoding_parameters",
        )


def validate_manual_review_manifest(payload, errors, prefix):
    require_fields(
        errors,
        payload,
        [
            "complete",
            "selected_count",
            "reviewed_count",
            "usable_review_count",
            "manual_followup_count",
            "classification_counts",
            "next_bucket_counts",
            "review_issue_counts",
        ],
        prefix,
    )
    require_type(errors, payload.get("complete"), bool, f"{prefix}.complete")
    for name in [
        "selected_count",
        "reviewed_count",
        "usable_review_count",
        "manual_followup_count",
    ]:
        require_non_negative_int(errors, payload.get(name), f"{prefix}.{name}")
    for name in ["classification_counts", "next_bucket_counts", "review_issue_counts"]:
        require_type(errors, payload.get(name), dict, f"{prefix}.{name}")


def validate_metric_summary(payload, errors, prefix):
    require_fields(
        errors,
        payload,
        [
            "sample_count",
            "weighted_cer",
            "macro_cer",
            "empty_final_count",
            "timeout_count",
            "crash_count",
        ],
        prefix,
    )
    require_non_negative_int(errors, payload.get("sample_count"), f"{prefix}.sample_count")
    for name in ["weighted_cer", "macro_cer"]:
        require_number(errors, payload.get(name), f"{prefix}.{name}")
    if "baseline_cer" in payload:
        require_ratio(errors, payload.get("baseline_cer"), f"{prefix}.baseline_cer")
    if "phantom_rate" in payload:
        require_ratio(errors, payload.get("phantom_rate"), f"{prefix}.phantom_rate")
    if "cer_std" in payload:
        require_ratio(errors, payload.get("cer_std"), f"{prefix}.cer_std")
    if "cer_ci95_half_width" in payload:
        require_ratio(errors, payload.get("cer_ci95_half_width"), f"{prefix}.cer_ci95_half_width")
    for name in ["empty_final_count", "timeout_count", "crash_count"]:
        require_non_negative_int(errors, payload.get(name), f"{prefix}.{name}")
    if "user_impact_metric_complete" in payload:
        require_type(
            errors,
            payload.get("user_impact_metric_complete"),
            bool,
            f"{prefix}.user_impact_metric_complete",
        )
    if payload.get("user_impact_metric_complete") is True:
        if "user_impact_metrics" not in payload:
            errors.append(f"{prefix}.user_impact_metrics is required when user_impact_metric_complete=true")
        else:
            validate_user_impact_metrics(
                payload.get("user_impact_metrics"),
                errors,
                f"{prefix}.user_impact_metrics",
            )
    elif "user_impact_metrics" in payload:
        validate_user_impact_metrics(
            payload.get("user_impact_metrics"),
            errors,
            f"{prefix}.user_impact_metrics",
        )


def validate_official_decision_workflow_report(payload, errors, prefix):
    require_fields(
        errors,
        payload,
        [
            "workflow_state",
            "decision_state",
            "default_change",
            "eligible_for_default",
            "regression_state",
            "regression_report_path",
            "decision_manifest_path",
            "markdown_report_path",
            "html_report_path",
            "blocking_gates",
            "next_actions",
        ],
        prefix,
    )
    if payload.get("workflow_state") != "completed":
        errors.append(f"{prefix}.workflow_state is invalid: {payload.get('workflow_state')!r}")
    if payload.get("decision_state") not in DECISION_STATES:
        errors.append(f"{prefix}.decision_state is invalid: {payload.get('decision_state')!r}")
    if payload.get("default_change") not in DEFAULT_CHANGE_VALUES:
        errors.append(f"{prefix}.default_change is invalid: {payload.get('default_change')!r}")
    if payload.get("regression_state") not in REGRESSION_STATES:
        errors.append(f"{prefix}.regression_state is invalid: {payload.get('regression_state')!r}")
    require_type(errors, payload.get("eligible_for_default"), bool, f"{prefix}.eligible_for_default")
    for name in [
        "regression_report_path",
        "decision_manifest_path",
        "markdown_report_path",
        "html_report_path",
    ]:
        require_non_empty_string(errors, payload.get(name), f"{prefix}.{name}")
    require_type(errors, payload.get("blocking_gates"), list, f"{prefix}.blocking_gates")
    require_type(errors, payload.get("next_actions"), list, f"{prefix}.next_actions")


def validate_official_comparison_readiness_report(payload, errors, prefix):
    require_fields(
        errors,
        payload,
        [
            "readiness_state",
            "eligible_for_official_comparison",
            "reference_version",
            "matrix_reference_versions",
            "reference_readiness_report_path",
            "engine_comparability_report_path",
            "engine_coverage_report_path",
            "engine_lane_matrix_path",
            "reference_readiness_state",
            "engine_comparability_state",
            "engine_coverage_state",
            "required_engine_ids",
            "missing_engine_ids",
            "product_path_lane_count",
            "product_path_default_gate_input_count",
            "blocking_gates",
            "reasons",
            "next_actions",
            "evidence_paths",
        ],
        prefix,
    )
    readiness_state = payload.get("readiness_state")
    if readiness_state not in OFFICIAL_COMPARISON_READINESS_STATES:
        errors.append(f"{prefix}.readiness_state is invalid: {readiness_state!r}")
    require_type(
        errors,
        payload.get("eligible_for_official_comparison"),
        bool,
        f"{prefix}.eligible_for_official_comparison",
    )
    for name in [
        "reference_version",
        "reference_readiness_report_path",
        "engine_comparability_report_path",
        "engine_coverage_report_path",
        "engine_lane_matrix_path",
    ]:
        require_non_empty_string(errors, payload.get(name), f"{prefix}.{name}")
    if payload.get("reference_readiness_state") not in REFERENCE_READINESS_STATES:
        errors.append(
            f"{prefix}.reference_readiness_state is invalid: "
            f"{payload.get('reference_readiness_state')!r}"
        )
    if payload.get("engine_comparability_state") not in ENGINE_COMPARABILITY_STATES:
        errors.append(
            f"{prefix}.engine_comparability_state is invalid: "
            f"{payload.get('engine_comparability_state')!r}"
        )
    if payload.get("engine_coverage_state") not in ENGINE_COVERAGE_STATES:
        errors.append(
            f"{prefix}.engine_coverage_state is invalid: {payload.get('engine_coverage_state')!r}"
        )
    for name in [
        "required_engine_ids",
        "missing_engine_ids",
        "matrix_reference_versions",
        "blocking_gates",
        "reasons",
        "next_actions",
        "evidence_paths",
    ]:
        require_string_list(errors, payload.get(name), f"{prefix}.{name}")
    require_non_negative_int(
        errors,
        payload.get("product_path_lane_count"),
        f"{prefix}.product_path_lane_count",
    )
    require_non_negative_int(
        errors,
        payload.get("product_path_default_gate_input_count"),
        f"{prefix}.product_path_default_gate_input_count",
    )
    if (
        isinstance(payload.get("product_path_lane_count"), int)
        and isinstance(payload.get("product_path_default_gate_input_count"), int)
        and payload["product_path_default_gate_input_count"] > payload["product_path_lane_count"]
    ):
        errors.append(
            f"{prefix}.product_path_default_gate_input_count cannot exceed product_path_lane_count"
        )
    enforce_official_comparison_readiness_invariants(payload, errors, prefix)


def enforce_official_comparison_readiness_invariants(payload, errors, prefix):
    readiness_state = payload.get("readiness_state")
    eligible = payload.get("eligible_for_official_comparison")
    blocking_gates = payload.get("blocking_gates") or []
    reference_ready = payload.get("reference_readiness_state") == "ready_for_default_gate"
    reference_version_ready = payload.get("matrix_reference_versions") == [
        payload.get("reference_version")
    ]
    comparability_ready = (
        payload.get("engine_comparability_state") == "ready_for_official_comparison"
    )
    coverage_ready = payload.get("engine_coverage_state") == "ready_for_official_comparison"
    product_path_ready = int_or_zero(payload.get("product_path_default_gate_input_count")) > 0

    expected_state = "ready_for_official_comparison"
    if not reference_ready or not reference_version_ready:
        expected_state = "blocked_reference"
    elif not comparability_ready:
        expected_state = "blocked_engine_comparability"
    elif not coverage_ready:
        expected_state = "blocked_engine_coverage"
    elif not product_path_ready:
        expected_state = "blocked_product_path"

    if readiness_state in OFFICIAL_COMPARISON_READINESS_STATES and readiness_state != expected_state:
        errors.append(
            f"{prefix}.readiness_state must be {expected_state} for current gate states"
        )
    if expected_state == "ready_for_official_comparison":
        if eligible is not True:
            errors.append(f"{prefix}.ready state requires eligible_for_official_comparison=true")
        if blocking_gates:
            errors.append(f"{prefix}.ready state requires empty blocking_gates")
        if payload.get("missing_engine_ids"):
            errors.append(f"{prefix}.ready state requires empty missing_engine_ids")
    else:
        if eligible is True:
            errors.append(f"{prefix}.blocked state requires eligible_for_official_comparison=false")
        if not blocking_gates:
            errors.append(f"{prefix}.blocked state requires blocking_gates")


def validate_official_comparison_preflight_workflow_report(payload, errors, prefix):
    require_fields(
        errors,
        payload,
        [
            "workflow_state",
            "eligible_for_official_comparison",
            "reference_version",
            "reference_readiness_report_path",
            "engine_lane_matrix_path",
            "engine_lane_matrix_csv_path",
            "engine_lane_matrix_markdown_path",
            "engine_comparability_report_path",
            "engine_coverage_report_path",
            "product_path_readiness_report_path",
            "official_comparison_readiness_report_path",
            "markdown_report_path",
            "html_report_path",
            "next_action_plan_path",
            "next_action_plan_markdown_path",
            "next_action_plan_html_path",
            "reference_readiness_state",
            "engine_comparability_state",
            "engine_coverage_state",
            "product_path_readiness_state",
            "official_comparison_readiness_state",
            "required_engine_ids",
            "missing_engine_ids",
            "product_path_lane_count",
            "product_path_default_gate_input_count",
            "blocking_gates",
            "next_actions",
            "evidence_paths",
        ],
        prefix,
    )
    workflow_state = payload.get("workflow_state")
    if workflow_state not in OFFICIAL_COMPARISON_PREFLIGHT_WORKFLOW_STATES:
        errors.append(f"{prefix}.workflow_state is invalid: {workflow_state!r}")
    require_type(
        errors,
        payload.get("eligible_for_official_comparison"),
        bool,
        f"{prefix}.eligible_for_official_comparison",
    )
    for name in [
        "reference_version",
        "reference_readiness_report_path",
        "engine_lane_matrix_path",
        "engine_lane_matrix_csv_path",
        "engine_lane_matrix_markdown_path",
        "engine_comparability_report_path",
        "engine_coverage_report_path",
        "product_path_readiness_report_path",
        "official_comparison_readiness_report_path",
        "markdown_report_path",
        "html_report_path",
        "next_action_plan_path",
        "next_action_plan_markdown_path",
        "next_action_plan_html_path",
    ]:
        require_non_empty_string(errors, payload.get(name), f"{prefix}.{name}")
    if payload.get("reference_readiness_state") not in REFERENCE_READINESS_STATES:
        errors.append(
            f"{prefix}.reference_readiness_state is invalid: "
            f"{payload.get('reference_readiness_state')!r}"
        )
    if payload.get("engine_comparability_state") not in ENGINE_COMPARABILITY_STATES:
        errors.append(
            f"{prefix}.engine_comparability_state is invalid: "
            f"{payload.get('engine_comparability_state')!r}"
        )
    if payload.get("engine_coverage_state") not in ENGINE_COVERAGE_STATES:
        errors.append(
            f"{prefix}.engine_coverage_state is invalid: {payload.get('engine_coverage_state')!r}"
        )
    if payload.get("product_path_readiness_state") not in PRODUCT_PATH_READINESS_STATES:
        errors.append(
            f"{prefix}.product_path_readiness_state is invalid: "
            f"{payload.get('product_path_readiness_state')!r}"
        )
    if payload.get("official_comparison_readiness_state") not in OFFICIAL_COMPARISON_READINESS_STATES:
        errors.append(
            f"{prefix}.official_comparison_readiness_state is invalid: "
            f"{payload.get('official_comparison_readiness_state')!r}"
        )
    for name in [
        "required_engine_ids",
        "missing_engine_ids",
        "blocking_gates",
        "next_actions",
        "evidence_paths",
    ]:
        require_string_list(errors, payload.get(name), f"{prefix}.{name}")
    require_non_negative_int(
        errors,
        payload.get("product_path_lane_count"),
        f"{prefix}.product_path_lane_count",
    )
    require_non_negative_int(
        errors,
        payload.get("product_path_default_gate_input_count"),
        f"{prefix}.product_path_default_gate_input_count",
    )
    enforce_official_comparison_preflight_workflow_invariants(payload, errors, prefix)


def enforce_official_comparison_preflight_workflow_invariants(payload, errors, prefix):
    workflow_state = payload.get("workflow_state")
    eligible = payload.get("eligible_for_official_comparison")
    blocking_gates = payload.get("blocking_gates") or []
    ready = (
        payload.get("reference_readiness_state") == "ready_for_default_gate"
        and payload.get("engine_comparability_state") == "ready_for_official_comparison"
        and payload.get("engine_coverage_state") == "ready_for_official_comparison"
        and payload.get("product_path_readiness_state") == "ready_for_product_path_default_gate"
        and payload.get("official_comparison_readiness_state") == "ready_for_official_comparison"
        and not payload.get("missing_engine_ids")
    )
    expected_state = "ready_for_official_comparison" if ready else "blocked_preflight"
    if workflow_state in OFFICIAL_COMPARISON_PREFLIGHT_WORKFLOW_STATES and workflow_state != expected_state:
        errors.append(f"{prefix}.workflow_state must be {expected_state} for current gate states")
    if expected_state == "ready_for_official_comparison":
        if eligible is not True:
            errors.append(f"{prefix}.ready state requires eligible_for_official_comparison=true")
        if blocking_gates:
            errors.append(f"{prefix}.ready state requires empty blocking_gates")
    else:
        if eligible is True:
            errors.append(f"{prefix}.blocked state requires eligible_for_official_comparison=false")
        if not blocking_gates:
            errors.append(f"{prefix}.blocked state requires blocking_gates")


def validate_official_comparison_next_action_plan(payload, errors, prefix):
    require_fields(
        errors,
        payload,
        [
            "plan_state",
            "workflow_report_path",
            "workflow_state",
            "eligible_for_official_comparison",
            "reference_version",
            "blocking_gates",
            "task_count",
            "open_task_count",
            "tasks",
            "evidence_paths",
            "markdown_report_path",
            "html_report_path",
        ],
        prefix,
    )
    plan_state = payload.get("plan_state")
    if plan_state not in OFFICIAL_COMPARISON_NEXT_ACTION_PLAN_STATES:
        errors.append(f"{prefix}.plan_state is invalid: {plan_state!r}")
    if payload.get("workflow_state") not in OFFICIAL_COMPARISON_PREFLIGHT_WORKFLOW_STATES:
        errors.append(f"{prefix}.workflow_state is invalid: {payload.get('workflow_state')!r}")
    require_type(
        errors,
        payload.get("eligible_for_official_comparison"),
        bool,
        f"{prefix}.eligible_for_official_comparison",
    )
    for name in [
        "workflow_report_path",
        "reference_version",
        "markdown_report_path",
        "html_report_path",
    ]:
        require_non_empty_string(errors, payload.get(name), f"{prefix}.{name}")
    for name in ["blocking_gates", "evidence_paths"]:
        require_string_list(errors, payload.get(name), f"{prefix}.{name}")
    require_non_negative_int(errors, payload.get("task_count"), f"{prefix}.task_count")
    require_non_negative_int(errors, payload.get("open_task_count"), f"{prefix}.open_task_count")
    require_type(errors, payload.get("tasks"), list, f"{prefix}.tasks")
    if isinstance(payload.get("tasks"), list):
        for index, task in enumerate(payload["tasks"]):
            validate_official_comparison_next_action_task(
                task,
                errors,
                f"{prefix}.tasks[{index}]",
            )
        if payload.get("task_count") != len(payload["tasks"]):
            errors.append(f"{prefix}.task_count must equal tasks length")
        open_count = sum(
            1
            for task in payload["tasks"]
            if isinstance(task, dict) and task.get("state") in {"open", "waiting"}
        )
        if payload.get("open_task_count") != open_count:
            errors.append(f"{prefix}.open_task_count must equal open/waiting task count")
    enforce_official_comparison_next_action_plan_invariants(payload, errors, prefix)


def validate_official_comparison_next_action_task(task, errors, prefix):
    if not isinstance(task, dict):
        errors.append(f"{prefix} must be an object")
        return
    require_fields(
        errors,
        task,
        [
            "task_id",
            "category",
            "title",
            "state",
            "blocking_gates",
            "target",
            "command",
            "evidence_needed",
            "evidence_paths",
        ],
        prefix,
    )
    for name in ["task_id", "category", "title", "target", "command"]:
        require_non_empty_string(errors, task.get(name), f"{prefix}.{name}")
    if task.get("state") not in OFFICIAL_COMPARISON_NEXT_ACTION_TASK_STATES:
        errors.append(f"{prefix}.state is invalid: {task.get('state')!r}")
    for name in ["blocking_gates", "evidence_needed", "evidence_paths"]:
        require_string_list(errors, task.get(name), f"{prefix}.{name}")


def enforce_official_comparison_next_action_plan_invariants(payload, errors, prefix):
    plan_state = payload.get("plan_state")
    eligible = payload.get("eligible_for_official_comparison")
    blocking_gates = payload.get("blocking_gates") or []
    open_task_count = int_or_zero(payload.get("open_task_count"))
    expected_state = (
        "ready_for_official_comparison"
        if eligible is True
        else "blocked_next_actions"
    )
    if plan_state in OFFICIAL_COMPARISON_NEXT_ACTION_PLAN_STATES and plan_state != expected_state:
        errors.append(f"{prefix}.plan_state must be {expected_state} for eligible state")
    if expected_state == "ready_for_official_comparison":
        if blocking_gates:
            errors.append(f"{prefix}.ready state requires empty blocking_gates")
        if open_task_count:
            errors.append(f"{prefix}.ready state requires open_task_count=0")
    else:
        if not blocking_gates:
            errors.append(f"{prefix}.blocked state requires blocking_gates")
        if open_task_count <= 0:
            errors.append(f"{prefix}.blocked state requires open_task_count>0")


def validate_official_comparison_next_action_artifact_prep_report(payload, errors, prefix):
    require_fields(
        errors,
        payload,
        [
            "prep_state",
            "workflow_report_path",
            "workflow_state",
            "eligible_for_official_comparison",
            "reference_version",
            "reference_batch_duration_minutes",
            "prepared_task_ids",
            "prepared_artifact_count",
            "prepared_artifact_paths",
            "next_actions",
            "notes",
            "evidence_paths",
            "markdown_report_path",
            "html_report_path",
        ],
        prefix,
    )
    prep_state = payload.get("prep_state")
    if prep_state not in OFFICIAL_COMPARISON_NEXT_ACTION_ARTIFACT_PREP_STATES:
        errors.append(f"{prefix}.prep_state is invalid: {prep_state!r}")
    if payload.get("workflow_state") not in OFFICIAL_COMPARISON_PREFLIGHT_WORKFLOW_STATES:
        errors.append(f"{prefix}.workflow_state is invalid: {payload.get('workflow_state')!r}")
    require_type(
        errors,
        payload.get("eligible_for_official_comparison"),
        bool,
        f"{prefix}.eligible_for_official_comparison",
    )
    for name in [
        "workflow_report_path",
        "reference_version",
        "markdown_report_path",
        "html_report_path",
    ]:
        require_non_empty_string(errors, payload.get(name), f"{prefix}.{name}")
    require_number(
        errors,
        payload.get("reference_batch_duration_minutes"),
        f"{prefix}.reference_batch_duration_minutes",
    )
    if (
        isinstance(payload.get("reference_batch_duration_minutes"), (int, float))
        and payload.get("reference_batch_duration_minutes") <= 0
    ):
        errors.append(f"{prefix}.reference_batch_duration_minutes must be positive")
    require_non_negative_int(
        errors,
        payload.get("prepared_artifact_count"),
        f"{prefix}.prepared_artifact_count",
    )
    for name in [
        "prepared_task_ids",
        "prepared_artifact_paths",
        "next_actions",
        "notes",
        "evidence_paths",
    ]:
        require_string_list(errors, payload.get(name), f"{prefix}.{name}")
    if isinstance(payload.get("prepared_artifact_paths"), list):
        if payload.get("prepared_artifact_count") != len(payload["prepared_artifact_paths"]):
            errors.append(f"{prefix}.prepared_artifact_count must equal prepared_artifact_paths length")
    enforce_official_comparison_next_action_artifact_prep_invariants(payload, errors, prefix)


def enforce_official_comparison_next_action_artifact_prep_invariants(payload, errors, prefix):
    prep_state = payload.get("prep_state")
    artifact_count = int_or_zero(payload.get("prepared_artifact_count"))
    task_ids = payload.get("prepared_task_ids") or []
    if prep_state in {"prepared_next_action_artifacts", "prepared_reference_review_pack"}:
        if artifact_count <= 0:
            errors.append(f"{prefix}.{prep_state} requires prepared_artifact_count>0")
    if prep_state == "prepared_reference_review_pack":
        if "reference_review" not in task_ids:
            errors.append(f"{prefix}.prepared_reference_review_pack requires reference_review task id")
    if prep_state == "nothing_to_prepare":
        if artifact_count:
            errors.append(f"{prefix}.nothing_to_prepare requires prepared_artifact_count=0")
        if task_ids:
            errors.append(f"{prefix}.nothing_to_prepare requires empty prepared_task_ids")
    if prep_state == "blocked_missing_reference_manifest":
        if not payload.get("next_actions"):
            errors.append(f"{prefix}.blocked_missing_reference_manifest requires next_actions")


def validate_official_comparison_next_action_execution_status_report(payload, errors, prefix):
    require_fields(
        errors,
        payload,
        [
            "execution_state",
            "workflow_report_path",
            "artifact_prep_report_path",
            "workflow_state",
            "eligible_for_official_comparison",
            "reference_version",
            "task_status_count",
            "ready_task_count",
            "blocked_task_count",
            "total_runnable_command_count",
            "task_statuses",
            "next_actions",
            "evidence_paths",
            "markdown_report_path",
            "html_report_path",
        ],
        prefix,
    )
    execution_state = payload.get("execution_state")
    if execution_state not in OFFICIAL_COMPARISON_NEXT_ACTION_EXECUTION_STATES:
        errors.append(f"{prefix}.execution_state is invalid: {execution_state!r}")
    if payload.get("workflow_state") not in OFFICIAL_COMPARISON_PREFLIGHT_WORKFLOW_STATES:
        errors.append(f"{prefix}.workflow_state is invalid: {payload.get('workflow_state')!r}")
    require_type(
        errors,
        payload.get("eligible_for_official_comparison"),
        bool,
        f"{prefix}.eligible_for_official_comparison",
    )
    for name in [
        "workflow_report_path",
        "artifact_prep_report_path",
        "reference_version",
        "markdown_report_path",
        "html_report_path",
    ]:
        require_non_empty_string(errors, payload.get(name), f"{prefix}.{name}")
    for name in [
        "task_status_count",
        "ready_task_count",
        "blocked_task_count",
        "total_runnable_command_count",
    ]:
        require_non_negative_int(errors, payload.get(name), f"{prefix}.{name}")
    for name in ["next_actions", "evidence_paths"]:
        require_string_list(errors, payload.get(name), f"{prefix}.{name}")
    require_type(errors, payload.get("task_statuses"), list, f"{prefix}.task_statuses")
    if isinstance(payload.get("task_statuses"), list):
        for index, status in enumerate(payload["task_statuses"]):
            validate_official_comparison_next_action_task_execution_status(
                status,
                errors,
                f"{prefix}.task_statuses[{index}]",
            )
    enforce_official_comparison_next_action_execution_status_invariants(
        payload,
        errors,
        prefix,
    )


def validate_official_comparison_next_action_task_execution_status(status, errors, prefix):
    if not isinstance(status, dict):
        errors.append(f"{prefix} must be an object")
        return
    require_fields(
        errors,
        status,
        [
            "task_id",
            "category",
            "status",
            "runnable_command_count",
            "runnable_commands",
            "evidence_needed",
            "prepared_artifact_paths",
            "blocking_reasons",
            "next_action",
        ],
        prefix,
    )
    status_value = status.get("status")
    if status_value not in OFFICIAL_COMPARISON_NEXT_ACTION_TASK_EXECUTION_STATUSES:
        errors.append(f"{prefix}.status is invalid: {status_value!r}")
    for name in ["task_id", "category", "next_action"]:
        require_non_empty_string(errors, status.get(name), f"{prefix}.{name}")
    require_non_negative_int(
        errors,
        status.get("runnable_command_count"),
        f"{prefix}.runnable_command_count",
    )
    for name in [
        "runnable_commands",
        "evidence_needed",
        "prepared_artifact_paths",
        "blocking_reasons",
    ]:
        require_string_list(errors, status.get(name), f"{prefix}.{name}")
    if isinstance(status.get("runnable_commands"), list):
        if status.get("runnable_command_count") != len(status["runnable_commands"]):
            errors.append(f"{prefix}.runnable_command_count must equal runnable_commands length")
    if status_value == "ready_to_execute" and int_or_zero(status.get("runnable_command_count")) <= 0:
        errors.append(f"{prefix}.ready_to_execute requires runnable_command_count>0")
    if status_value in {
        "waiting_for_manual_input",
        "waiting_for_target_reference",
        "waiting_for_real_run",
    } and not status.get("blocking_reasons"):
        errors.append(f"{prefix}.{status_value} requires blocking_reasons")


def enforce_official_comparison_next_action_execution_status_invariants(payload, errors, prefix):
    task_statuses = payload.get("task_statuses") or []
    if isinstance(task_statuses, list):
        task_count = len(task_statuses)
        ready_count = sum(
            1 for status in task_statuses
            if isinstance(status, dict) and status.get("status") == "ready_to_execute"
        )
        blocked_count = sum(
            1 for status in task_statuses
            if isinstance(status, dict)
            and status.get("status") in {
                "waiting_for_manual_input",
                "waiting_for_target_reference",
                "waiting_for_real_run",
            }
        )
        command_count = sum(
            int_or_zero(status.get("runnable_command_count"))
            for status in task_statuses
            if isinstance(status, dict)
        )
        if payload.get("task_status_count") != task_count:
            errors.append(f"{prefix}.task_status_count must equal task_statuses length")
        if payload.get("ready_task_count") != ready_count:
            errors.append(f"{prefix}.ready_task_count must equal ready_to_execute task count")
        if payload.get("blocked_task_count") != blocked_count:
            errors.append(f"{prefix}.blocked_task_count must equal waiting task count")
        if payload.get("total_runnable_command_count") != command_count:
            errors.append(f"{prefix}.total_runnable_command_count must equal task runnable command sum")
    execution_state = payload.get("execution_state")
    if execution_state == "ready_to_execute" and int_or_zero(payload.get("ready_task_count")) <= 0:
        errors.append(f"{prefix}.ready_to_execute requires ready_task_count>0")
    if execution_state == "blocked_waiting_for_evidence" and int_or_zero(payload.get("blocked_task_count")) <= 0:
        errors.append(f"{prefix}.blocked_waiting_for_evidence requires blocked_task_count>0")
    if execution_state == "no_action_needed":
        if int_or_zero(payload.get("ready_task_count")) or int_or_zero(payload.get("blocked_task_count")):
            errors.append(f"{prefix}.no_action_needed requires ready_task_count=0 and blocked_task_count=0")


def validate_official_comparison_operator_handoff_report(payload, errors, prefix):
    require_fields(
        errors,
        payload,
        [
            "handoff_state",
            "workflow_report_path",
            "artifact_prep_report_path",
            "execution_status_report_path",
            "workflow_state",
            "eligible_for_official_comparison",
            "reference_version",
            "item_count",
            "ready_item_count",
            "blocked_item_count",
            "handoff_items",
            "next_actions",
            "evidence_paths",
            "markdown_report_path",
            "html_report_path",
        ],
        prefix,
    )
    handoff_state = payload.get("handoff_state")
    if handoff_state not in OFFICIAL_COMPARISON_OPERATOR_HANDOFF_STATES:
        errors.append(f"{prefix}.handoff_state is invalid: {handoff_state!r}")
    if payload.get("workflow_state") not in OFFICIAL_COMPARISON_PREFLIGHT_WORKFLOW_STATES:
        errors.append(f"{prefix}.workflow_state is invalid: {payload.get('workflow_state')!r}")
    require_type(
        errors,
        payload.get("eligible_for_official_comparison"),
        bool,
        f"{prefix}.eligible_for_official_comparison",
    )
    for name in [
        "workflow_report_path",
        "artifact_prep_report_path",
        "execution_status_report_path",
        "reference_version",
        "markdown_report_path",
        "html_report_path",
    ]:
        require_non_empty_string(errors, payload.get(name), f"{prefix}.{name}")
    for name in ["item_count", "ready_item_count", "blocked_item_count"]:
        require_non_negative_int(errors, payload.get(name), f"{prefix}.{name}")
    for name in ["next_actions", "evidence_paths"]:
        require_string_list(errors, payload.get(name), f"{prefix}.{name}")
    require_type(errors, payload.get("handoff_items"), list, f"{prefix}.handoff_items")
    if isinstance(payload.get("handoff_items"), list):
        for index, item in enumerate(payload["handoff_items"]):
            validate_official_comparison_operator_handoff_item(
                item,
                errors,
                f"{prefix}.handoff_items[{index}]",
            )
    enforce_official_comparison_operator_handoff_invariants(payload, errors, prefix)


def validate_official_comparison_operator_handoff_item(item, errors, prefix):
    if not isinstance(item, dict):
        errors.append(f"{prefix} must be an object")
        return
    require_fields(
        errors,
        item,
        [
            "item_id",
            "task_id",
            "category",
            "execution_status",
            "title",
            "operator_action",
            "evidence_to_return",
            "source_paths",
            "blocking_reasons",
        ],
        prefix,
    )
    if item.get("execution_status") not in OFFICIAL_COMPARISON_NEXT_ACTION_TASK_EXECUTION_STATUSES:
        errors.append(f"{prefix}.execution_status is invalid: {item.get('execution_status')!r}")
    for name in ["item_id", "task_id", "category", "title", "operator_action"]:
        require_non_empty_string(errors, item.get(name), f"{prefix}.{name}")
    for name in ["evidence_to_return", "source_paths", "blocking_reasons"]:
        require_string_list(errors, item.get(name), f"{prefix}.{name}")
    if item.get("execution_status") in {
        "waiting_for_manual_input",
        "waiting_for_target_reference",
        "waiting_for_real_run",
    } and not item.get("blocking_reasons"):
        errors.append(f"{prefix}.{item.get('execution_status')} requires blocking_reasons")


def enforce_official_comparison_operator_handoff_invariants(payload, errors, prefix):
    handoff_items = payload.get("handoff_items") or []
    if isinstance(handoff_items, list):
        item_count = len(handoff_items)
        ready_count = sum(
            1 for item in handoff_items
            if isinstance(item, dict) and item.get("execution_status") == "ready_to_execute"
        )
        blocked_count = sum(
            1 for item in handoff_items
            if isinstance(item, dict)
            and item.get("execution_status") in {
                "waiting_for_manual_input",
                "waiting_for_target_reference",
                "waiting_for_real_run",
            }
        )
        if payload.get("item_count") != item_count:
            errors.append(f"{prefix}.item_count must equal handoff_items length")
        if payload.get("ready_item_count") != ready_count:
            errors.append(f"{prefix}.ready_item_count must equal ready_to_execute item count")
        if payload.get("blocked_item_count") != blocked_count:
            errors.append(f"{prefix}.blocked_item_count must equal waiting item count")
    handoff_state = payload.get("handoff_state")
    if handoff_state == "ready_for_operator" and int_or_zero(payload.get("ready_item_count")) <= 0:
        errors.append(f"{prefix}.ready_for_operator requires ready_item_count>0")
    if handoff_state == "blocked_waiting_for_operator_evidence" and int_or_zero(payload.get("blocked_item_count")) <= 0:
        errors.append(f"{prefix}.blocked_waiting_for_operator_evidence requires blocked_item_count>0")
    if handoff_state == "no_handoff_needed":
        if int_or_zero(payload.get("ready_item_count")) or int_or_zero(payload.get("blocked_item_count")):
            errors.append(f"{prefix}.no_handoff_needed requires ready_item_count=0 and blocked_item_count=0")


def validate_official_comparison_operator_evidence_intake_report(payload, errors, prefix):
    require_fields(
        errors,
        payload,
        [
            "intake_state",
            "handoff_report_path",
            "target_reference_version",
            "ready_to_rerun_preflight",
            "item_count",
            "accepted_item_count",
            "missing_item_count",
            "rejected_item_count",
            "items",
            "reference_review_workflow_report_path",
            "run_bundle_manifest_paths",
            "next_actions",
            "evidence_paths",
            "markdown_report_path",
            "html_report_path",
        ],
        prefix,
    )
    intake_state = payload.get("intake_state")
    if intake_state not in OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_INTAKE_STATES:
        errors.append(f"{prefix}.intake_state is invalid: {intake_state!r}")
    require_type(
        errors,
        payload.get("ready_to_rerun_preflight"),
        bool,
        f"{prefix}.ready_to_rerun_preflight",
    )
    for name in [
        "handoff_report_path",
        "target_reference_version",
        "markdown_report_path",
        "html_report_path",
    ]:
        require_non_empty_string(errors, payload.get(name), f"{prefix}.{name}")
    for name in [
        "item_count",
        "accepted_item_count",
        "missing_item_count",
        "rejected_item_count",
    ]:
        require_non_negative_int(errors, payload.get(name), f"{prefix}.{name}")
    for name in ["run_bundle_manifest_paths", "next_actions", "evidence_paths"]:
        require_string_list(errors, payload.get(name), f"{prefix}.{name}")
    if payload.get("reference_review_workflow_report_path") is not None:
        require_type(
            errors,
            payload.get("reference_review_workflow_report_path"),
            str,
            f"{prefix}.reference_review_workflow_report_path",
        )
    require_type(errors, payload.get("items"), list, f"{prefix}.items")
    if isinstance(payload.get("items"), list):
        for index, item in enumerate(payload["items"]):
            validate_official_comparison_operator_evidence_intake_item(
                item,
                errors,
                f"{prefix}.items[{index}]",
            )
    enforce_official_comparison_operator_evidence_intake_invariants(payload, errors, prefix)


def validate_official_comparison_operator_evidence_intake_item(item, errors, prefix):
    if not isinstance(item, dict):
        errors.append(f"{prefix} must be an object")
        return
    require_fields(
        errors,
        item,
        [
            "task_id",
            "state",
            "evidence_paths",
            "reasons",
            "next_action",
        ],
        prefix,
    )
    if item.get("state") not in OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_ITEM_STATES:
        errors.append(f"{prefix}.state is invalid: {item.get('state')!r}")
    for name in ["task_id", "next_action"]:
        require_non_empty_string(errors, item.get(name), f"{prefix}.{name}")
    for name in ["evidence_paths", "reasons"]:
        require_string_list(errors, item.get(name), f"{prefix}.{name}")
    if item.get("state") in {"missing", "rejected"} and not item.get("reasons"):
        errors.append(f"{prefix}.{item.get('state')} requires reasons")


def enforce_official_comparison_operator_evidence_intake_invariants(payload, errors, prefix):
    items = payload.get("items") or []
    if isinstance(items, list):
        item_count = len(items)
        accepted_count = sum(
            1 for item in items
            if isinstance(item, dict) and item.get("state") == "accepted"
        )
        missing_count = sum(
            1 for item in items
            if isinstance(item, dict) and item.get("state") == "missing"
        )
        rejected_count = sum(
            1 for item in items
            if isinstance(item, dict) and item.get("state") == "rejected"
        )
        not_needed_count = sum(
            1 for item in items
            if isinstance(item, dict) and item.get("state") == "not_needed"
        )
        if payload.get("item_count") != item_count:
            errors.append(f"{prefix}.item_count must equal items length")
        if payload.get("accepted_item_count") != accepted_count:
            errors.append(f"{prefix}.accepted_item_count must equal accepted items")
        if payload.get("missing_item_count") != missing_count:
            errors.append(f"{prefix}.missing_item_count must equal missing items")
        if payload.get("rejected_item_count") != rejected_count:
            errors.append(f"{prefix}.rejected_item_count must equal rejected items")
        if accepted_count + missing_count + rejected_count + not_needed_count != item_count:
            errors.append(f"{prefix}.item states must account for every item")
        if item_count:
            expected_ready = missing_count == 0 and rejected_count == 0
            if payload.get("ready_to_rerun_preflight") is not expected_ready:
                errors.append(
                    f"{prefix}.ready_to_rerun_preflight must reflect accepted/not_needed items only"
                )
    intake_state = payload.get("intake_state")
    ready = payload.get("ready_to_rerun_preflight")
    if intake_state == "ready_to_rerun_preflight" and ready is not True:
        errors.append(f"{prefix}.ready_to_rerun_preflight state requires ready_to_rerun_preflight=true")
    if intake_state == "ready_to_rerun_preflight":
        if int_or_zero(payload.get("item_count")) <= 0:
            errors.append(f"{prefix}.ready_to_rerun_preflight state requires item_count>0")
        if int_or_zero(payload.get("missing_item_count")) or int_or_zero(payload.get("rejected_item_count")):
            errors.append(f"{prefix}.ready_to_rerun_preflight state requires no missing or rejected items")
    if intake_state == "blocked_missing_operator_evidence" and ready is not False:
        errors.append(f"{prefix}.blocked_missing_operator_evidence requires ready_to_rerun_preflight=false")
    if intake_state == "blocked_missing_operator_evidence":
        if not int_or_zero(payload.get("missing_item_count")) and not int_or_zero(payload.get("rejected_item_count")):
            errors.append(f"{prefix}.blocked_missing_operator_evidence requires missing or rejected items")
    if intake_state == "no_handoff_needed":
        if int_or_zero(payload.get("item_count")):
            errors.append(f"{prefix}.no_handoff_needed requires item_count=0")


def validate_official_comparison_operator_evidence_request_report(payload, errors, prefix):
    require_fields(
        errors,
        payload,
        [
            "request_state",
            "release_workflow_report_path",
            "preflight_workflow_report_path",
            "decision_workflow_report_path",
            "workflow_state",
            "release_state",
            "target_reference_version",
            "operator_handoff_report_path",
            "operator_evidence_intake_report_path",
            "task_count",
            "requested_task_count",
            "requests",
            "global_return_fields",
            "task_return_requirements",
            "return_field_requirements",
            "return_template_path",
            "return_template_fill_command_template_path",
            "return_workflow_command_template_path",
            "intake_command_template_path",
            "release_workflow_command_template_path",
            "command_template_paths",
            "next_actions",
            "evidence_paths",
            "markdown_report_path",
            "html_report_path",
            "return_guide_markdown_path",
            "return_guide_html_path",
        ],
        prefix,
    )
    request_state = payload.get("request_state")
    if request_state not in OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_REQUEST_STATES:
        errors.append(f"{prefix}.request_state is invalid: {request_state!r}")
    if payload.get("workflow_state") not in OFFICIAL_RELEASE_WORKFLOW_STATES:
        errors.append(f"{prefix}.workflow_state is invalid: {payload.get('workflow_state')!r}")
    if payload.get("release_state") not in OFFICIAL_COMPARISON_RELEASE_GATE_STATES:
        errors.append(f"{prefix}.release_state is invalid: {payload.get('release_state')!r}")
    for name in [
        "release_workflow_report_path",
        "preflight_workflow_report_path",
        "decision_workflow_report_path",
        "target_reference_version",
        "operator_handoff_report_path",
        "operator_evidence_intake_report_path",
        "return_template_path",
        "return_template_fill_command_template_path",
        "return_workflow_command_template_path",
        "intake_command_template_path",
        "release_workflow_command_template_path",
        "markdown_report_path",
        "html_report_path",
        "return_guide_markdown_path",
        "return_guide_html_path",
    ]:
        require_non_empty_string(errors, payload.get(name), f"{prefix}.{name}")
    if "release_artifact_audit_report_path" in payload:
        require_type(
            errors,
            payload.get("release_artifact_audit_report_path"),
            str,
            f"{prefix}.release_artifact_audit_report_path",
        )
    for name in ["task_count", "requested_task_count"]:
        require_non_negative_int(errors, payload.get(name), f"{prefix}.{name}")
    for name in [
        "global_return_fields",
        "command_template_paths",
        "next_actions",
        "evidence_paths",
    ]:
        require_string_list(errors, payload.get(name), f"{prefix}.{name}")
    if isinstance(payload.get("command_template_paths"), list):
        for name in [
            "return_template_fill_command_template_path",
            "return_workflow_command_template_path",
            "intake_command_template_path",
            "release_workflow_command_template_path",
        ]:
            if payload.get(name) not in payload["command_template_paths"]:
                errors.append(f"{prefix}.command_template_paths must include {name}")
    require_type(errors, payload.get("requests"), list, f"{prefix}.requests")
    if isinstance(payload.get("requests"), list):
        for index, item in enumerate(payload["requests"]):
            validate_official_comparison_operator_evidence_request_item(
                item,
                errors,
                f"{prefix}.requests[{index}]",
            )
    require_type(
        errors,
        payload.get("task_return_requirements"),
        list,
        f"{prefix}.task_return_requirements",
    )
    if isinstance(payload.get("task_return_requirements"), list):
        for index, item in enumerate(payload["task_return_requirements"]):
            validate_official_comparison_operator_evidence_return_requirement(
                item,
                errors,
                f"{prefix}.task_return_requirements[{index}]",
            )
    require_type(
        errors,
        payload.get("return_field_requirements"),
        list,
        f"{prefix}.return_field_requirements",
    )
    if isinstance(payload.get("return_field_requirements"), list):
        for index, item in enumerate(payload["return_field_requirements"]):
            validate_official_comparison_operator_evidence_request_field_requirement(
                item,
                errors,
                f"{prefix}.return_field_requirements[{index}]",
            )
    enforce_official_comparison_operator_evidence_request_invariants(
        payload,
        errors,
        prefix,
    )


def validate_official_comparison_operator_evidence_request_item(item, errors, prefix):
    if not isinstance(item, dict):
        errors.append(f"{prefix} must be an object")
        return
    require_fields(
        errors,
        item,
        [
            "task_id",
            "title",
            "request_state",
            "execution_status",
            "evidence_state",
            "adoption_item_ids",
            "operator_action",
            "next_action",
            "reasons",
            "evidence_to_return",
            "acceptance_criteria",
            "return_fields",
            "source_paths",
            "evidence_paths",
            "command_template_paths",
        ],
        prefix,
    )
    if item.get("request_state") not in (
        OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_REQUEST_ITEM_STATES
    ):
        errors.append(f"{prefix}.request_state is invalid: {item.get('request_state')!r}")
    if item.get("execution_status") not in OFFICIAL_COMPARISON_NEXT_ACTION_TASK_EXECUTION_STATUSES:
        errors.append(f"{prefix}.execution_status is invalid: {item.get('execution_status')!r}")
    if item.get("evidence_state") not in OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_ITEM_STATES:
        errors.append(f"{prefix}.evidence_state is invalid: {item.get('evidence_state')!r}")
    for name in ["task_id", "title", "operator_action", "next_action"]:
        require_non_empty_string(errors, item.get(name), f"{prefix}.{name}")
    for name in [
        "reasons",
        "adoption_item_ids",
        "evidence_to_return",
        "acceptance_criteria",
        "return_fields",
        "source_paths",
        "evidence_paths",
        "command_template_paths",
    ]:
        require_string_list(errors, item.get(name), f"{prefix}.{name}")
    if item.get("request_state") == "requested" and not item.get("return_fields"):
        errors.append(f"{prefix}.requested requires return_fields")
    if item.get("request_state") == "requested" and not item.get("acceptance_criteria"):
        errors.append(f"{prefix}.requested requires acceptance_criteria")


def validate_official_comparison_operator_evidence_request_field_requirement(item, errors, prefix):
    if not isinstance(item, dict):
        errors.append(f"{prefix} must be an object")
        return
    require_fields(
        errors,
        item,
        [
            "field",
            "task_ids",
            "requested_task_ids",
            "source_paths",
            "adoption_item_ids",
            "evidence_to_return",
            "acceptance_criteria",
            "next_actions",
            "command_template_paths",
        ],
        prefix,
    )
    require_non_empty_string(errors, item.get("field"), f"{prefix}.field")
    if "value_type" in item:
        require_non_empty_string(errors, item.get("value_type"), f"{prefix}.value_type")
        if item.get("value_type") not in {"path", "path_list", "string"}:
            errors.append(f"{prefix}.value_type is invalid: {item.get('value_type')!r}")
    if "allow_multiple" in item:
        require_type(errors, item.get("allow_multiple"), bool, f"{prefix}.allow_multiple")
    if "expected_manifest_types" in item:
        require_string_list(
            errors,
            item.get("expected_manifest_types"),
            f"{prefix}.expected_manifest_types",
        )
    if "expected_value" in item:
        require_type(errors, item.get("expected_value"), str, f"{prefix}.expected_value")
    if "resolved_expected_value" in item:
        require_type(
            errors,
            item.get("resolved_expected_value"),
            str,
            f"{prefix}.resolved_expected_value",
        )
    for name in [
        "task_ids",
        "requested_task_ids",
        "source_paths",
        "adoption_item_ids",
        "evidence_to_return",
        "acceptance_criteria",
        "next_actions",
        "command_template_paths",
    ]:
        require_string_list(errors, item.get(name), f"{prefix}.{name}")
    if not item.get("task_ids"):
        errors.append(f"{prefix}.task_ids must not be empty")
    if not item.get("requested_task_ids"):
        errors.append(f"{prefix}.requested_task_ids must not be empty")
    if item.get("task_ids") and item.get("requested_task_ids"):
        if not set(item["requested_task_ids"]).issubset(set(item["task_ids"])):
            errors.append(f"{prefix}.requested_task_ids must be a subset of task_ids")
    if not item.get("evidence_to_return"):
        errors.append(f"{prefix}.requested field requires evidence_to_return")
    if not item.get("acceptance_criteria"):
        errors.append(f"{prefix}.requested field requires acceptance_criteria")


def enforce_official_comparison_operator_evidence_request_invariants(payload, errors, prefix):
    requests = payload.get("requests") or []
    if isinstance(requests, list):
        task_count = len(requests)
        requested_count = sum(
            1 for item in requests
            if isinstance(item, dict) and item.get("request_state") == "requested"
        )
        if payload.get("task_count") != task_count:
            errors.append(f"{prefix}.task_count must equal requests length")
        if payload.get("requested_task_count") != requested_count:
            errors.append(f"{prefix}.requested_task_count must equal requested items")
    request_state = payload.get("request_state")
    requested_count = int_or_zero(payload.get("requested_task_count"))
    task_count = int_or_zero(payload.get("task_count"))
    if request_state == "needs_operator_evidence":
        if requested_count <= 0:
            errors.append(f"{prefix}.needs_operator_evidence requires requested_task_count>0")
    if request_state == "operator_evidence_already_accepted":
        if task_count <= 0:
            errors.append(f"{prefix}.operator_evidence_already_accepted requires task_count>0")
        if requested_count:
            errors.append(
                f"{prefix}.operator_evidence_already_accepted requires requested_task_count=0"
            )
    if request_state == "no_operator_evidence_needed" and requested_count:
        errors.append(f"{prefix}.no_operator_evidence_needed requires requested_task_count=0")
    field_requirements = payload.get("return_field_requirements") or []
    task_requirements = payload.get("task_return_requirements") or []
    if isinstance(requests, list) and isinstance(field_requirements, list):
        expected_tasks = {}
        expected_adoption_items = {}
        for item in requests:
            if not isinstance(item, dict) or item.get("request_state") != "requested":
                continue
            for path in payload.get("command_template_paths", []):
                if path not in item.get("command_template_paths", []):
                    errors.append(
                        f"{prefix}.requests command_template_paths must include top-level command paths"
                    )
                    break
            task_id = item.get("task_id", "")
            for field in item.get("return_fields", []):
                expected_tasks.setdefault(field, set()).add(task_id)
                expected_adoption_items.setdefault(field, set()).update(
                    item.get("adoption_item_ids", [])
                )
        actual_tasks = {}
        actual_adoption_items = {}
        for item in field_requirements:
            if not isinstance(item, dict):
                continue
            field = item.get("field", "")
            actual_tasks[field] = set(item.get("task_ids", []))
            actual_adoption_items[field] = set(item.get("adoption_item_ids", []))
        if actual_tasks != expected_tasks:
            errors.append(
                f"{prefix}.return_field_requirements must match requested request return_fields"
            )
        if actual_adoption_items != expected_adoption_items:
            errors.append(
                f"{prefix}.return_field_requirements adoption_item_ids must match requested requests"
            )
    if isinstance(requests, list) and isinstance(task_requirements, list):
        expected_by_task = {}
        for item in requests:
            if not isinstance(item, dict) or item.get("request_state") != "requested":
                continue
            expected_by_task[item.get("task_id", "")] = {
                "return_fields": set(item.get("return_fields", [])),
                "adoption_item_ids": set(item.get("adoption_item_ids", [])),
                "acceptance_criteria": set(item.get("acceptance_criteria", [])),
            }
        actual_by_task = {}
        for item in task_requirements:
            if not isinstance(item, dict) or item.get("request_state") != "requested":
                continue
            actual_by_task[item.get("task_id", "")] = {
                "return_fields": set(item.get("return_fields", [])),
                "adoption_item_ids": set(item.get("adoption_item_ids", [])),
                "acceptance_criteria": set(item.get("acceptance_criteria", [])),
            }
        if actual_by_task != expected_by_task:
            errors.append(
                f"{prefix}.task_return_requirements must match requested requests"
            )


def validate_official_comparison_operator_evidence_return_template(payload, errors, prefix):
    require_fields(
        errors,
        payload,
        [
            "template_type",
            "request_report_path",
            "target_reference_version",
            "return_template_fill_command_template_path",
            "return_workflow_command_template_path",
            "intake_command_template_path",
            "release_workflow_command_template_path",
            "command_template_paths",
            "reference_review_workflow_report_path",
            "run_bundle_manifest_paths",
            "return_field_requirements",
            "notes",
        ],
        prefix,
    )
    if payload.get("template_type") != "official_comparison_operator_evidence_return_template":
        errors.append(
            f"{prefix}.template_type must be official_comparison_operator_evidence_return_template"
        )
    require_non_negative_int(errors, payload.get("schema_version"), f"{prefix}.schema_version")
    for name in [
        "request_report_path",
        "target_reference_version",
        "return_template_fill_command_template_path",
        "return_workflow_command_template_path",
        "intake_command_template_path",
        "release_workflow_command_template_path",
    ]:
        require_non_empty_string(errors, payload.get(name), f"{prefix}.{name}")
    require_type(
        errors,
        payload.get("reference_review_workflow_report_path"),
        str,
        f"{prefix}.reference_review_workflow_report_path",
    )
    for name in ["command_template_paths", "run_bundle_manifest_paths", "notes"]:
        require_string_list(errors, payload.get(name), f"{prefix}.{name}")
    if isinstance(payload.get("command_template_paths"), list):
        for name in [
            "return_template_fill_command_template_path",
            "return_workflow_command_template_path",
            "intake_command_template_path",
            "release_workflow_command_template_path",
        ]:
            if payload.get(name) not in payload["command_template_paths"]:
                errors.append(f"{prefix}.command_template_paths must include {name}")
    require_type(
        errors,
        payload.get("return_field_requirements"),
        list,
        f"{prefix}.return_field_requirements",
    )
    if isinstance(payload.get("return_field_requirements"), list):
        for index, item in enumerate(payload["return_field_requirements"]):
            validate_official_comparison_operator_evidence_request_field_requirement(
                item,
                errors,
                f"{prefix}.return_field_requirements[{index}]",
            )
    if "task_return_requirements" in payload:
        require_type(
            errors,
            payload.get("task_return_requirements"),
            list,
            f"{prefix}.task_return_requirements",
        )
        if isinstance(payload.get("task_return_requirements"), list):
            for index, item in enumerate(payload["task_return_requirements"]):
                validate_official_comparison_operator_evidence_return_requirement(
                    item,
                    errors,
                    f"{prefix}.task_return_requirements[{index}]",
                )
    if "submission_slot_values" in payload:
        require_type(
            errors,
            payload.get("submission_slot_values"),
            list,
            f"{prefix}.submission_slot_values",
        )
        if isinstance(payload.get("submission_slot_values"), list):
            for index, item in enumerate(payload["submission_slot_values"]):
                validate_official_comparison_operator_evidence_return_template_slot_value(
                    item,
                    errors,
                    f"{prefix}.submission_slot_values[{index}]",
                )
    if "submission_slot_autofill_diagnostics" in payload:
        require_type(
            errors,
            payload.get("submission_slot_autofill_diagnostics"),
            list,
            f"{prefix}.submission_slot_autofill_diagnostics",
        )
        if isinstance(payload.get("submission_slot_autofill_diagnostics"), list):
            for index, item in enumerate(
                payload["submission_slot_autofill_diagnostics"]
            ):
                validate_official_comparison_operator_evidence_autofill_diagnostic(
                    item,
                    errors,
                    f"{prefix}.submission_slot_autofill_diagnostics[{index}]",
                )
    enforce_official_comparison_operator_evidence_return_template_invariants(
        payload,
        errors,
        prefix,
    )


def validate_official_comparison_operator_evidence_return_template_slot_value(
    item,
    errors,
    prefix,
):
    if not isinstance(item, dict):
        errors.append(f"{prefix} must be an object")
        return
    require_fields(errors, item, ["slot_id", "return_field", "path"], prefix)
    for name in ["slot_id", "return_field", "path"]:
        require_non_empty_string(errors, item.get(name), f"{prefix}.{name}")
    if item.get("return_field") not in {
        "reference_review_workflow_report_path",
        "run_bundle_manifest_paths",
    }:
        errors.append(f"{prefix}.return_field is invalid: {item.get('return_field')!r}")


def validate_official_comparison_operator_evidence_autofill_diagnostic(
    item,
    errors,
    prefix,
):
    if not isinstance(item, dict):
        errors.append(f"{prefix} must be an object")
        return
    require_fields(
        errors,
        item,
        [
            "slot_id",
            "return_field",
            "expected_submission_path",
            "autofill_state",
            "reason",
        ],
        prefix,
    )
    for name in [
        "slot_id",
        "return_field",
        "expected_submission_path",
        "autofill_state",
        "reason",
    ]:
        require_non_empty_string(errors, item.get(name), f"{prefix}.{name}")
    if item.get("return_field") not in {
        "reference_review_workflow_report_path",
        "run_bundle_manifest_paths",
    }:
        errors.append(f"{prefix}.return_field is invalid: {item.get('return_field')!r}")
    if item.get("autofill_state") not in {
        "skipped_invalid_expected_submission_path",
    }:
        errors.append(
            f"{prefix}.autofill_state is invalid: {item.get('autofill_state')!r}"
        )


def enforce_official_comparison_operator_evidence_submission_slot_value_uniqueness(
    slot_values,
    errors,
    prefix,
):
    seen_slot_ids = set()
    for index, item in enumerate(slot_values):
        if not isinstance(item, dict):
            continue
        slot_id = item.get("slot_id")
        if not isinstance(slot_id, str) or not slot_id:
            continue
        if slot_id in seen_slot_ids:
            errors.append(
                f"{prefix}[{index}].slot_id must be unique: {slot_id}"
            )
        seen_slot_ids.add(slot_id)


def enforce_official_release_submission_slot_id_partition(payload, errors, prefix):
    state_id_fields = [
        "operator_evidence_submitted_submission_slot_ids",
        "operator_evidence_missing_submission_slot_ids",
        "operator_evidence_rejected_submission_slot_ids",
        "operator_evidence_not_needed_submission_slot_ids",
    ]
    id_sets = {}
    for field in state_id_fields:
        values = payload.get(field)
        if not isinstance(values, list):
            continue
        seen_ids = set()
        id_set = set()
        for slot_id in values:
            if not isinstance(slot_id, str) or not slot_id:
                continue
            if slot_id in seen_ids:
                errors.append(
                    f"{prefix}.{field} must contain unique slot ids: {slot_id}"
                )
            seen_ids.add(slot_id)
            id_set.add(slot_id)
        id_sets[field] = id_set
    if len(id_sets) != len(state_id_fields):
        return
    state_by_slot_id = {}
    overlapping_slot_ids = []
    for field, slot_ids in id_sets.items():
        for slot_id in slot_ids:
            if slot_id in state_by_slot_id:
                overlapping_slot_ids.append(slot_id)
                continue
            state_by_slot_id[slot_id] = field
    for slot_id in sorted(set(overlapping_slot_ids)):
        errors.append(
            f"{prefix}.operator_evidence_submission_slot_ids must be disjoint "
            f"across states: {slot_id}"
        )
    if isinstance(payload.get("operator_evidence_submission_slot_count"), int):
        covered_slot_ids = set().union(*id_sets.values())
        if payload.get("operator_evidence_submission_slot_count") != len(
            covered_slot_ids
        ):
            errors.append(
                f"{prefix}.operator_evidence_submission_slot_ids must cover "
                "operator_evidence_submission_slot_count"
            )


def expected_official_release_submission_status_state(payload):
    slot_count = payload.get("operator_evidence_submission_slot_count")
    submitted_count = payload.get("operator_evidence_submitted_submission_slot_count")
    missing_count = payload.get("operator_evidence_missing_submission_slot_count")
    rejected_count = payload.get("operator_evidence_rejected_submission_slot_count")
    if not all(
        isinstance(value, int)
        for value in [slot_count, submitted_count, missing_count, rejected_count]
    ):
        return None
    if slot_count == 0:
        return "no_operator_evidence_needed"
    if rejected_count > 0:
        return "blocked_invalid_submissions"
    if missing_count == 0:
        return "all_slots_submitted"
    if submitted_count > 0:
        return "partially_submitted"
    return "waiting_for_submissions"


def official_release_rejected_submission_path_count(payload):
    blocking_slots = payload.get("operator_evidence_blocking_submission_slots")
    if not isinstance(blocking_slots, list):
        return int_or_zero(payload.get("operator_evidence_rejected_submission_slot_count"))
    return sum(
        1
        for item in blocking_slots
        if isinstance(item, dict)
        and item.get("slot_status") == "rejected"
        and isinstance(item.get("matched_evidence_paths"), list)
        and any(
            isinstance(path, str) and path.strip()
            for path in item.get("matched_evidence_paths", [])
        )
    )


def expected_official_operator_evidence_submission_fill_step_state(
    readiness_state,
):
    if readiness_state == "no_submission_values_needed":
        return "not_needed"
    if readiness_state == "ready_to_fill_return_template":
        return "open"
    return "blocked"


def enforce_official_comparison_operator_evidence_return_template_invariants(
    payload,
    errors,
    prefix,
):
    task_requirements = payload.get("task_return_requirements") or []
    field_requirements = payload.get("return_field_requirements") or []
    if isinstance(task_requirements, list) and isinstance(field_requirements, list):
        expected_tasks = {}
        expected_adoption_items = {}
        for item in task_requirements:
            if not isinstance(item, dict) or item.get("request_state") != "requested":
                continue
            task_id = item.get("task_id", "")
            for field in item.get("return_fields", []):
                expected_tasks.setdefault(field, set()).add(task_id)
                expected_adoption_items.setdefault(field, set()).update(
                    item.get("adoption_item_ids", [])
                )
        actual_tasks = {}
        actual_adoption_items = {}
        for item in field_requirements:
            if not isinstance(item, dict):
                continue
            field = item.get("field", "")
            actual_tasks[field] = set(item.get("task_ids", []))
            actual_adoption_items[field] = set(item.get("adoption_item_ids", []))
        if actual_tasks != expected_tasks:
            errors.append(
                f"{prefix}.return_field_requirements must match task_return_requirements return_fields"
            )
        if actual_adoption_items != expected_adoption_items:
            errors.append(
                f"{prefix}.return_field_requirements adoption_item_ids must match task_return_requirements"
            )
    slot_values = payload.get("submission_slot_values")
    if isinstance(slot_values, list):
        enforce_official_comparison_operator_evidence_submission_slot_value_uniqueness(
            slot_values,
            errors,
            f"{prefix}.submission_slot_values",
        )
        reference_slot_paths = [
            item.get("path")
            for item in slot_values
            if isinstance(item, dict)
            and item.get("return_field") == "reference_review_workflow_report_path"
        ]
        for path in reference_slot_paths:
            if path != payload.get("reference_review_workflow_report_path"):
                errors.append(
                    f"{prefix}.submission_slot_values reference path must match "
                    "reference_review_workflow_report_path"
                )
        run_bundle_paths = set(payload.get("run_bundle_manifest_paths", []))
        for item in slot_values:
            if not isinstance(item, dict):
                continue
            if item.get("return_field") != "run_bundle_manifest_paths":
                continue
            if item.get("path") not in run_bundle_paths:
                errors.append(
                    f"{prefix}.submission_slot_values run bundle path must be in "
                    "run_bundle_manifest_paths"
                )


def validate_official_comparison_operator_evidence_return_requirement(item, errors, prefix):
    if not isinstance(item, dict):
        errors.append(f"{prefix} must be an object")
        return
    require_fields(
        errors,
        item,
        [
            "task_id",
            "title",
            "request_state",
            "adoption_item_ids",
            "return_fields",
            "evidence_to_return",
            "acceptance_criteria",
            "reasons",
            "next_action",
            "source_paths",
            "command_template_paths",
        ],
        prefix,
    )
    for name in ["task_id", "title", "request_state", "next_action"]:
        require_non_empty_string(errors, item.get(name), f"{prefix}.{name}")
    for name in [
        "adoption_item_ids",
        "return_fields",
        "evidence_to_return",
        "acceptance_criteria",
        "reasons",
        "source_paths",
        "command_template_paths",
    ]:
        require_string_list(errors, item.get(name), f"{prefix}.{name}")
    if item.get("request_state") not in OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_REQUEST_ITEM_STATES:
        errors.append(f"{prefix}.request_state is invalid: {item.get('request_state')!r}")
    if item.get("request_state") == "requested":
        if not item.get("return_fields"):
            errors.append(f"{prefix}.requested item requires return_fields")
        if not item.get("evidence_to_return"):
            errors.append(f"{prefix}.requested item requires evidence_to_return")
        if not item.get("acceptance_criteria"):
            errors.append(f"{prefix}.requested item requires acceptance_criteria")


def validate_official_comparison_operator_evidence_return_workflow_report(payload, errors, prefix):
    require_fields(
        errors,
        payload,
        [
            "return_state",
            "return_template_path",
            "release_workflow_report_path",
            "operator_evidence_request_report_path",
            "operator_evidence_return_guide_markdown_path",
            "operator_evidence_return_guide_html_path",
            "return_workflow_command_template_path",
            "intake_command_template_path",
            "release_workflow_command_template_path",
            "command_template_paths",
            "target_reference_version",
            "reference_review_workflow_report_path",
            "run_bundle_manifest_paths",
            "operator_handoff_report_path",
            "operator_evidence_intake_report_path",
            "preflight_resume_plan_path",
            "operator_evidence_intake_state",
            "operator_evidence_ready_to_rerun_preflight",
            "operator_evidence_items",
            "operator_evidence_task_results",
            "return_field_statuses",
            "return_blocker_summary",
            "operator_evidence_accepted_item_count",
            "operator_evidence_missing_item_count",
            "operator_evidence_rejected_item_count",
            "preflight_resume_plan_state",
            "preflight_resume_ready_to_rerun",
            "preflight_rerun_command",
            "blocking_reasons",
            "next_actions",
            "evidence_paths",
            "markdown_report_path",
            "html_report_path",
        ],
        prefix,
    )
    return_state = payload.get("return_state")
    if return_state not in OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_RETURN_WORKFLOW_STATES:
        errors.append(f"{prefix}.return_state is invalid: {return_state!r}")
    if payload.get("operator_evidence_intake_state") not in (
        OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_INTAKE_STATES
    ):
        errors.append(
            f"{prefix}.operator_evidence_intake_state is invalid: "
            f"{payload.get('operator_evidence_intake_state')!r}"
        )
    if payload.get("preflight_resume_plan_state") not in (
        OFFICIAL_COMPARISON_PREFLIGHT_RESUME_PLAN_STATES
    ):
        errors.append(
            f"{prefix}.preflight_resume_plan_state is invalid: "
            f"{payload.get('preflight_resume_plan_state')!r}"
        )
    for name in [
        "return_template_path",
        "release_workflow_report_path",
        "operator_evidence_request_report_path",
        "operator_evidence_return_guide_markdown_path",
        "operator_evidence_return_guide_html_path",
        "target_reference_version",
        "operator_handoff_report_path",
        "operator_evidence_intake_report_path",
        "preflight_resume_plan_path",
        "markdown_report_path",
        "html_report_path",
    ]:
        require_non_empty_string(errors, payload.get(name), f"{prefix}.{name}")
    for name in [
        "return_template_fill_command_template_path",
        "return_workflow_command_template_path",
        "intake_command_template_path",
        "release_workflow_command_template_path",
    ]:
        require_type(errors, payload.get(name), str, f"{prefix}.{name}")
    if payload.get("reference_review_workflow_report_path") is not None:
        require_type(
            errors,
            payload.get("reference_review_workflow_report_path"),
            str,
            f"{prefix}.reference_review_workflow_report_path",
        )
    require_type(errors, payload.get("preflight_rerun_command"), str, f"{prefix}.preflight_rerun_command")
    for name in [
        "operator_evidence_ready_to_rerun_preflight",
        "preflight_resume_ready_to_rerun",
    ]:
        require_type(errors, payload.get(name), bool, f"{prefix}.{name}")
    for name in [
        "operator_evidence_accepted_item_count",
        "operator_evidence_missing_item_count",
        "operator_evidence_rejected_item_count",
    ]:
        require_non_negative_int(errors, payload.get(name), f"{prefix}.{name}")
    for name in [
        "run_bundle_manifest_paths",
        "command_template_paths",
        "blocking_reasons",
        "next_actions",
        "evidence_paths",
    ]:
        require_string_list(errors, payload.get(name), f"{prefix}.{name}")
    if isinstance(payload.get("command_template_paths"), list):
        for name in [
            "return_template_fill_command_template_path",
            "return_workflow_command_template_path",
            "intake_command_template_path",
            "release_workflow_command_template_path",
        ]:
            if payload.get(name) and payload.get(name) not in payload["command_template_paths"]:
                errors.append(f"{prefix}.command_template_paths must include {name}")
    require_type(
        errors,
        payload.get("operator_evidence_items"),
        list,
        f"{prefix}.operator_evidence_items",
    )
    if isinstance(payload.get("operator_evidence_items"), list):
        for index, item in enumerate(payload["operator_evidence_items"]):
            validate_official_comparison_operator_evidence_intake_item(
                item,
                errors,
                f"{prefix}.operator_evidence_items[{index}]",
            )
    require_type(
        errors,
        payload.get("operator_evidence_task_results"),
        list,
        f"{prefix}.operator_evidence_task_results",
    )
    if isinstance(payload.get("operator_evidence_task_results"), list):
        for index, item in enumerate(payload["operator_evidence_task_results"]):
            validate_official_comparison_operator_evidence_task_result(
                item,
                errors,
                f"{prefix}.operator_evidence_task_results[{index}]",
            )
    require_type(
        errors,
        payload.get("return_field_statuses"),
        list,
        f"{prefix}.return_field_statuses",
    )
    if isinstance(payload.get("return_field_statuses"), list):
        for index, item in enumerate(payload["return_field_statuses"]):
            validate_official_comparison_operator_evidence_return_field_status(
                item,
                errors,
                f"{prefix}.return_field_statuses[{index}]",
            )
    require_type(
        errors,
        payload.get("return_blocker_summary"),
        list,
        f"{prefix}.return_blocker_summary",
    )
    if isinstance(payload.get("return_blocker_summary"), list):
        for index, item in enumerate(payload["return_blocker_summary"]):
            validate_official_release_return_blocker_summary_item(
                item,
                errors,
                f"{prefix}.return_blocker_summary[{index}]",
            )
    if "submission_slot_values" in payload:
        require_type(
            errors,
            payload.get("submission_slot_values"),
            list,
            f"{prefix}.submission_slot_values",
        )
        if isinstance(payload.get("submission_slot_values"), list):
            for index, item in enumerate(payload["submission_slot_values"]):
                validate_official_comparison_operator_evidence_return_template_slot_value(
                    item,
                    errors,
                    f"{prefix}.submission_slot_values[{index}]",
                )
    enforce_official_comparison_operator_evidence_return_workflow_invariants(
        payload,
        errors,
        prefix,
    )


def validate_official_comparison_operator_evidence_execution_plan(payload, errors, prefix):
    require_fields(
        errors,
        payload,
        [
            "plan_state",
            "release_workflow_report_path",
            "workflow_state",
            "adoption_state",
            "target_reference_version",
            "operator_evidence_request_report_path",
            "operator_evidence_return_template_path",
            "operator_evidence_return_template_fill_command_template_path",
            "operator_evidence_return_workflow_command_template_path",
            "operator_evidence_release_workflow_command_template_path",
            "adoption_remediation_plan_path",
            "operator_task_count",
            "execution_step_count",
            "execution_step_state_counts",
            "open_execution_step_count",
            "blocked_execution_step_count",
            "completed_execution_step_count",
            "not_needed_execution_step_count",
            "open_execution_step_ids",
            "blocked_execution_step_ids",
            "next_open_execution_step_id",
            "next_open_execution_step_title",
            "next_open_execution_step_task_ids",
            "next_open_execution_step_return_fields",
            "next_open_execution_step_blocking_submission_slot_ids",
            "next_open_execution_step_blocking_submission_slot_details",
            "next_open_execution_step_source_artifact_hint_paths",
            "next_open_execution_step_command_template_paths",
            "next_open_execution_step_next_actions",
            "return_field_requirements",
            "operator_tasks",
            "execution_steps",
            "command_template_paths",
            "next_actions",
            "evidence_paths",
            "markdown_report_path",
            "html_report_path",
        ],
        prefix,
    )
    if payload.get("plan_state") not in (
        OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_EXECUTION_PLAN_STATES
    ):
        errors.append(f"{prefix}.plan_state is invalid: {payload.get('plan_state')!r}")
    if payload.get("workflow_state") not in OFFICIAL_RELEASE_WORKFLOW_STATES:
        errors.append(f"{prefix}.workflow_state is invalid: {payload.get('workflow_state')!r}")
    if payload.get("adoption_state") not in OFFICIAL_COMPARISON_ADOPTION_STATES:
        errors.append(f"{prefix}.adoption_state is invalid: {payload.get('adoption_state')!r}")
    for name in [
        "release_workflow_report_path",
        "target_reference_version",
        "markdown_report_path",
        "html_report_path",
    ]:
        require_non_empty_string(errors, payload.get(name), f"{prefix}.{name}")
    for name in [
        "operator_evidence_request_report_path",
        "operator_evidence_return_template_path",
        "operator_evidence_return_template_fill_command_template_path",
        "operator_evidence_return_workflow_command_template_path",
        "operator_evidence_release_workflow_command_template_path",
        "adoption_remediation_plan_path",
    ]:
        require_type(errors, payload.get(name), str, f"{prefix}.{name}")
    for name in [
        "operator_task_count",
        "execution_step_count",
        "open_execution_step_count",
        "blocked_execution_step_count",
        "completed_execution_step_count",
        "not_needed_execution_step_count",
    ]:
        require_non_negative_int(errors, payload.get(name), f"{prefix}.{name}")
    require_type(
        errors,
        payload.get("execution_step_state_counts"),
        dict,
        f"{prefix}.execution_step_state_counts",
    )
    if isinstance(payload.get("execution_step_state_counts"), dict):
        for state in OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_EXECUTION_STEP_STATES:
            require_non_negative_int(
                errors,
                payload["execution_step_state_counts"].get(state),
                f"{prefix}.execution_step_state_counts.{state}",
            )
    for name in [
        "command_template_paths",
        "next_actions",
        "evidence_paths",
        "open_execution_step_ids",
        "blocked_execution_step_ids",
    ]:
        require_string_list(errors, payload.get(name), f"{prefix}.{name}")
    require_type(
        errors,
        payload.get("next_open_execution_step_id"),
        str,
        f"{prefix}.next_open_execution_step_id",
    )
    require_type(
        errors,
        payload.get("next_open_execution_step_title"),
        str,
        f"{prefix}.next_open_execution_step_title",
    )
    for name in [
        "next_open_execution_step_task_ids",
        "next_open_execution_step_return_fields",
        "next_open_execution_step_blocking_submission_slot_ids",
        "next_open_execution_step_source_artifact_hint_paths",
        "next_open_execution_step_command_template_paths",
        "next_open_execution_step_next_actions",
    ]:
        require_string_list(errors, payload.get(name), f"{prefix}.{name}")
    require_type(
        errors,
        payload.get("next_open_execution_step_blocking_submission_slot_details"),
        list,
        f"{prefix}.next_open_execution_step_blocking_submission_slot_details",
    )
    if isinstance(
        payload.get("next_open_execution_step_blocking_submission_slot_details"),
        list,
    ):
        for index, item in enumerate(
            payload["next_open_execution_step_blocking_submission_slot_details"]
        ):
            validate_official_comparison_operator_evidence_blocking_slot_summary_item(
                item,
                errors,
                f"{prefix}.next_open_execution_step_blocking_submission_slot_details[{index}]",
            )
    require_type(errors, payload.get("operator_tasks"), list, f"{prefix}.operator_tasks")
    if isinstance(payload.get("operator_tasks"), list):
        for index, task in enumerate(payload["operator_tasks"]):
            validate_official_release_workflow_operator_task(
                task,
                errors,
                f"{prefix}.operator_tasks[{index}]",
            )
    require_type(
        errors,
        payload.get("return_field_requirements"),
        list,
        f"{prefix}.return_field_requirements",
    )
    if isinstance(payload.get("return_field_requirements"), list):
        for index, item in enumerate(payload["return_field_requirements"]):
            validate_official_comparison_operator_evidence_request_field_requirement(
                item,
                errors,
                f"{prefix}.return_field_requirements[{index}]",
            )
    require_type(errors, payload.get("execution_steps"), list, f"{prefix}.execution_steps")
    if isinstance(payload.get("execution_steps"), list):
        for index, step in enumerate(payload["execution_steps"]):
            validate_official_comparison_operator_evidence_execution_step(
                step,
                errors,
                f"{prefix}.execution_steps[{index}]",
            )
    enforce_official_comparison_operator_evidence_execution_plan_invariants(
        payload,
        errors,
        prefix,
    )


def validate_official_comparison_operator_evidence_execution_step(step, errors, prefix):
    if not isinstance(step, dict):
        errors.append(f"{prefix} must be an object")
        return
    require_fields(
        errors,
        step,
        [
            "step_id",
            "title",
            "step_state",
            "task_ids",
            "return_fields",
            "adoption_item_ids",
            "evidence_to_collect",
            "acceptance_criteria",
            "source_paths",
            "source_artifact_hint_paths",
            "command_template_paths",
            "next_actions",
            "submission_slot_count",
            "submitted_submission_slot_count",
            "missing_submission_slot_count",
            "rejected_submission_slot_count",
            "not_needed_submission_slot_count",
            "submission_slot_ids",
            "blocking_submission_slot_ids",
            "blocking_submission_slot_details",
        ],
        prefix,
    )
    for name in ["step_id", "title", "step_state"]:
        require_non_empty_string(errors, step.get(name), f"{prefix}.{name}")
    if step.get("step_state") not in (
        OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_EXECUTION_STEP_STATES
    ):
        errors.append(f"{prefix}.step_state is invalid: {step.get('step_state')!r}")
    for name in [
        "submission_slot_count",
        "submitted_submission_slot_count",
        "missing_submission_slot_count",
        "rejected_submission_slot_count",
        "not_needed_submission_slot_count",
    ]:
        require_non_negative_int(errors, step.get(name), f"{prefix}.{name}")
    for name in [
        "task_ids",
        "return_fields",
        "adoption_item_ids",
        "evidence_to_collect",
        "acceptance_criteria",
        "source_paths",
        "source_artifact_hint_paths",
        "command_template_paths",
        "next_actions",
        "submission_slot_ids",
        "blocking_submission_slot_ids",
    ]:
        require_string_list(errors, step.get(name), f"{prefix}.{name}")
    require_type(
        errors,
        step.get("blocking_submission_slot_details"),
        list,
        f"{prefix}.blocking_submission_slot_details",
    )
    if isinstance(step.get("blocking_submission_slot_details"), list):
        for index, item in enumerate(step["blocking_submission_slot_details"]):
            validate_official_comparison_operator_evidence_blocking_slot_summary_item(
                item,
                errors,
                f"{prefix}.blocking_submission_slot_details[{index}]",
            )
    count_total = (
        step.get("submitted_submission_slot_count", 0)
        + step.get("missing_submission_slot_count", 0)
        + step.get("rejected_submission_slot_count", 0)
        + step.get("not_needed_submission_slot_count", 0)
    )
    if (
        isinstance(step.get("submission_slot_count"), int)
        and all(
            isinstance(step.get(name), int)
            for name in [
                "submitted_submission_slot_count",
                "missing_submission_slot_count",
                "rejected_submission_slot_count",
                "not_needed_submission_slot_count",
            ]
        )
        and step.get("submission_slot_count") != count_total
    ):
        errors.append(f"{prefix}.submission slot counts must add up to submission_slot_count")
    if isinstance(step.get("submission_slot_ids"), list) and isinstance(
        step.get("blocking_submission_slot_ids"),
        list,
    ):
        slot_ids = set(step.get("submission_slot_ids", []))
        for slot_id in step.get("blocking_submission_slot_ids", []):
            if slot_id not in slot_ids:
                errors.append(
                    f"{prefix}.blocking_submission_slot_ids must be included in submission_slot_ids"
                )
                break
    if isinstance(step.get("blocking_submission_slot_details"), list) and isinstance(
        step.get("blocking_submission_slot_ids"),
        list,
    ):
        detail_ids = [
            item.get("slot_id")
            for item in step.get("blocking_submission_slot_details", [])
            if isinstance(item, dict)
        ]
        if detail_ids != step.get("blocking_submission_slot_ids", []):
            errors.append(
                f"{prefix}.blocking_submission_slot_details must match "
                "blocking_submission_slot_ids"
            )
    if step.get("step_state") == "open":
        if not step.get("task_ids"):
            errors.append(f"{prefix}.open step requires task_ids")
        if (
            step.get("step_id", "").startswith("collect_")
            and not step.get("evidence_to_collect")
        ):
            errors.append(f"{prefix}.collect step requires evidence_to_collect")
    expected_source_artifact_hints = (
        expected_official_comparison_operator_evidence_source_artifact_hint_paths(
            step
        )
    )
    if step.get("source_artifact_hint_paths") != expected_source_artifact_hints:
        errors.append(f"{prefix}.source_artifact_hint_paths must match source_paths")


def enforce_official_comparison_operator_evidence_execution_plan_invariants(
    payload,
    errors,
    prefix,
):
    tasks = payload.get("operator_tasks") or []
    steps = payload.get("execution_steps") or []
    if isinstance(tasks, list) and payload.get("operator_task_count") != len(tasks):
        errors.append(f"{prefix}.operator_task_count must equal operator_tasks length")
    if isinstance(steps, list) and payload.get("execution_step_count") != len(steps):
        errors.append(f"{prefix}.execution_step_count must equal execution_steps length")
    if isinstance(steps, list):
        state_counts = {
            state: 0
            for state in OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_EXECUTION_STEP_STATES
        }
        open_step_ids = []
        blocked_step_ids = []
        for step in steps:
            if not isinstance(step, dict):
                continue
            step_state = step.get("step_state", "")
            step_id = step.get("step_id", "")
            if step_state in state_counts:
                state_counts[step_state] += 1
            if step_state == "open":
                open_step_ids.append(step_id)
            if step_state == "blocked":
                blocked_step_ids.append(step_id)
        if payload.get("execution_step_state_counts") != state_counts:
            errors.append(
                f"{prefix}.execution_step_state_counts must match execution_steps"
            )
        for field, state in [
            ("open_execution_step_count", "open"),
            ("blocked_execution_step_count", "blocked"),
            ("completed_execution_step_count", "completed"),
            ("not_needed_execution_step_count", "not_needed"),
        ]:
            if payload.get(field) != state_counts[state]:
                errors.append(f"{prefix}.{field} must match execution_steps")
        if payload.get("open_execution_step_ids") != open_step_ids:
            errors.append(f"{prefix}.open_execution_step_ids must match execution_steps")
        if payload.get("blocked_execution_step_ids") != blocked_step_ids:
            errors.append(
                f"{prefix}.blocked_execution_step_ids must match execution_steps"
            )
        expected_next_open_step_id = open_step_ids[0] if open_step_ids else ""
        expected_next_open_step = next(
            (
                step
                for step in steps
                if isinstance(step, dict)
                and step.get("step_state") == "open"
            ),
            {},
        )
        if payload.get("next_open_execution_step_id") != expected_next_open_step_id:
            errors.append(
                f"{prefix}.next_open_execution_step_id must match execution_steps"
            )
        expected_next_open_fields = [
            ("next_open_execution_step_title", "title", ""),
            ("next_open_execution_step_task_ids", "task_ids", []),
            ("next_open_execution_step_return_fields", "return_fields", []),
            (
                "next_open_execution_step_blocking_submission_slot_ids",
                "blocking_submission_slot_ids",
                [],
            ),
            (
                "next_open_execution_step_blocking_submission_slot_details",
                "blocking_submission_slot_details",
                [],
            ),
            (
                "next_open_execution_step_source_artifact_hint_paths",
                "source_artifact_hint_paths",
                [],
            ),
            (
                "next_open_execution_step_command_template_paths",
                "command_template_paths",
                [],
            ),
            ("next_open_execution_step_next_actions", "next_actions", []),
        ]
        for plan_field, step_field, default in expected_next_open_fields:
            if payload.get(plan_field) != expected_next_open_step.get(
                step_field,
                default,
            ):
                errors.append(f"{prefix}.{plan_field} must match execution_steps")
        steps_by_id = {
            step.get("step_id"): step
            for step in steps
            if isinstance(step, dict)
        }
        open_collect_steps = [
            step
            for step in steps
            if isinstance(step, dict)
            and step.get("step_id", "").startswith("collect_")
            and step.get("step_state") == "open"
        ]
        collect_steps = [
            step
            for step in steps
            if isinstance(step, dict)
            and step.get("step_id", "").startswith("collect_")
        ]
        all_collect_steps_not_needed = (
            bool(collect_steps)
            and all(step.get("step_state") == "not_needed" for step in collect_steps)
        )
        fill_step = steps_by_id.get("fill_return_template")
        if (
            open_collect_steps
            and isinstance(fill_step, dict)
            and fill_step.get("step_state") != "blocked"
        ):
            errors.append(
                f"{prefix}.fill_return_template must be blocked while collect steps are open"
            )
        if (
            collect_steps
            and not open_collect_steps
            and not all_collect_steps_not_needed
            and isinstance(fill_step, dict)
            and fill_step.get("step_state") == "blocked"
        ):
            errors.append(
                f"{prefix}.fill_return_template must not be blocked after collect steps are complete"
            )
    if isinstance(steps, list) and isinstance(payload.get("command_template_paths"), list):
        command_paths = set(payload.get("command_template_paths", []))
        for step in steps:
            if not isinstance(step, dict):
                continue
            for path in step.get("command_template_paths", []):
                if path not in command_paths:
                    errors.append(
                        f"{prefix}.command_template_paths must include step command paths"
                    )
                    break


def validate_official_comparison_operator_evidence_submission_checklist(
    payload,
    errors,
    prefix,
):
    require_fields(
        errors,
        payload,
        [
            "checklist_state",
            "release_workflow_report_path",
            "operator_evidence_execution_plan_path",
            "workflow_state",
            "adoption_state",
            "target_reference_version",
            "operator_task_count",
            "submission_slot_count",
            "open_submission_slot_count",
            "accepted_submission_slot_count",
            "blocked_submission_slot_count",
            "not_needed_submission_slot_count",
            "submission_slots",
            "command_template_paths",
            "next_actions",
            "evidence_paths",
            "markdown_report_path",
            "html_report_path",
        ],
        prefix,
    )
    if payload.get("checklist_state") not in (
        OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_SUBMISSION_CHECKLIST_STATES
    ):
        errors.append(
            f"{prefix}.checklist_state is invalid: {payload.get('checklist_state')!r}"
        )
    if payload.get("workflow_state") not in OFFICIAL_RELEASE_WORKFLOW_STATES:
        errors.append(f"{prefix}.workflow_state is invalid: {payload.get('workflow_state')!r}")
    if payload.get("adoption_state") not in OFFICIAL_COMPARISON_ADOPTION_STATES:
        errors.append(f"{prefix}.adoption_state is invalid: {payload.get('adoption_state')!r}")
    for name in [
        "release_workflow_report_path",
        "target_reference_version",
        "markdown_report_path",
        "html_report_path",
    ]:
        require_non_empty_string(errors, payload.get(name), f"{prefix}.{name}")
    require_type(
        errors,
        payload.get("operator_evidence_execution_plan_path"),
        str,
        f"{prefix}.operator_evidence_execution_plan_path",
    )
    for name in [
        "operator_task_count",
        "submission_slot_count",
        "open_submission_slot_count",
        "accepted_submission_slot_count",
        "blocked_submission_slot_count",
        "not_needed_submission_slot_count",
    ]:
        require_non_negative_int(errors, payload.get(name), f"{prefix}.{name}")
    for name in ["command_template_paths", "next_actions", "evidence_paths"]:
        require_string_list(errors, payload.get(name), f"{prefix}.{name}")
    require_type(errors, payload.get("submission_slots"), list, f"{prefix}.submission_slots")
    if isinstance(payload.get("submission_slots"), list):
        for index, slot in enumerate(payload["submission_slots"]):
            validate_official_comparison_operator_evidence_submission_slot(
                slot,
                errors,
                f"{prefix}.submission_slots[{index}]",
            )
    enforce_official_comparison_operator_evidence_submission_checklist_invariants(
        payload,
        errors,
        prefix,
    )


def expected_official_comparison_operator_evidence_submission_manifest_types(
    return_field,
):
    if return_field == "reference_review_workflow_report_path":
        return ["reference_review_batch_workflow_report"]
    if return_field == "run_bundle_manifest_paths":
        return ["engine_run_bundle_manifest"]
    return []


def expected_reference_review_submission_next_actions(metadata):
    if not isinstance(metadata, dict):
        return []
    row_number = int_or_zero(
        metadata.get("next_blocked_review_decision_row_number")
    )
    sample_id = metadata.get("next_blocked_review_decision_sample_id")
    recommended_action = metadata.get(
        "next_blocked_review_decision_recommended_action"
    )
    if row_number and sample_id and recommended_action:
        return [
            "Edit reference review decisions row "
            f"{row_number} for sample {sample_id}: {recommended_action}."
        ]
    if recommended_action:
        return [f"Edit reference review decisions: {recommended_action}."]
    return []


def enforce_official_comparison_operator_evidence_submission_manifest_types(
    payload,
    errors,
    prefix,
):
    expected = expected_official_comparison_operator_evidence_submission_manifest_types(
        payload.get("return_field")
    )
    if not expected or not isinstance(payload.get("expected_manifest_types"), list):
        return
    if payload.get("expected_manifest_types") != expected:
        errors.append(
            f"{prefix}.expected_manifest_types must be {expected!r} "
            f"for return_field={payload.get('return_field')}"
        )


def enforce_official_comparison_operator_evidence_submission_slot_context(
    payload,
    errors,
    prefix,
):
    slot_type = payload.get("slot_type")
    return_field = payload.get("return_field")
    if slot_type == "reference_review_workflow_report":
        if return_field != "reference_review_workflow_report_path":
            errors.append(
                f"{prefix}.reference review slot requires "
                "return_field=reference_review_workflow_report_path"
            )
        if payload.get("engine_id") or payload.get("benchmark_kind"):
            errors.append(
                f"{prefix}.reference review slot requires empty engine_id and "
                "benchmark_kind"
            )
        if payload.get("sample_set") != "reference_review_batch":
            errors.append(
                f"{prefix}.reference review slot requires "
                "sample_set=reference_review_batch"
            )
        metadata = (
            payload.get("metadata")
            if isinstance(payload.get("metadata"), dict)
            else {}
        )
        readiness_path = metadata.get("submission_readiness_report_path", "")
        source_paths = payload.get("source_paths", [])
        if (
            isinstance(readiness_path, str)
            and readiness_path
            and isinstance(source_paths, list)
            and readiness_path not in source_paths
        ):
            errors.append(
                f"{prefix}.metadata.submission_readiness_report_path must be "
                "included in source_paths"
            )
        expected_workflow_path = metadata.get("expected_workflow_report_path", "")
        if isinstance(expected_workflow_path, str) and expected_workflow_path:
            expected_submission_path = (
                expected_official_comparison_operator_evidence_submission_path_details(
                    payload
                ).get("expected_submission_path", "")
            )
            if expected_workflow_path != expected_submission_path:
                errors.append(
                    f"{prefix}.metadata.expected_workflow_report_path must match "
                    "expected submission path"
                )
        for name in [
            "blocked_review_decision_item_count",
            "next_blocked_review_decision_row_number",
            "review_decision_fill_task_count",
            "review_decision_item_count",
        ]:
            if name in metadata:
                require_non_negative_int(
                    errors,
                    metadata.get(name),
                    f"{prefix}.metadata.{name}",
                )
        if "blocking_gates" in metadata:
            require_string_list(
                errors,
                metadata.get("blocking_gates"),
                f"{prefix}.metadata.blocking_gates",
            )
        for name in [
            "blocked_review_decision_sample_ids",
            "blocked_review_decision_missing_fields",
        ]:
            if name in metadata:
                require_string_list(
                    errors,
                    metadata.get(name),
                    f"{prefix}.metadata.{name}",
                )
        if "blocked_review_decision_items" in metadata:
            require_type(
                errors,
                metadata.get("blocked_review_decision_items"),
                list,
                f"{prefix}.metadata.blocked_review_decision_items",
            )
            if isinstance(metadata.get("blocked_review_decision_items"), list):
                for index, item in enumerate(metadata["blocked_review_decision_items"]):
                    validate_reference_review_submission_blocked_decision_item(
                        item,
                        errors,
                        f"{prefix}.metadata.blocked_review_decision_items[{index}]",
                    )
        if "review_decision_fill_tasks" in metadata:
            require_type(
                errors,
                metadata.get("review_decision_fill_tasks"),
                list,
                f"{prefix}.metadata.review_decision_fill_tasks",
            )
            if isinstance(metadata.get("review_decision_fill_tasks"), list):
                for index, item in enumerate(metadata["review_decision_fill_tasks"]):
                    validate_reference_review_submission_fill_task(
                        item,
                        errors,
                        f"{prefix}.metadata.review_decision_fill_tasks[{index}]",
                    )
        if "review_decisions_path" in metadata:
            require_type(
                errors,
                metadata.get("review_decisions_path"),
                str,
                f"{prefix}.metadata.review_decisions_path",
            )
        if "review_decision_fill_tasks_csv_path" in metadata:
            require_type(
                errors,
                metadata.get("review_decision_fill_tasks_csv_path"),
                str,
                f"{prefix}.metadata.review_decision_fill_tasks_csv_path",
            )
            csv_path = metadata.get("review_decision_fill_tasks_csv_path", "")
            if (
                isinstance(csv_path, str)
                and csv_path
                and isinstance(source_paths, list)
                and csv_path not in source_paths
            ):
                errors.append(
                    f"{prefix}.metadata.review_decision_fill_tasks_csv_path "
                    "must be included in source_paths"
                )
        for name in [
            "next_blocked_review_decision_sample_id",
            "next_blocked_review_decision_recommended_action",
        ]:
            if name in metadata:
                require_type(
                    errors,
                    metadata.get(name),
                    str,
                    f"{prefix}.metadata.{name}",
                )
        expected_next_actions = expected_reference_review_submission_next_actions(
            metadata
        )
        next_actions = payload.get("next_actions")
        if expected_next_actions and isinstance(next_actions, list):
            for action in expected_next_actions:
                if action not in next_actions:
                    errors.append(
                        f"{prefix}.next_actions must include reference review "
                        f"readiness action: {action}"
                    )
        readiness_report = read_json_if_available(readiness_path)
        if isinstance(readiness_report, dict):
            for name in [
                "submission_readiness_state",
                "ready_for_reference_workflow",
                "blocked_review_decision_item_count",
                "blocked_review_decision_sample_ids",
                "blocked_review_decision_missing_fields",
                "blocked_review_decision_items",
                "review_decision_fill_task_count",
                "review_decision_fill_tasks",
                "review_decision_fill_tasks_csv_path",
                "next_blocked_review_decision_row_number",
                "next_blocked_review_decision_sample_id",
                "next_blocked_review_decision_recommended_action",
                "review_decision_item_count",
                "blocking_gates",
                "review_decisions_path",
                "expected_workflow_report_path",
            ]:
                if name in metadata and metadata.get(name) != readiness_report.get(name):
                    errors.append(
                        f"{prefix}.metadata.{name} must match submission readiness report"
                    )
        handoff_step_ids = metadata.get("submission_handoff_step_ids", [])
        if handoff_step_ids and handoff_step_ids != [
            "run_reference_review_workflow",
            "return_reference_review_workflow_report",
        ]:
            errors.append(
                f"{prefix}.metadata.submission_handoff_step_ids sequence is invalid"
            )
        return
    if slot_type in {
        "target_reference_engine_bundle",
        "comparability_rerun_bundle",
        "product_path_run_bundle",
    }:
        if return_field != "run_bundle_manifest_paths":
            errors.append(
                f"{prefix}.{slot_type} requires "
                "return_field=run_bundle_manifest_paths"
            )
        for field in ["engine_id", "benchmark_kind", "sample_set"]:
            if not payload.get(field):
                errors.append(f"{prefix}.{slot_type} requires {field}")
    if (
        slot_type == "product_path_run_bundle"
        and payload.get("benchmark_kind") != "product_path_final"
    ):
        errors.append(
            f"{prefix}.product_path_run_bundle requires "
            "benchmark_kind=product_path_final"
        )


def validate_official_comparison_operator_evidence_submission_slot(slot, errors, prefix):
    if not isinstance(slot, dict):
        errors.append(f"{prefix} must be an object")
        return
    require_fields(
        errors,
        slot,
        [
            "slot_id",
            "slot_type",
            "slot_state",
            "task_id",
            "title",
            "return_field",
            "expected_manifest_types",
            "expected_value",
            "resolved_expected_value",
            "engine_id",
            "benchmark_kind",
            "sample_set",
            "current_reference_version",
            "target_reference_version",
            "evidence_to_collect",
            "acceptance_criteria",
            "source_paths",
            "command_template_paths",
            "command_templates",
            "next_actions",
            "metadata",
        ],
        prefix,
    )
    for name in ["slot_id", "slot_type", "slot_state", "task_id", "title", "return_field"]:
        require_non_empty_string(errors, slot.get(name), f"{prefix}.{name}")
    if slot.get("slot_type") not in (
        OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_SUBMISSION_SLOT_TYPES
    ):
        errors.append(f"{prefix}.slot_type is invalid: {slot.get('slot_type')!r}")
    if slot.get("slot_state") not in (
        OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_SUBMISSION_SLOT_STATES
    ):
        errors.append(f"{prefix}.slot_state is invalid: {slot.get('slot_state')!r}")
    for name in [
        "expected_manifest_types",
        "evidence_to_collect",
        "acceptance_criteria",
        "source_paths",
        "command_template_paths",
        "command_templates",
        "next_actions",
    ]:
        require_string_list(errors, slot.get(name), f"{prefix}.{name}")
    for name in [
        "expected_value",
        "resolved_expected_value",
        "engine_id",
        "benchmark_kind",
        "sample_set",
        "current_reference_version",
        "target_reference_version",
    ]:
        require_type(errors, slot.get(name), str, f"{prefix}.{name}")
    if isinstance(slot.get("sample_set"), str):
        sample_set = slot.get("sample_set", "").strip()
        if sample_set.startswith("[") and sample_set.endswith("]"):
            errors.append(f"{prefix}.sample_set must not use list literal formatting")
    require_type(errors, slot.get("metadata"), dict, f"{prefix}.metadata")
    enforce_official_comparison_operator_evidence_submission_manifest_types(
        slot,
        errors,
        prefix,
    )
    enforce_official_comparison_operator_evidence_submission_slot_context(
        slot,
        errors,
        prefix,
    )
    if slot.get("slot_state") == "open":
        if not slot.get("expected_manifest_types"):
            errors.append(f"{prefix}.open slot requires expected_manifest_types")
        if not slot.get("evidence_to_collect"):
            errors.append(f"{prefix}.open slot requires evidence_to_collect")


def enforce_official_comparison_operator_evidence_submission_checklist_invariants(
    payload,
    errors,
    prefix,
):
    slots = payload.get("submission_slots")
    if not isinstance(slots, list):
        return
    if payload.get("submission_slot_count") != len(slots):
        errors.append(f"{prefix}.submission_slot_count must equal submission_slots length")
    seen_slot_ids = set()
    state_counts = {
        "open": 0,
        "accepted": 0,
        "blocked": 0,
        "not_needed": 0,
    }
    target_reference_version = payload.get("target_reference_version")
    for index, slot in enumerate(slots):
        if not isinstance(slot, dict):
            continue
        if (
            isinstance(target_reference_version, str)
            and target_reference_version
            and isinstance(slot.get("target_reference_version"), str)
            and slot.get("target_reference_version") != target_reference_version
        ):
            errors.append(
                f"{prefix}.submission_slots[{index}].target_reference_version "
                "must match target_reference_version"
            )
        slot_id = slot.get("slot_id")
        if isinstance(slot_id, str) and slot_id:
            if slot_id in seen_slot_ids:
                errors.append(
                    f"{prefix}.submission_slots[{index}].slot_id "
                    f"must be unique: {slot_id}"
                )
            seen_slot_ids.add(slot_id)
        state = slot.get("slot_state")
        if state in state_counts:
            state_counts[state] += 1
    count_fields = {
        "open_submission_slot_count": "open",
        "accepted_submission_slot_count": "accepted",
        "blocked_submission_slot_count": "blocked",
        "not_needed_submission_slot_count": "not_needed",
    }
    for field, state in count_fields.items():
        if payload.get(field) != state_counts[state]:
            errors.append(f"{prefix}.{field} must equal {state} submission slots")
    checklist_state = payload.get("checklist_state")
    if state_counts["open"] or state_counts["blocked"]:
        if checklist_state != "ready_to_collect_operator_submissions":
            errors.append(
                f"{prefix}.checklist_state must be ready_to_collect_operator_submissions "
                "when open or blocked submission slots exist"
            )
    elif slots and checklist_state == "blocked_no_submission_path":
        errors.append(f"{prefix}.blocked_no_submission_path requires no submission slots")


def validate_official_comparison_operator_evidence_submission_status_report(
    payload,
    errors,
    prefix,
):
    require_fields(
        errors,
        payload,
        [
            "status_state",
            "submission_checklist_path",
            "operator_evidence_return_workflow_report_path",
            "release_workflow_report_path",
            "workflow_state",
            "adoption_state",
            "target_reference_version",
            "preflight_workflow_report_path",
            "decision_workflow_report_path",
            "release_artifact_audit_report_path",
            "operator_evidence_return_template_path",
            "submission_values_template_path",
            "submission_values_template_markdown_path",
            "submission_values_template_html_path",
            "submission_slot_count",
            "submitted_submission_slot_count",
            "missing_submission_slot_count",
            "rejected_submission_slot_count",
            "not_needed_submission_slot_count",
            "expected_submission_path_exists_count",
            "expected_submission_path_missing_count",
            "expected_submission_path_not_applicable_count",
            "expected_submission_path_missing_slot_ids",
            "submission_action_group_count",
            "submission_values_filled_path_count",
            "submission_values_blank_path_count",
            "submission_completion_state",
            "full_submission_ready",
            "remaining_required_slot_count",
            "remaining_required_slot_ids",
            "submitted_required_slot_ids",
            "missing_required_slot_ids",
            "rejected_required_slot_ids",
            "submission_values_minimum_required_filled_path_count",
            "submission_values_fill_command_readiness_state",
            "submission_values_fill_command_blocking_reasons",
            "submission_action_groups",
            "slot_statuses",
            "operator_fill_quickstart",
            "blocking_reasons",
            "blocking_slot_summary",
            "command_template_paths",
            "next_actions",
            "evidence_paths",
            "return_template_fill_from_status_command_template_path",
            "return_workflow_from_status_command_template_path",
            "release_workflow_from_status_command_template_path",
            "command_sequence",
            "markdown_report_path",
            "html_report_path",
        ],
        prefix,
    )
    if payload.get("status_state") not in (
        OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_SUBMISSION_STATUS_STATES
    ):
        errors.append(f"{prefix}.status_state is invalid: {payload.get('status_state')!r}")
    if payload.get("workflow_state") not in OFFICIAL_RELEASE_WORKFLOW_STATES:
        errors.append(f"{prefix}.workflow_state is invalid: {payload.get('workflow_state')!r}")
    if payload.get("adoption_state") not in OFFICIAL_COMPARISON_ADOPTION_STATES:
        errors.append(f"{prefix}.adoption_state is invalid: {payload.get('adoption_state')!r}")
    for name in [
        "submission_checklist_path",
        "release_workflow_report_path",
        "target_reference_version",
        "preflight_workflow_report_path",
        "decision_workflow_report_path",
        "operator_evidence_return_template_path",
        "submission_values_template_path",
        "submission_values_template_markdown_path",
        "submission_values_template_html_path",
        "return_template_fill_from_status_command_template_path",
        "return_workflow_from_status_command_template_path",
        "release_workflow_from_status_command_template_path",
        "markdown_report_path",
        "html_report_path",
    ]:
        require_non_empty_string(errors, payload.get(name), f"{prefix}.{name}")
    require_type(
        errors,
        payload.get("release_artifact_audit_report_path"),
        str,
        f"{prefix}.release_artifact_audit_report_path",
    )
    require_type(
        errors,
        payload.get("operator_evidence_return_workflow_report_path"),
        str,
        f"{prefix}.operator_evidence_return_workflow_report_path",
    )
    for name in [
        "submission_slot_count",
        "submitted_submission_slot_count",
        "missing_submission_slot_count",
        "rejected_submission_slot_count",
        "not_needed_submission_slot_count",
        "expected_submission_path_exists_count",
        "expected_submission_path_missing_count",
        "expected_submission_path_not_applicable_count",
        "submission_action_group_count",
        "submission_values_filled_path_count",
        "submission_values_blank_path_count",
        "remaining_required_slot_count",
        "submission_values_minimum_required_filled_path_count",
    ]:
        require_non_negative_int(errors, payload.get(name), f"{prefix}.{name}")
    if payload.get("submission_completion_state") not in (
        OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_SUBMISSION_COMPLETION_STATES
    ):
        errors.append(
            f"{prefix}.submission_completion_state is invalid: "
            f"{payload.get('submission_completion_state')!r}"
        )
    require_type(
        errors,
        payload.get("full_submission_ready"),
        bool,
        f"{prefix}.full_submission_ready",
    )
    if (
        payload.get("submission_values_fill_command_readiness_state")
        not in OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_SUBMISSION_VALUES_FILL_STATES
    ):
        errors.append(
            f"{prefix}.submission_values_fill_command_readiness_state is invalid: "
            f"{payload.get('submission_values_fill_command_readiness_state')!r}"
        )
    for name in [
        "blocking_reasons",
        "blocking_slot_summary",
        "command_template_paths",
        "next_actions",
        "evidence_paths",
        "submission_values_fill_command_blocking_reasons",
        "expected_submission_path_missing_slot_ids",
        "remaining_required_slot_ids",
        "submitted_required_slot_ids",
        "missing_required_slot_ids",
        "rejected_required_slot_ids",
    ]:
        if name == "blocking_slot_summary":
            continue
        require_string_list(errors, payload.get(name), f"{prefix}.{name}")
    require_type(
        errors,
        payload.get("blocking_slot_summary"),
        list,
        f"{prefix}.blocking_slot_summary",
    )
    if isinstance(payload.get("blocking_slot_summary"), list):
        for index, item in enumerate(payload["blocking_slot_summary"]):
            validate_official_comparison_operator_evidence_blocking_slot_summary_item(
                item,
                errors,
                f"{prefix}.blocking_slot_summary[{index}]",
            )
    require_type(errors, payload.get("command_sequence"), list, f"{prefix}.command_sequence")
    if isinstance(payload.get("command_sequence"), list):
        for index, item in enumerate(payload["command_sequence"]):
            validate_official_comparison_operator_evidence_submission_command_step(
                item,
                errors,
                f"{prefix}.command_sequence[{index}]",
            )
    require_type(errors, payload.get("slot_statuses"), list, f"{prefix}.slot_statuses")
    if isinstance(payload.get("slot_statuses"), list):
        for index, item in enumerate(payload["slot_statuses"]):
            validate_official_comparison_operator_evidence_submission_slot_status(
                item,
                errors,
                f"{prefix}.slot_statuses[{index}]",
            )
    require_type(
        errors,
        payload.get("submission_action_groups"),
        list,
        f"{prefix}.submission_action_groups",
    )
    if isinstance(payload.get("submission_action_groups"), list):
        for index, item in enumerate(payload["submission_action_groups"]):
            validate_official_comparison_operator_evidence_submission_action_group(
                item,
                errors,
                f"{prefix}.submission_action_groups[{index}]",
            )
    validate_official_comparison_operator_evidence_fill_quickstart(
        payload.get("operator_fill_quickstart"),
        errors,
        f"{prefix}.operator_fill_quickstart",
    )
    enforce_official_comparison_operator_evidence_submission_status_invariants(
        payload,
        errors,
        prefix,
    )


def validate_official_comparison_operator_evidence_submission_command_step(
    item,
    errors,
    prefix,
):
    if not isinstance(item, dict):
        errors.append(f"{prefix} must be an object")
        return
    require_fields(
        errors,
        item,
        [
            "step_id",
            "step_order",
            "title",
            "step_state",
            "command_template_path",
            "input_paths",
            "output_paths",
            "depends_on_step_ids",
            "next_actions",
        ],
        prefix,
    )
    for name in ["step_id", "title", "step_state", "command_template_path"]:
        require_non_empty_string(errors, item.get(name), f"{prefix}.{name}")
    require_non_negative_int(errors, item.get("step_order"), f"{prefix}.step_order")
    if isinstance(item.get("step_order"), int) and item.get("step_order") <= 0:
        errors.append(f"{prefix}.step_order must be greater than zero")
    if item.get("step_state") not in (
        OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_EXECUTION_STEP_STATES
    ):
        errors.append(f"{prefix}.step_state is invalid: {item.get('step_state')!r}")
    for name in [
        "input_paths",
        "output_paths",
        "depends_on_step_ids",
        "next_actions",
    ]:
        require_string_list(errors, item.get(name), f"{prefix}.{name}")
    if item.get("step_state") == "open" and not item.get("next_actions"):
        errors.append(f"{prefix}.open command sequence step requires next_actions")


def enforce_official_comparison_operator_evidence_blocking_slot_summary_invariants(
    payload,
    source_slots,
    errors,
    prefix,
):
    summary = payload.get("blocking_slot_summary")
    if not isinstance(summary, list):
        return
    expected_slots = [
        item
        for item in source_slots
        if isinstance(item, dict)
        and item.get("slot_status") in {"missing", "rejected"}
    ]
    expected_ids = [item.get("slot_id") for item in expected_slots]
    actual_ids = [
        item.get("slot_id")
        for item in summary
        if isinstance(item, dict)
    ]
    if actual_ids != expected_ids:
        errors.append(
            f"{prefix}.blocking_slot_summary must match missing/rejected slot order"
        )
    slots_by_id = {
        item.get("slot_id"): item
        for item in expected_slots
        if isinstance(item.get("slot_id"), str)
    }
    for index, item in enumerate(summary):
        if not isinstance(item, dict):
            continue
        source = slots_by_id.get(item.get("slot_id"))
        if not isinstance(source, dict):
            continue
        for field in [
            "slot_type",
            "slot_status",
            "task_id",
            "title",
            "return_field",
            "expected_manifest_types",
            "expected_submission_path",
            "expected_submission_path_state",
            "expected_submission_path_file_state",
            "command_template_paths",
            "source_artifact_hint_paths",
            "metadata",
            "next_actions",
        ]:
            if item.get(field) != source.get(field):
                errors.append(
                    f"{prefix}.blocking_slot_summary[{index}].{field} "
                    "must match source slot"
                )
        source_paths = set(source.get("source_paths", []))
        for hint_index, hint_path in enumerate(
            item.get("source_artifact_hint_paths", [])
        ):
            if hint_path not in source_paths:
                errors.append(
                    f"{prefix}.blocking_slot_summary[{index}]."
                    f"source_artifact_hint_paths[{hint_index}] must exist in source_paths"
                )


BLOCKING_SLOT_ARTIFACT_HINT_FILENAMES = {
    "reference_review_pack.html",
    "reference_review_decision_scaffold_report.html",
    "reference_review_decisions.scaffold.csv",
    "reference_review_decision_fill_tasks.csv",
    "reference_review_operator_worklist.csv",
    "reference_review_submission_readiness_report.html",
    "reference_review_submission_readiness_report.json",
    "reference_review_workflow_command_template.txt",
}


def expected_official_comparison_operator_evidence_source_artifact_hint_paths(slot):
    if not isinstance(slot, dict):
        return []
    metadata = slot.get("metadata", {})
    if not isinstance(metadata, dict):
        metadata = {}
    source_paths = unique_non_empty_strings(
        list(slot.get("source_paths", []))
        + [metadata.get("review_decision_fill_tasks_csv_path", "")]
    )
    paths = unique_non_empty_strings(
        path
        for path in source_paths
        if Path(path).name in BLOCKING_SLOT_ARTIFACT_HINT_FILENAMES
    )
    default_gate_paths = [
        path
        for path in paths
        if "reference_review_default_gate_pack" in Path(path).parts
    ]
    return default_gate_paths or paths


def validate_official_comparison_operator_evidence_blocking_slot_summary_item(
    item,
    errors,
    prefix,
):
    if not isinstance(item, dict):
        errors.append(f"{prefix} must be an object")
        return
    require_fields(
        errors,
        item,
        [
            "slot_id",
            "slot_type",
            "slot_status",
            "task_id",
            "title",
            "return_field",
            "expected_manifest_types",
            "expected_submission_path",
            "expected_submission_path_state",
            "expected_submission_path_file_state",
            "primary_blocker_reason",
            "first_command_template",
            "command_template_paths",
            "source_artifact_hint_paths",
            "metadata",
            "next_action",
            "next_actions",
        ],
        prefix,
    )
    for name in ["slot_id", "slot_type", "slot_status", "task_id", "title", "return_field"]:
        require_non_empty_string(errors, item.get(name), f"{prefix}.{name}")
    if item.get("slot_type") not in (
        OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_SUBMISSION_SLOT_TYPES
    ):
        errors.append(f"{prefix}.slot_type is invalid: {item.get('slot_type')!r}")
    if item.get("slot_status") not in {"missing", "rejected"}:
        errors.append(f"{prefix}.slot_status is invalid: {item.get('slot_status')!r}")
    require_string_list(
        errors,
        item.get("expected_manifest_types"),
        f"{prefix}.expected_manifest_types",
    )
    require_string_list(
        errors,
        item.get("command_template_paths"),
        f"{prefix}.command_template_paths",
    )
    require_string_list(
        errors,
        item.get("source_artifact_hint_paths"),
        f"{prefix}.source_artifact_hint_paths",
    )
    require_string_list(errors, item.get("next_actions"), f"{prefix}.next_actions")
    require_type(errors, item.get("metadata"), dict, f"{prefix}.metadata")
    for name in [
        "expected_submission_path",
        "expected_submission_path_state",
        "expected_submission_path_file_state",
        "primary_blocker_reason",
        "first_command_template",
        "next_action",
    ]:
        require_type(errors, item.get(name), str, f"{prefix}.{name}")
    if (
        isinstance(item.get("expected_submission_path_file_state"), str)
        and item.get("expected_submission_path_file_state")
        and item.get("expected_submission_path_file_state")
        not in OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_EXPECTED_SUBMISSION_PATH_FILE_STATES
    ):
        errors.append(
            f"{prefix}.expected_submission_path_file_state is invalid: "
            f"{item.get('expected_submission_path_file_state')!r}"
        )


def enforce_official_comparison_operator_evidence_submission_command_sequence_contract(
    sequence,
    errors,
    prefix,
    expected_command_paths=None,
    expected_step_states=None,
):
    if not isinstance(sequence, list):
        return
    steps_by_id = {
        item.get("step_id"): item
        for item in sequence
        if isinstance(item, dict)
    }
    if expected_command_paths:
        for step_id, expected in expected_command_paths.items():
            step = steps_by_id.get(step_id)
            if not isinstance(step, dict) or not expected:
                continue
            field_name, expected_path = expected
            if expected_path and step.get("command_template_path") != expected_path:
                errors.append(
                    f"{prefix}.{step_id}.command_template_path must match {field_name}"
                )
    if expected_step_states:
        for step_id, expected_state in expected_step_states.items():
            step = steps_by_id.get(step_id)
            if not isinstance(step, dict) or not expected_state:
                continue
            if step.get("step_state") != expected_state:
                errors.append(
                    f"{prefix}.{step_id}.step_state must be {expected_state}"
                )
    previous_to_current = [
        ("fill_return_template_from_status", "run_return_workflow_from_status"),
        ("run_return_workflow_from_status", "rerun_release_workflow_from_status_return"),
    ]
    for previous_id, current_id in previous_to_current:
        previous = steps_by_id.get(previous_id)
        current = steps_by_id.get(current_id)
        if not isinstance(previous, dict) or not isinstance(current, dict):
            continue
        previous_outputs = {
            path
            for path in previous.get("output_paths", [])
            if isinstance(path, str) and path
        }
        current_inputs = {
            path
            for path in current.get("input_paths", [])
            if isinstance(path, str) and path
        }
        if previous_outputs and not previous_outputs.issubset(current_inputs):
            errors.append(
                f"{prefix}.{current_id}.input_paths must include "
                f"{previous_id} output_paths"
            )


def validate_official_comparison_operator_evidence_submission_slot_status(
    item,
    errors,
    prefix,
):
    if not isinstance(item, dict):
        errors.append(f"{prefix} must be an object")
        return
    require_fields(
        errors,
        item,
        [
            "slot_id",
            "slot_type",
            "slot_status",
            "task_id",
            "title",
            "return_field",
            "expected_manifest_types",
            "expected_submission_path",
            "expected_submission_path_state",
            "expected_submission_path_file_state",
            "expected_submission_path_note",
            "engine_id",
            "benchmark_kind",
            "sample_set",
            "current_reference_version",
            "target_reference_version",
            "evidence_to_collect",
            "acceptance_criteria",
            "source_paths",
            "source_artifact_hint_paths",
            "command_template_paths",
            "command_templates",
            "return_task_state",
            "return_task_reasons",
            "return_field_resolution_state",
            "return_field_value_contract_state",
            "return_field_value_contract_errors",
            "return_field_blocked_evidence_task_ids",
            "matched_evidence_paths",
            "rejection_reasons",
            "missing_reasons",
            "matched_evidence",
            "next_actions",
            "source_candidate_diagnostics",
            "metadata",
        ],
        prefix,
    )
    for name in [
        "slot_id",
        "slot_type",
        "slot_status",
        "task_id",
        "title",
        "return_field",
    ]:
        require_non_empty_string(errors, item.get(name), f"{prefix}.{name}")
    for name in [
        "engine_id",
        "benchmark_kind",
        "sample_set",
        "current_reference_version",
        "target_reference_version",
        "return_task_state",
        "return_field_resolution_state",
        "return_field_value_contract_state",
    ]:
        require_type(errors, item.get(name), str, f"{prefix}.{name}")
    if item.get("slot_type") not in (
        OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_SUBMISSION_SLOT_TYPES
    ):
        errors.append(f"{prefix}.slot_type is invalid: {item.get('slot_type')!r}")
    if item.get("slot_status") not in (
        OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_SUBMISSION_SLOT_STATUS_STATES
    ):
        errors.append(
            f"{prefix}.slot_status is invalid: {item.get('slot_status')!r}"
        )
    enforce_official_comparison_operator_evidence_expected_submission_path_contract(
        item,
        errors,
        prefix,
    )
    for name in [
        "expected_manifest_types",
        "evidence_to_collect",
        "acceptance_criteria",
        "source_paths",
        "source_artifact_hint_paths",
        "command_template_paths",
        "command_templates",
        "return_task_reasons",
        "return_field_value_contract_errors",
        "return_field_blocked_evidence_task_ids",
        "matched_evidence_paths",
        "rejection_reasons",
        "missing_reasons",
        "next_actions",
    ]:
        require_string_list(errors, item.get(name), f"{prefix}.{name}")
    require_type(errors, item.get("matched_evidence"), list, f"{prefix}.matched_evidence")
    require_type(errors, item.get("metadata"), dict, f"{prefix}.metadata")
    if item.get("return_task_state"):
        if item.get("return_task_state") not in OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_ITEM_STATES:
            errors.append(
                f"{prefix}.return_task_state is invalid: "
                f"{item.get('return_task_state')!r}"
            )
    if item.get("return_field_resolution_state"):
        if item.get("return_field_resolution_state") not in (
            OFFICIAL_COMPARISON_RETURN_FIELD_RESOLUTION_STATES
        ):
            errors.append(
                f"{prefix}.return_field_resolution_state is invalid: "
                f"{item.get('return_field_resolution_state')!r}"
            )
    if item.get("return_field_value_contract_state"):
        if item.get("return_field_value_contract_state") not in (
            OFFICIAL_COMPARISON_RETURN_FIELD_VALUE_CONTRACT_STATES
        ):
            errors.append(
                f"{prefix}.return_field_value_contract_state is invalid: "
                f"{item.get('return_field_value_contract_state')!r}"
            )
    if item.get("return_task_state") in {"missing", "rejected"}:
        if not item.get("return_task_reasons"):
            errors.append(f"{prefix}.return_task_state requires return_task_reasons")
    if item.get("return_field_value_contract_state") == "invalid":
        if not item.get("return_field_value_contract_errors"):
            errors.append(
                f"{prefix}.invalid return field contract requires "
                "return_field_value_contract_errors"
            )
    enforce_official_comparison_operator_evidence_submission_manifest_types(
        item,
        errors,
        prefix,
    )
    enforce_official_comparison_operator_evidence_submission_slot_context(
        item,
        errors,
        prefix,
    )
    if item.get("return_field_resolution_state") in {
        "missing",
        "rejected",
        "partially_accepted",
    }:
        if not item.get("return_field_blocked_evidence_task_ids"):
            errors.append(
                f"{prefix}.blocking return field resolution requires "
                "return_field_blocked_evidence_task_ids"
            )
    if item.get("slot_status") == "submitted" and not item.get("matched_evidence_paths"):
        errors.append(f"{prefix}.submitted slot requires matched_evidence_paths")
    if item.get("slot_status") == "missing" and not item.get("missing_reasons"):
        errors.append(f"{prefix}.missing slot requires missing_reasons")
    if item.get("slot_status") == "rejected" and not item.get("rejection_reasons"):
        errors.append(f"{prefix}.rejected slot requires rejection_reasons")
    validate_official_comparison_operator_evidence_source_candidate_diagnostics(
        item.get("source_candidate_diagnostics"),
        errors,
        f"{prefix}.source_candidate_diagnostics",
    )
    if item.get("source_paths") and not item.get("source_candidate_diagnostics"):
        errors.append(
            f"{prefix}.source_candidate_diagnostics must not be empty "
            "when source_paths exist"
        )
    expected_source_artifact_hints = (
        expected_official_comparison_operator_evidence_source_artifact_hint_paths(
            item
        )
    )
    if item.get("source_artifact_hint_paths") != expected_source_artifact_hints:
        errors.append(f"{prefix}.source_artifact_hint_paths must match source_paths")
    if item.get("slot_status") in {"missing", "rejected"}:
        if not item.get("expected_manifest_types"):
            errors.append(
                f"{prefix}.{item.get('slot_status')} slot requires "
                "expected_manifest_types"
            )
        if not item.get("evidence_to_collect"):
            errors.append(
                f"{prefix}.{item.get('slot_status')} slot requires "
                "evidence_to_collect"
            )


def validate_official_comparison_operator_evidence_submission_action_group(
    item,
    errors,
    prefix,
):
    if not isinstance(item, dict):
        errors.append(f"{prefix} must be an object")
        return
    require_fields(
        errors,
        item,
        [
            "group_id",
            "group_order",
            "group_status",
            "task_id",
            "title",
            "slot_count",
            "submitted_slot_count",
            "missing_slot_count",
            "rejected_slot_count",
            "not_needed_slot_count",
            "slot_ids",
            "blocking_slot_ids",
            "return_fields",
            "slot_types",
            "expected_manifest_types",
            "engine_ids",
            "benchmark_kinds",
            "sample_sets",
            "current_reference_versions",
            "target_reference_version",
            "evidence_to_collect",
            "acceptance_criteria",
            "source_paths",
            "source_candidate_summary",
            "command_template_paths",
            "next_actions",
        ],
        prefix,
    )
    for name in ["group_id", "group_status", "task_id", "title"]:
        require_non_empty_string(errors, item.get(name), f"{prefix}.{name}")
    require_non_negative_int(errors, item.get("group_order"), f"{prefix}.group_order")
    if isinstance(item.get("group_order"), int) and item.get("group_order") <= 0:
        errors.append(f"{prefix}.group_order must be greater than zero")
    if item.get("group_status") not in (
        OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_SUBMISSION_STATUS_STATES
    ):
        errors.append(
            f"{prefix}.group_status is invalid: {item.get('group_status')!r}"
        )
    for name in [
        "slot_count",
        "submitted_slot_count",
        "missing_slot_count",
        "rejected_slot_count",
        "not_needed_slot_count",
    ]:
        require_non_negative_int(errors, item.get(name), f"{prefix}.{name}")
    for name in [
        "slot_ids",
        "blocking_slot_ids",
        "return_fields",
        "slot_types",
        "expected_manifest_types",
        "engine_ids",
        "benchmark_kinds",
        "sample_sets",
        "current_reference_versions",
        "evidence_to_collect",
        "acceptance_criteria",
        "source_paths",
        "command_template_paths",
        "next_actions",
    ]:
        require_string_list(errors, item.get(name), f"{prefix}.{name}")
    require_type(
        errors,
        item.get("target_reference_version"),
        str,
        f"{prefix}.target_reference_version",
    )
    require_type(
        errors,
        item.get("source_candidate_summary"),
        list,
        f"{prefix}.source_candidate_summary",
    )
    if isinstance(item.get("source_candidate_summary"), list):
        for index, summary in enumerate(item["source_candidate_summary"]):
            validate_official_comparison_operator_evidence_source_candidate_summary(
                summary,
                errors,
                f"{prefix}.source_candidate_summary[{index}]",
            )
    if item.get("source_paths") and not item.get("source_candidate_summary"):
        errors.append(
            f"{prefix}.source_candidate_summary must not be empty "
            "when source_paths exist"
        )
    if (
        isinstance(item.get("slot_count"), int)
        and isinstance(item.get("submitted_slot_count"), int)
        and isinstance(item.get("missing_slot_count"), int)
        and isinstance(item.get("rejected_slot_count"), int)
        and isinstance(item.get("not_needed_slot_count"), int)
    ):
        if item["slot_count"] != (
            item["submitted_slot_count"]
            + item["missing_slot_count"]
            + item["rejected_slot_count"]
            + item["not_needed_slot_count"]
        ):
            errors.append(
                f"{prefix}.slot_count must equal submitted+missing+rejected+not_needed counts"
            )
    if isinstance(item.get("slot_ids"), list) and isinstance(item.get("slot_count"), int):
        if len(item["slot_ids"]) != item["slot_count"]:
            errors.append(f"{prefix}.slot_count must equal slot_ids length")
    if isinstance(item.get("blocking_slot_ids"), list):
        expected_blocking_count = int_or_zero(item.get("missing_slot_count")) + int_or_zero(
            item.get("rejected_slot_count")
        )
        if len(item["blocking_slot_ids"]) != expected_blocking_count:
            errors.append(
                f"{prefix}.blocking_slot_ids length must equal missing+rejected counts"
            )


def validate_official_comparison_operator_evidence_source_candidate_summary(
    item,
    errors,
    prefix,
):
    if not isinstance(item, dict):
        errors.append(f"{prefix} must be an object")
        return
    require_fields(
        errors,
        item,
        ["candidate_state", "candidate_count", "reasons"],
        prefix,
    )
    require_type(errors, item.get("candidate_state"), str, f"{prefix}.candidate_state")
    require_non_negative_int(
        errors,
        item.get("candidate_count"),
        f"{prefix}.candidate_count",
    )
    require_string_list(errors, item.get("reasons"), f"{prefix}.reasons")
    if item.get("candidate_state") not in (
        OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_SOURCE_CANDIDATE_STATES
    ):
        errors.append(
            f"{prefix}.candidate_state is invalid: {item.get('candidate_state')!r}"
        )
    if item.get("candidate_state") != "usable_as_submission" and not item.get("reasons"):
        errors.append(f"{prefix}.non-usable candidate summary requires reasons")


def validate_official_comparison_operator_evidence_fill_quickstart(
    item,
    errors,
    prefix,
):
    if not isinstance(item, dict):
        errors.append(f"{prefix} must be an object")
        return
    require_fields(
        errors,
        item,
        [
            "status_state",
            "submission_completion_state",
            "full_submission_ready",
            "fill_command_readiness_state",
            "slot_value_count",
            "filled_path_count",
            "blank_path_count",
            "remaining_required_slot_count",
            "remaining_required_slot_ids",
            "edit_path",
            "editable_field",
            "fill_command_template_path",
            "groups",
            "slot_path_inputs",
            "next_actions",
        ],
        prefix,
    )
    if item.get("status_state") not in (
        OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_SUBMISSION_STATUS_STATES
    ):
        errors.append(
            f"{prefix}.status_state is invalid: {item.get('status_state')!r}"
        )
    if item.get("submission_completion_state") not in (
        OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_SUBMISSION_COMPLETION_STATES
    ):
        errors.append(
            f"{prefix}.submission_completion_state is invalid: "
            f"{item.get('submission_completion_state')!r}"
        )
    require_type(
        errors,
        item.get("full_submission_ready"),
        bool,
        f"{prefix}.full_submission_ready",
    )
    if item.get("fill_command_readiness_state") not in (
        OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_SUBMISSION_VALUES_FILL_STATES
    ):
        errors.append(
            f"{prefix}.fill_command_readiness_state is invalid: "
            f"{item.get('fill_command_readiness_state')!r}"
        )
    for name in [
        "slot_value_count",
        "filled_path_count",
        "blank_path_count",
        "remaining_required_slot_count",
    ]:
        require_non_negative_int(errors, item.get(name), f"{prefix}.{name}")
    for name in [
        "edit_path",
        "editable_field",
        "fill_command_template_path",
    ]:
        require_non_empty_string(errors, item.get(name), f"{prefix}.{name}")
    if item.get("editable_field") != "slot_values[].path":
        errors.append(f"{prefix}.editable_field must be 'slot_values[].path'")
    require_string_list(
        errors,
        item.get("remaining_required_slot_ids"),
        f"{prefix}.remaining_required_slot_ids",
    )
    require_string_list(errors, item.get("next_actions"), f"{prefix}.next_actions")
    require_type(errors, item.get("groups"), list, f"{prefix}.groups")
    if isinstance(item.get("groups"), list):
        for index, group in enumerate(item["groups"]):
            validate_official_comparison_operator_evidence_fill_quickstart_group(
                group,
                errors,
                f"{prefix}.groups[{index}]",
            )
    require_type(
        errors,
        item.get("slot_path_inputs"),
        list,
        f"{prefix}.slot_path_inputs",
    )
    if isinstance(item.get("slot_path_inputs"), list):
        enforce_official_comparison_operator_evidence_completion_summary(
            item,
            item.get("slot_path_inputs", []),
            errors,
            prefix,
        )
        for index, slot in enumerate(item["slot_path_inputs"]):
            validate_official_comparison_operator_evidence_fill_quickstart_slot(
                slot,
                errors,
                f"{prefix}.slot_path_inputs[{index}]",
            )


def validate_official_comparison_operator_evidence_fill_quickstart_group(
    item,
    errors,
    prefix,
):
    if not isinstance(item, dict):
        errors.append(f"{prefix} must be an object")
        return
    require_fields(
        errors,
        item,
        [
            "group_id",
            "group_order",
            "task_id",
            "title",
            "group_status",
            "slot_count",
            "missing_slot_count",
            "rejected_slot_count",
            "blocking_slot_ids",
            "expected_manifest_types",
            "task_command_template_paths",
            "first_command_templates",
            "primary_next_action",
        ],
        prefix,
    )
    for name in ["group_id", "task_id", "title", "group_status"]:
        require_non_empty_string(errors, item.get(name), f"{prefix}.{name}")
    require_non_negative_int(errors, item.get("group_order"), f"{prefix}.group_order")
    if isinstance(item.get("group_order"), int) and item.get("group_order") <= 0:
        errors.append(f"{prefix}.group_order must be greater than zero")
    if item.get("group_status") not in (
        OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_SUBMISSION_STATUS_STATES
    ):
        errors.append(
            f"{prefix}.group_status is invalid: {item.get('group_status')!r}"
        )
    for name in ["slot_count", "missing_slot_count", "rejected_slot_count"]:
        require_non_negative_int(errors, item.get(name), f"{prefix}.{name}")
    for name in [
        "blocking_slot_ids",
        "expected_manifest_types",
        "task_command_template_paths",
        "first_command_templates",
    ]:
        require_string_list(errors, item.get(name), f"{prefix}.{name}")
    require_type(
        errors,
        item.get("primary_next_action"),
        str,
        f"{prefix}.primary_next_action",
    )


def validate_official_comparison_operator_evidence_fill_quickstart_slot(
    item,
    errors,
    prefix,
):
    if not isinstance(item, dict):
        errors.append(f"{prefix} must be an object")
        return
    require_fields(
        errors,
        item,
        [
            "slot_id",
            "group_id",
            "task_id",
            "slot_status",
            "slot_type",
            "return_field",
            "engine_id",
            "benchmark_kind",
            "sample_set",
            "target_reference_version",
            "path",
            "path_value_hint",
            "expected_submission_path",
            "expected_submission_path_state",
            "expected_submission_path_file_state",
            "expected_submission_path_note",
            "expected_manifest_types",
            "primary_blocker_reason",
            "task_command_template_paths",
            "first_command_template",
            "source_artifact_hint_paths",
            "metadata",
            "next_action",
        ],
        prefix,
    )
    for name in ["slot_id", "group_id", "task_id", "slot_status", "slot_type", "return_field"]:
        require_non_empty_string(errors, item.get(name), f"{prefix}.{name}")
    for name in [
        "engine_id",
        "benchmark_kind",
        "sample_set",
        "target_reference_version",
        "path",
        "path_value_hint",
        "expected_submission_path",
        "expected_submission_path_state",
        "expected_submission_path_file_state",
        "expected_submission_path_note",
        "primary_blocker_reason",
        "first_command_template",
        "next_action",
    ]:
        require_type(errors, item.get(name), str, f"{prefix}.{name}")
    if item.get("slot_status") not in (
        OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_SUBMISSION_SLOT_STATUS_STATES
    ):
        errors.append(
            f"{prefix}.slot_status is invalid: {item.get('slot_status')!r}"
        )
    if item.get("slot_type") not in (
        OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_SUBMISSION_SLOT_TYPES
    ):
        errors.append(f"{prefix}.slot_type is invalid: {item.get('slot_type')!r}")
    if item.get("return_field") not in {
        "reference_review_workflow_report_path",
        "run_bundle_manifest_paths",
    }:
        errors.append(f"{prefix}.return_field is invalid: {item.get('return_field')!r}")
    expected_hint = (
        expected_official_comparison_operator_evidence_submission_path_value_hint(
            item.get("return_field")
        )
    )
    if expected_hint and item.get("path_value_hint") != expected_hint:
        errors.append(f"{prefix}.path_value_hint must be {expected_hint!r}")
    if (
        isinstance(item.get("expected_submission_path_state"), str)
        and item.get("expected_submission_path_state")
        not in OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_EXPECTED_SUBMISSION_PATH_STATES
    ):
        errors.append(
            f"{prefix}.expected_submission_path_state is invalid: "
            f"{item.get('expected_submission_path_state')!r}"
        )
    if (
        isinstance(item.get("expected_submission_path_file_state"), str)
        and item.get("expected_submission_path_file_state")
        not in OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_EXPECTED_SUBMISSION_PATH_FILE_STATES
    ):
        errors.append(
            f"{prefix}.expected_submission_path_file_state is invalid: "
            f"{item.get('expected_submission_path_file_state')!r}"
        )
    require_non_empty_string(
        errors,
        item.get("expected_submission_path_state"),
        f"{prefix}.expected_submission_path_state",
    )
    require_non_empty_string(
        errors,
        item.get("expected_submission_path_file_state"),
        f"{prefix}.expected_submission_path_file_state",
    )
    require_non_empty_string(
        errors,
        item.get("expected_submission_path_note"),
        f"{prefix}.expected_submission_path_note",
    )
    for name in [
        "expected_manifest_types",
        "task_command_template_paths",
        "source_artifact_hint_paths",
    ]:
        require_string_list(errors, item.get(name), f"{prefix}.{name}")
    require_type(errors, item.get("metadata"), dict, f"{prefix}.metadata")


def first_non_empty_string(values):
    if isinstance(values, list):
        for value in values:
            if isinstance(value, str) and value.strip():
                return value
    return ""


def official_comparison_operator_evidence_quickstart_first_command_for_slot(slot):
    if not isinstance(slot, dict):
        return ""
    commands = slot.get("command_templates")
    if not isinstance(commands, list):
        return ""
    if (
        slot.get("slot_type") == "product_path_run_bundle"
        and slot.get("benchmark_kind") == "product_path_final"
    ):
        for command in commands:
            if (
                isinstance(command, str)
                and "convert_stt_pipeline_to_official_bundle.py" in command
            ):
                return command
    return first_non_empty_string(commands)


def official_comparison_operator_evidence_quickstart_path_for_slot(slot):
    if not isinstance(slot, dict):
        return ""
    if isinstance(slot.get("path"), str):
        return slot.get("path", "")
    paths = slot.get("matched_evidence_paths")
    if isinstance(paths, list):
        return first_non_empty_string(paths)
    return ""


def official_comparison_operator_evidence_quickstart_blocker_for_slot(slot):
    if not isinstance(slot, dict):
        return ""
    for field in [
        "rejection_reasons",
        "missing_reasons",
        "return_field_value_contract_errors",
        "return_task_reasons",
    ]:
        value = first_non_empty_string(slot.get(field))
        if value:
            return value
    return ""


def official_comparison_operator_evidence_quickstart_task_command_paths(slot):
    if not isinstance(slot, dict):
        return []
    paths = unique_non_empty_strings(slot.get("command_template_paths", []))
    task_paths = [
        path
        for path in paths
        if not any(marker in path for marker in GENERIC_OPERATOR_COMMAND_PATH_MARKERS)
    ]
    return task_paths or paths[:1]


def official_comparison_operator_evidence_quickstart_slot_ids(slots):
    return [
        slot.get("slot_id")
        for slot in slots
        if isinstance(slot, dict)
        and slot.get("slot_status") != "not_needed"
        and isinstance(slot.get("slot_id"), str)
        and slot.get("slot_id")
    ]


def enforce_official_comparison_operator_evidence_fill_quickstart_invariants(
    payload,
    errors,
    prefix,
    slot_field,
    count_field_names,
    path_field_names=None,
):
    quickstart = payload.get("operator_fill_quickstart")
    if not isinstance(quickstart, dict):
        return
    slots = payload.get(slot_field)
    groups = payload.get("submission_action_groups")
    if not isinstance(slots, list) or not isinstance(groups, list):
        return

    status_field, fill_field, filled_field, blank_field = count_field_names
    field_pairs = [
        ("status_state", status_field),
        ("fill_command_readiness_state", fill_field),
        ("filled_path_count", filled_field),
        ("blank_path_count", blank_field),
    ]
    for quickstart_field, payload_field in field_pairs:
        if not payload_field:
            continue
        if quickstart.get(quickstart_field) != payload.get(payload_field):
            errors.append(
                f"{prefix}.operator_fill_quickstart.{quickstart_field} "
                f"must match {payload_field}"
            )
    completion_summary = (
        expected_official_comparison_operator_evidence_completion_summary(slots)
    )
    for field in [
        "submission_completion_state",
        "full_submission_ready",
        "remaining_required_slot_count",
        "remaining_required_slot_ids",
    ]:
        if quickstart.get(field) != completion_summary[field]:
            errors.append(
                f"{prefix}.operator_fill_quickstart.{field} "
                f"must match {slot_field}"
            )

    expected_slot_ids = official_comparison_operator_evidence_quickstart_slot_ids(slots)
    if quickstart.get("slot_value_count") != len(expected_slot_ids):
        errors.append(
            f"{prefix}.operator_fill_quickstart.slot_value_count "
            f"must equal non-not-needed {slot_field} length"
        )

    if path_field_names:
        edit_field, fill_command_field = path_field_names
        if quickstart.get("edit_path") != payload.get(edit_field):
            errors.append(
                f"{prefix}.operator_fill_quickstart.edit_path must match {edit_field}"
            )
        if quickstart.get("fill_command_template_path") != payload.get(fill_command_field):
            errors.append(
                f"{prefix}.operator_fill_quickstart.fill_command_template_path "
                f"must match {fill_command_field}"
            )

    slot_inputs = quickstart.get("slot_path_inputs")
    if isinstance(slot_inputs, list):
        actual_slot_ids = [
            item.get("slot_id")
            for item in slot_inputs
            if isinstance(item, dict)
            and isinstance(item.get("slot_id"), str)
            and item.get("slot_id")
        ]
        if actual_slot_ids != expected_slot_ids:
            errors.append(
                f"{prefix}.operator_fill_quickstart.slot_path_inputs "
                f"must match {slot_field} non-not-needed slot order"
            )
        group_id_by_slot_id = {
            slot_id: group.get("group_id", "")
            for group in groups
            if isinstance(group, dict)
            for slot_id in group.get("slot_ids", [])
            if isinstance(slot_id, str)
        }
        source_by_slot_id = {
            slot.get("slot_id"): slot
            for slot in slots
            if isinstance(slot, dict) and isinstance(slot.get("slot_id"), str)
        }
        for index, item in enumerate(slot_inputs):
            if not isinstance(item, dict):
                continue
            slot = source_by_slot_id.get(item.get("slot_id"))
            if not isinstance(slot, dict):
                continue
            item_prefix = (
                f"{prefix}.operator_fill_quickstart.slot_path_inputs[{index}]"
            )
            expected_pairs = [
                ("group_id", group_id_by_slot_id.get(slot.get("slot_id"), "")),
                ("task_id", slot.get("task_id", "")),
                ("slot_status", slot.get("slot_status", "")),
                ("slot_type", slot.get("slot_type", "")),
                ("return_field", slot.get("return_field", "")),
                ("engine_id", slot.get("engine_id", "")),
                ("benchmark_kind", slot.get("benchmark_kind", "")),
                ("sample_set", slot.get("sample_set", "")),
                ("target_reference_version", slot.get("target_reference_version", "")),
                ("path", official_comparison_operator_evidence_quickstart_path_for_slot(slot)),
                (
                    "path_value_hint",
                    expected_official_comparison_operator_evidence_submission_path_value_hint(
                        slot.get("return_field")
                    ),
                ),
                (
                    "first_command_template",
                    official_comparison_operator_evidence_quickstart_first_command_for_slot(
                        slot
                    ),
                ),
                (
                    "metadata",
                    slot.get("metadata", {})
                    if isinstance(slot.get("metadata"), dict)
                    else {},
                ),
                ("next_action", first_non_empty_string(slot.get("next_actions"))),
            ]
            expected_submission_path_details = (
                expected_official_comparison_operator_evidence_submission_path_details(
                    slot
                )
            )
            expected_pairs.extend(
                (field, expected_submission_path_details[field])
                for field in [
                    "expected_submission_path",
                    "expected_submission_path_state",
                    "expected_submission_path_file_state",
                    "expected_submission_path_note",
                ]
            )
            if slot_field != "slot_values":
                expected_pairs.append((
                    "primary_blocker_reason",
                    official_comparison_operator_evidence_quickstart_blocker_for_slot(slot),
                ))
            for field, expected in expected_pairs:
                if expected is not None and item.get(field) != expected:
                    errors.append(f"{item_prefix}.{field} must match {slot_field}")
            if item.get("expected_manifest_types") != slot.get("expected_manifest_types", []):
                errors.append(
                    f"{item_prefix}.expected_manifest_types must match {slot_field}"
                )
            expected_task_commands = (
                official_comparison_operator_evidence_quickstart_task_command_paths(
                    slot
                )
            )
            if item.get("task_command_template_paths") != expected_task_commands:
                errors.append(
                    f"{item_prefix}.task_command_template_paths must match "
                    f"{slot_field}"
                )
            expected_hints = (
                expected_official_comparison_operator_evidence_source_artifact_hint_paths(
                    slot
                )
            )
            if item.get("source_artifact_hint_paths") != expected_hints:
                errors.append(
                    f"{item_prefix}.source_artifact_hint_paths must match "
                    f"{slot_field}"
                )

    quickstart_groups = quickstart.get("groups")
    if isinstance(quickstart_groups, list):
        expected_group_ids = [
            group.get("group_id")
            for group in groups
            if isinstance(group, dict)
            and isinstance(group.get("group_id"), str)
            and group.get("group_id")
        ]
        actual_group_ids = [
            group.get("group_id")
            for group in quickstart_groups
            if isinstance(group, dict)
            and isinstance(group.get("group_id"), str)
            and group.get("group_id")
        ]
        if actual_group_ids != expected_group_ids:
            errors.append(
                f"{prefix}.operator_fill_quickstart.groups must match "
                "submission_action_groups order"
            )
        slots_by_id = {
            slot.get("slot_id"): slot
            for slot in slots
            if isinstance(slot, dict) and isinstance(slot.get("slot_id"), str)
        }
        group_by_id = {
            group.get("group_id"): group
            for group in groups
            if isinstance(group, dict) and isinstance(group.get("group_id"), str)
        }
        for index, quickstart_group in enumerate(quickstart_groups):
            if not isinstance(quickstart_group, dict):
                continue
            group = group_by_id.get(quickstart_group.get("group_id"))
            if not isinstance(group, dict):
                continue
            item_prefix = f"{prefix}.operator_fill_quickstart.groups[{index}]"
            expected_pairs = [
                ("group_order", group.get("group_order", 0)),
                ("task_id", group.get("task_id", "")),
                ("title", group.get("title", "")),
                ("group_status", group.get("group_status", "")),
                ("slot_count", group.get("slot_count", 0)),
                ("missing_slot_count", group.get("missing_slot_count", 0)),
                ("rejected_slot_count", group.get("rejected_slot_count", 0)),
                ("primary_next_action", first_non_empty_string(group.get("next_actions"))),
            ]
            for field, expected in expected_pairs:
                if quickstart_group.get(field) != expected:
                    errors.append(f"{item_prefix}.{field} must match submission_action_groups")
            for field in ["blocking_slot_ids", "expected_manifest_types"]:
                if quickstart_group.get(field) != group.get(field, []):
                    errors.append(f"{item_prefix}.{field} must match submission_action_groups")
            group_slots = [
                slots_by_id[slot_id]
                for slot_id in group.get("slot_ids", [])
                if slot_id in slots_by_id
            ]
            expected_task_commands = unique_non_empty_strings(
                path
                for slot in group_slots
                for path in official_comparison_operator_evidence_quickstart_task_command_paths(
                    slot
                )
            )
            if quickstart_group.get("task_command_template_paths") != expected_task_commands:
                errors.append(
                    f"{item_prefix}.task_command_template_paths must match "
                    "group slot task command templates"
                )
            expected_first_commands = unique_non_empty_strings(
                official_comparison_operator_evidence_quickstart_first_command_for_slot(
                    slot
                )
                for slot in group_slots
            )
            if quickstart_group.get("first_command_templates") != expected_first_commands:
                errors.append(
                    f"{item_prefix}.first_command_templates must match "
                    "group slot first command templates"
                )


def unique_strings(values):
    result = []
    for value in values:
        if isinstance(value, str) and value not in result:
            result.append(value)
    return result


def unique_non_empty_strings(values):
    result = []
    for value in values:
        if isinstance(value, str) and value.strip() and value not in result:
            result.append(value)
    return result


def expected_official_comparison_operator_evidence_source_candidate_summary_for_slots(
    slots,
):
    summaries = {}
    for slot in slots:
        if not isinstance(slot, dict):
            continue
        diagnostics = slot.get("source_candidate_diagnostics")
        if not isinstance(diagnostics, list):
            continue
        for diagnostic in diagnostics:
            if not isinstance(diagnostic, dict):
                continue
            state = diagnostic.get("candidate_state")
            if not isinstance(state, str) or not state:
                continue
            summary = summaries.setdefault(
                state,
                {
                    "candidate_state": state,
                    "candidate_count": 0,
                    "reasons": [],
                },
            )
            summary["candidate_count"] += 1
            reasons = diagnostic.get("reasons", [])
            if isinstance(reasons, list):
                summary["reasons"] = unique_strings(summary["reasons"] + reasons)

    ordered = [
        summaries[state]
        for state in OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_SOURCE_CANDIDATE_STATE_ORDER
        if state in summaries
    ]
    ordered.extend(
        summaries[state]
        for state in sorted(summaries)
        if state
        not in OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_SOURCE_CANDIDATE_STATE_ORDER
    )
    return ordered


def expected_official_comparison_operator_evidence_submission_next_actions_for_slots(
    slots,
):
    return unique_non_empty_strings(
        action
        for slot in slots
        if isinstance(slot, dict) and isinstance(slot.get("next_actions"), list)
        for action in slot.get("next_actions", [])
    )


def expected_official_comparison_operator_evidence_submission_group_list_for_slots(
    slots,
    field,
):
    return unique_non_empty_strings(
        value
        for slot in slots
        if isinstance(slot, dict) and isinstance(slot.get(field), list)
        for value in slot.get(field, [])
    )


def expected_official_comparison_operator_evidence_submission_group_scalar_list_for_slots(
    slots,
    field,
):
    return unique_non_empty_strings(
        slot.get(field)
        for slot in slots
        if isinstance(slot, dict) and field in slot
    )


def enforce_official_release_gate_report_copy_invariants(
    payload,
    errors,
    prefix,
):
    gate = read_linked_manifest_if_available(
        payload,
        "release_gate_report_path",
        "official_comparison_release_gate_report",
        errors,
        prefix,
    )
    if gate is None:
        return
    field_pairs = [
        ("release_state", "release_state"),
        ("eligible_for_default_release", "eligible_for_default_release"),
        ("preflight_workflow_report_path", "preflight_workflow_report_path"),
        ("decision_workflow_report_path", "decision_workflow_report_path"),
        ("blocking_gates", "blocking_gates"),
        ("blocking_reasons", "blocking_reasons"),
        ("operator_handoff_report_path", "operator_handoff_report_path"),
        ("operator_handoff_state", "operator_handoff_state"),
        ("operator_handoff_item_count", "operator_handoff_item_count"),
        (
            "operator_handoff_blocked_item_count",
            "operator_handoff_blocked_item_count",
        ),
        (
            "operator_evidence_intake_report_path",
            "operator_evidence_intake_report_path",
        ),
        ("operator_evidence_intake_state", "operator_evidence_intake_state"),
        (
            "operator_evidence_ready_to_rerun_preflight",
            "operator_evidence_ready_to_rerun_preflight",
        ),
        (
            "operator_evidence_accepted_item_count",
            "operator_evidence_accepted_item_count",
        ),
        (
            "operator_evidence_missing_item_count",
            "operator_evidence_missing_item_count",
        ),
        (
            "operator_evidence_rejected_item_count",
            "operator_evidence_rejected_item_count",
        ),
        ("preflight_resume_plan_path", "preflight_resume_plan_path"),
        ("preflight_resume_plan_state", "preflight_resume_plan_state"),
        ("preflight_resume_ready_to_rerun", "preflight_resume_ready_to_rerun"),
    ]
    for release_field, gate_field in field_pairs:
        if (
            release_field in payload
            and gate_field in gate
            and payload.get(release_field) != gate.get(gate_field)
        ):
            errors.append(
                f"{prefix}.{release_field} must match "
                f"release_gate_report.{gate_field}"
            )


def enforce_official_release_artifact_prep_report_copy_invariants(
    payload,
    errors,
    prefix,
):
    prep = read_linked_manifest_if_available(
        payload,
        "artifact_prep_report_path",
        "official_comparison_next_action_artifact_prep_report",
        errors,
        prefix,
    )
    if prep is None:
        return
    field_pairs = [
        ("preflight_workflow_report_path", "workflow_report_path"),
        ("target_reference_version", "reference_version"),
    ]
    for release_field, prep_field in field_pairs:
        if (
            release_field in payload
            and prep_field in prep
            and payload.get(release_field) != prep.get(prep_field)
        ):
            errors.append(
                f"{prefix}.{release_field} must match "
                f"artifact_prep_report.{prep_field}"
            )


def enforce_official_release_execution_status_report_copy_invariants(
    payload,
    errors,
    prefix,
):
    execution_status = read_linked_manifest_if_available(
        payload,
        "execution_status_report_path",
        "official_comparison_next_action_execution_status_report",
        errors,
        prefix,
    )
    if execution_status is None:
        return
    field_pairs = [
        ("preflight_workflow_report_path", "workflow_report_path"),
        ("artifact_prep_report_path", "artifact_prep_report_path"),
        ("target_reference_version", "reference_version"),
    ]
    for release_field, execution_field in field_pairs:
        if (
            release_field in payload
            and execution_field in execution_status
            and payload.get(release_field) != execution_status.get(execution_field)
        ):
            errors.append(
                f"{prefix}.{release_field} must match "
                f"execution_status_report.{execution_field}"
            )


def enforce_official_release_operator_handoff_report_copy_invariants(
    payload,
    errors,
    prefix,
):
    handoff = read_linked_manifest_if_available(
        payload,
        "operator_handoff_report_path",
        "official_comparison_operator_handoff_report",
        errors,
        prefix,
    )
    if handoff is None:
        return
    field_pairs = [
        ("preflight_workflow_report_path", "workflow_report_path"),
        ("artifact_prep_report_path", "artifact_prep_report_path"),
        ("execution_status_report_path", "execution_status_report_path"),
        ("operator_handoff_state", "handoff_state"),
        ("operator_handoff_item_count", "item_count"),
        ("operator_handoff_ready_item_count", "ready_item_count"),
        ("operator_handoff_blocked_item_count", "blocked_item_count"),
    ]
    for release_field, handoff_field in field_pairs:
        if (
            release_field in payload
            and handoff_field in handoff
            and payload.get(release_field) != handoff.get(handoff_field)
        ):
            errors.append(
                f"{prefix}.{release_field} must match "
                f"operator_handoff_report.{handoff_field}"
            )


def enforce_official_release_operator_evidence_intake_report_copy_invariants(
    payload,
    errors,
    prefix,
):
    intake = read_linked_manifest_if_available(
        payload,
        "operator_evidence_intake_report_path",
        "official_comparison_operator_evidence_intake_report",
        errors,
        prefix,
    )
    if intake is None:
        return
    field_pairs = [
        ("operator_handoff_report_path", "handoff_report_path"),
        ("target_reference_version", "target_reference_version"),
        ("operator_evidence_intake_state", "intake_state"),
        ("operator_evidence_ready_to_rerun_preflight", "ready_to_rerun_preflight"),
        ("operator_handoff_item_count", "item_count"),
        ("operator_evidence_accepted_item_count", "accepted_item_count"),
        ("operator_evidence_missing_item_count", "missing_item_count"),
        ("operator_evidence_rejected_item_count", "rejected_item_count"),
    ]
    for release_field, intake_field in field_pairs:
        if (
            release_field in payload
            and intake_field in intake
            and payload.get(release_field) != intake.get(intake_field)
        ):
            errors.append(
                f"{prefix}.{release_field} must match "
                f"operator_evidence_intake_report.{intake_field}"
            )


def enforce_official_release_preflight_resume_plan_copy_invariants(
    payload,
    errors,
    prefix,
):
    resume = read_linked_manifest_if_available(
        payload,
        "preflight_resume_plan_path",
        "official_comparison_preflight_resume_plan",
        errors,
        prefix,
    )
    if resume is None:
        return
    field_pairs = [
        ("operator_evidence_intake_report_path", "intake_report_path"),
        ("operator_handoff_report_path", "handoff_report_path"),
        ("preflight_workflow_report_path", "source_workflow_report_path"),
        ("target_reference_version", "target_reference_version"),
        ("preflight_resume_plan_state", "plan_state"),
        ("preflight_resume_ready_to_rerun", "ready_to_rerun_preflight"),
    ]
    for release_field, resume_field in field_pairs:
        if (
            release_field in payload
            and resume_field in resume
            and payload.get(release_field) != resume.get(resume_field)
        ):
            errors.append(
                f"{prefix}.{release_field} must match "
                f"preflight_resume_plan.{resume_field}"
            )


def enforce_official_release_execution_plan_copy_invariants(
    payload,
    errors,
    prefix,
):
    plan = read_linked_manifest_if_available(
        payload,
        "operator_evidence_execution_plan_path",
        "official_comparison_operator_evidence_execution_plan",
        errors,
        prefix,
    )
    if plan is None:
        return
    field_pairs = [
        ("workflow_state", "workflow_state"),
        ("adoption_state", "adoption_state"),
        ("target_reference_version", "target_reference_version"),
        (
            "operator_evidence_request_report_path",
            "operator_evidence_request_report_path",
        ),
        ("operator_evidence_return_template_path", "operator_evidence_return_template_path"),
        (
            "operator_evidence_return_template_fill_command_template_path",
            "operator_evidence_return_template_fill_command_template_path",
        ),
        (
            "operator_evidence_return_workflow_command_template_path",
            "operator_evidence_return_workflow_command_template_path",
        ),
        (
            "operator_evidence_release_workflow_command_template_path",
            "operator_evidence_release_workflow_command_template_path",
        ),
        ("adoption_remediation_plan_path", "adoption_remediation_plan_path"),
        ("operator_handoff_item_count", "operator_task_count"),
        ("operator_evidence_return_field_requirements", "return_field_requirements"),
        ("operator_tasks", "operator_tasks"),
        ("operator_evidence_execution_step_state_counts", "execution_step_state_counts"),
        ("operator_evidence_open_execution_step_count", "open_execution_step_count"),
        ("operator_evidence_blocked_execution_step_count", "blocked_execution_step_count"),
        ("operator_evidence_completed_execution_step_count", "completed_execution_step_count"),
        (
            "operator_evidence_not_needed_execution_step_count",
            "not_needed_execution_step_count",
        ),
        ("operator_evidence_open_execution_step_ids", "open_execution_step_ids"),
        ("operator_evidence_blocked_execution_step_ids", "blocked_execution_step_ids"),
        ("operator_evidence_next_open_execution_step_id", "next_open_execution_step_id"),
        (
            "operator_evidence_next_open_execution_step_title",
            "next_open_execution_step_title",
        ),
        (
            "operator_evidence_next_open_execution_step_task_ids",
            "next_open_execution_step_task_ids",
        ),
        (
            "operator_evidence_next_open_execution_step_return_fields",
            "next_open_execution_step_return_fields",
        ),
        (
            "operator_evidence_next_open_execution_step_blocking_submission_slot_ids",
            "next_open_execution_step_blocking_submission_slot_ids",
        ),
        (
            "operator_evidence_next_open_execution_step_blocking_submission_slot_details",
            "next_open_execution_step_blocking_submission_slot_details",
        ),
        (
            "operator_evidence_next_open_execution_step_source_artifact_hint_paths",
            "next_open_execution_step_source_artifact_hint_paths",
        ),
        (
            "operator_evidence_next_open_execution_step_command_template_paths",
            "next_open_execution_step_command_template_paths",
        ),
        (
            "operator_evidence_next_open_execution_step_next_actions",
            "next_open_execution_step_next_actions",
        ),
    ]
    required_plan_summary_fields = {
        "execution_step_state_counts",
        "open_execution_step_count",
        "blocked_execution_step_count",
        "completed_execution_step_count",
        "not_needed_execution_step_count",
        "open_execution_step_ids",
        "blocked_execution_step_ids",
        "next_open_execution_step_id",
        "next_open_execution_step_title",
        "next_open_execution_step_task_ids",
        "next_open_execution_step_return_fields",
        "next_open_execution_step_blocking_submission_slot_ids",
        "next_open_execution_step_blocking_submission_slot_details",
        "next_open_execution_step_source_artifact_hint_paths",
        "next_open_execution_step_command_template_paths",
        "next_open_execution_step_next_actions",
    }
    for release_field, plan_field in field_pairs:
        if plan_field in required_plan_summary_fields and plan_field not in plan:
            errors.append(
                f"{prefix}.operator_evidence_execution_plan.{plan_field} is required"
            )
            continue
        if (
            release_field in payload
            and plan_field in plan
            and payload.get(release_field) != plan.get(plan_field)
        ):
            errors.append(
                f"{prefix}.{release_field} must match "
                f"operator_evidence_execution_plan.{plan_field}"
            )
    if (
        isinstance(payload.get("command_template_paths"), list)
        and isinstance(plan.get("command_template_paths"), list)
    ):
        release_commands = set(payload.get("command_template_paths", []))
        missing_commands = [
            command
            for command in plan.get("command_template_paths", [])
            if command not in release_commands
        ]
        if missing_commands:
            errors.append(
                f"{prefix}.command_template_paths must include "
                "operator_evidence_execution_plan.command_template_paths"
            )


def validate_official_release_execution_plan_summary_context(payload, errors, prefix):
    if "operator_evidence_execution_plan_path" not in payload:
        return
    require_fields(
        errors,
        payload,
        [
            "operator_evidence_execution_step_state_counts",
            "operator_evidence_open_execution_step_count",
            "operator_evidence_blocked_execution_step_count",
            "operator_evidence_completed_execution_step_count",
            "operator_evidence_not_needed_execution_step_count",
            "operator_evidence_open_execution_step_ids",
            "operator_evidence_blocked_execution_step_ids",
            "operator_evidence_next_open_execution_step_id",
            "operator_evidence_next_open_execution_step_title",
            "operator_evidence_next_open_execution_step_task_ids",
            "operator_evidence_next_open_execution_step_return_fields",
            "operator_evidence_next_open_execution_step_blocking_submission_slot_ids",
            "operator_evidence_next_open_execution_step_blocking_submission_slot_details",
            "operator_evidence_next_open_execution_step_source_artifact_hint_paths",
            "operator_evidence_next_open_execution_step_command_template_paths",
            "operator_evidence_next_open_execution_step_next_actions",
        ],
        prefix,
    )
    require_type(
        errors,
        payload.get("operator_evidence_execution_step_state_counts"),
        dict,
        f"{prefix}.operator_evidence_execution_step_state_counts",
    )
    if isinstance(payload.get("operator_evidence_execution_step_state_counts"), dict):
        for state in OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_EXECUTION_STEP_STATES:
            require_non_negative_int(
                errors,
                payload["operator_evidence_execution_step_state_counts"].get(state),
                f"{prefix}.operator_evidence_execution_step_state_counts.{state}",
            )
    for name in [
        "operator_evidence_open_execution_step_count",
        "operator_evidence_blocked_execution_step_count",
        "operator_evidence_completed_execution_step_count",
        "operator_evidence_not_needed_execution_step_count",
    ]:
        require_non_negative_int(errors, payload.get(name), f"{prefix}.{name}")
    for name in [
        "operator_evidence_open_execution_step_ids",
        "operator_evidence_blocked_execution_step_ids",
    ]:
        require_string_list(errors, payload.get(name), f"{prefix}.{name}")
    require_type(
        errors,
        payload.get("operator_evidence_next_open_execution_step_id"),
        str,
        f"{prefix}.operator_evidence_next_open_execution_step_id",
    )
    require_type(
        errors,
        payload.get("operator_evidence_next_open_execution_step_title"),
        str,
        f"{prefix}.operator_evidence_next_open_execution_step_title",
    )
    for name in [
        "operator_evidence_next_open_execution_step_task_ids",
        "operator_evidence_next_open_execution_step_return_fields",
        "operator_evidence_next_open_execution_step_blocking_submission_slot_ids",
        "operator_evidence_next_open_execution_step_source_artifact_hint_paths",
        "operator_evidence_next_open_execution_step_command_template_paths",
        "operator_evidence_next_open_execution_step_next_actions",
    ]:
        require_string_list(errors, payload.get(name), f"{prefix}.{name}")
    require_type(
        errors,
        payload.get(
            "operator_evidence_next_open_execution_step_blocking_submission_slot_details"
        ),
        list,
        (
            f"{prefix}."
            "operator_evidence_next_open_execution_step_blocking_submission_slot_details"
        ),
    )
    if isinstance(
        payload.get(
            "operator_evidence_next_open_execution_step_blocking_submission_slot_details"
        ),
        list,
    ):
        for index, item in enumerate(
            payload[
                "operator_evidence_next_open_execution_step_blocking_submission_slot_details"
            ]
        ):
            validate_official_comparison_operator_evidence_blocking_slot_summary_item(
                item,
                errors,
                (
                    f"{prefix}."
                    "operator_evidence_next_open_execution_step_"
                    f"blocking_submission_slot_details[{index}]"
                ),
            )


def expected_official_release_next_blocking_submission_context(payload):
    summary = payload.get("operator_evidence_submission_blocking_slot_summary")
    item = summary[0] if isinstance(summary, list) and summary and isinstance(summary[0], dict) else {}
    field_pairs = [
        ("operator_evidence_next_blocking_submission_slot_id", "slot_id"),
        ("operator_evidence_next_blocking_submission_slot_type", "slot_type"),
        ("operator_evidence_next_blocking_submission_slot_status", "slot_status"),
        ("operator_evidence_next_blocking_submission_task_id", "task_id"),
        ("operator_evidence_next_blocking_submission_title", "title"),
        ("operator_evidence_next_blocking_submission_return_field", "return_field"),
        (
            "operator_evidence_next_blocking_submission_expected_submission_path",
            "expected_submission_path",
        ),
        (
            "operator_evidence_next_blocking_submission_expected_submission_path_file_state",
            "expected_submission_path_file_state",
        ),
        (
            "operator_evidence_next_blocking_submission_primary_blocker_reason",
            "primary_blocker_reason",
        ),
        (
            "operator_evidence_next_blocking_submission_first_command_template",
            "first_command_template",
        ),
        (
            "operator_evidence_next_blocking_submission_next_action",
            "next_action",
        ),
    ]
    expected = {
        release_field: item.get(item_field, "")
        for release_field, item_field in field_pairs
    }
    expected[
        "operator_evidence_next_blocking_submission_source_artifact_hint_paths"
    ] = (
        item.get("source_artifact_hint_paths", [])
        if isinstance(item.get("source_artifact_hint_paths"), list)
        else []
    )
    expected["operator_evidence_next_blocking_submission_command_template_paths"] = (
        item.get("command_template_paths", [])
        if isinstance(item.get("command_template_paths"), list)
        else []
    )
    expected["operator_evidence_next_blocking_submission_next_actions"] = (
        item.get("next_actions", [])
        if isinstance(item.get("next_actions"), list)
        else []
    )
    expected["operator_evidence_next_blocking_submission_metadata"] = (
        item.get("metadata", {})
        if isinstance(item.get("metadata"), dict)
        else {}
    )
    return expected


def validate_official_release_next_blocking_submission_context(payload, errors, prefix):
    if "operator_evidence_submission_status_report_path" not in payload:
        return
    fields = [
        "operator_evidence_next_blocking_submission_slot_id",
        "operator_evidence_next_blocking_submission_slot_type",
        "operator_evidence_next_blocking_submission_slot_status",
        "operator_evidence_next_blocking_submission_task_id",
        "operator_evidence_next_blocking_submission_title",
        "operator_evidence_next_blocking_submission_return_field",
        "operator_evidence_next_blocking_submission_expected_submission_path",
        "operator_evidence_next_blocking_submission_expected_submission_path_file_state",
        "operator_evidence_next_blocking_submission_primary_blocker_reason",
        "operator_evidence_next_blocking_submission_first_command_template",
        "operator_evidence_next_blocking_submission_next_action",
        "operator_evidence_next_blocking_submission_source_artifact_hint_paths",
        "operator_evidence_next_blocking_submission_command_template_paths",
        "operator_evidence_next_blocking_submission_next_actions",
        "operator_evidence_next_blocking_submission_metadata",
    ]
    require_fields(errors, payload, fields, prefix)
    for name in [
        "operator_evidence_next_blocking_submission_slot_id",
        "operator_evidence_next_blocking_submission_slot_type",
        "operator_evidence_next_blocking_submission_slot_status",
        "operator_evidence_next_blocking_submission_task_id",
        "operator_evidence_next_blocking_submission_title",
        "operator_evidence_next_blocking_submission_return_field",
        "operator_evidence_next_blocking_submission_expected_submission_path",
        "operator_evidence_next_blocking_submission_expected_submission_path_file_state",
        "operator_evidence_next_blocking_submission_primary_blocker_reason",
        "operator_evidence_next_blocking_submission_first_command_template",
        "operator_evidence_next_blocking_submission_next_action",
    ]:
        require_type(errors, payload.get(name), str, f"{prefix}.{name}")
    require_string_list(
        errors,
        payload.get("operator_evidence_next_blocking_submission_source_artifact_hint_paths"),
        f"{prefix}.operator_evidence_next_blocking_submission_source_artifact_hint_paths",
    )
    require_string_list(
        errors,
        payload.get("operator_evidence_next_blocking_submission_command_template_paths"),
        f"{prefix}.operator_evidence_next_blocking_submission_command_template_paths",
    )
    require_string_list(
        errors,
        payload.get("operator_evidence_next_blocking_submission_next_actions"),
        f"{prefix}.operator_evidence_next_blocking_submission_next_actions",
    )
    require_type(
        errors,
        payload.get("operator_evidence_next_blocking_submission_metadata"),
        dict,
        f"{prefix}.operator_evidence_next_blocking_submission_metadata",
    )
    for name, expected_value in expected_official_release_next_blocking_submission_context(
        payload
    ).items():
        if name in payload and payload.get(name) != expected_value:
            errors.append(
                f"{prefix}.{name} must match "
                "operator_evidence_submission_blocking_slot_summary[0]"
            )


def enforce_official_release_submission_checklist_copy_invariants(
    payload,
    errors,
    prefix,
):
    checklist = read_linked_manifest_if_available(
        payload,
        "operator_evidence_submission_checklist_path",
        "official_comparison_operator_evidence_submission_checklist",
        errors,
        prefix,
    )
    if checklist is None:
        return
    field_pairs = [
        ("workflow_state", "workflow_state"),
        ("adoption_state", "adoption_state"),
        ("target_reference_version", "target_reference_version"),
        ("operator_handoff_item_count", "operator_task_count"),
        ("operator_evidence_submission_slot_count", "submission_slot_count"),
    ]
    for release_field, checklist_field in field_pairs:
        if (
            release_field in payload
            and checklist_field in checklist
            and payload.get(release_field) != checklist.get(checklist_field)
        ):
            errors.append(
                f"{prefix}.{release_field} must match "
                f"operator_evidence_submission_checklist.{checklist_field}"
            )
    if (
        isinstance(payload.get("command_template_paths"), list)
        and isinstance(checklist.get("command_template_paths"), list)
    ):
        release_commands = set(payload.get("command_template_paths", []))
        missing_commands = [
            command
            for command in checklist.get("command_template_paths", [])
            if command not in release_commands
        ]
        if missing_commands:
            errors.append(
                f"{prefix}.command_template_paths must include "
                "operator_evidence_submission_checklist.command_template_paths"
            )


def enforce_official_release_submission_status_report_copy_invariants(
    payload,
    errors,
    prefix,
):
    status = read_linked_manifest_if_available(
        payload,
        "operator_evidence_submission_status_report_path",
        "official_comparison_operator_evidence_submission_status_report",
        errors,
        prefix,
    )
    if status is None:
        return
    field_pairs = [
        ("operator_evidence_submission_status_state", "status_state"),
        ("operator_evidence_submission_slot_count", "submission_slot_count"),
        (
            "operator_evidence_submission_completion_state",
            "submission_completion_state",
        ),
        ("operator_evidence_full_submission_ready", "full_submission_ready"),
        (
            "operator_evidence_remaining_required_slot_count",
            "remaining_required_slot_count",
        ),
        (
            "operator_evidence_remaining_required_slot_ids",
            "remaining_required_slot_ids",
        ),
        (
            "operator_evidence_submission_action_group_count",
            "submission_action_group_count",
        ),
        (
            "operator_evidence_submission_action_groups",
            "submission_action_groups",
        ),
        (
            "operator_evidence_submission_values_template_path",
            "submission_values_template_path",
        ),
        (
            "operator_evidence_submission_values_template_markdown_path",
            "submission_values_template_markdown_path",
        ),
        (
            "operator_evidence_submission_values_template_html_path",
            "submission_values_template_html_path",
        ),
        (
            "operator_evidence_submitted_submission_slot_count",
            "submitted_submission_slot_count",
        ),
        (
            "operator_evidence_missing_submission_slot_count",
            "missing_submission_slot_count",
        ),
        (
            "operator_evidence_rejected_submission_slot_count",
            "rejected_submission_slot_count",
        ),
        (
            "operator_evidence_not_needed_submission_slot_count",
            "not_needed_submission_slot_count",
        ),
        (
            "operator_evidence_expected_submission_path_exists_count",
            "expected_submission_path_exists_count",
        ),
        (
            "operator_evidence_expected_submission_path_missing_count",
            "expected_submission_path_missing_count",
        ),
        (
            "operator_evidence_expected_submission_path_not_applicable_count",
            "expected_submission_path_not_applicable_count",
        ),
        (
            "operator_evidence_expected_submission_path_missing_slot_ids",
            "expected_submission_path_missing_slot_ids",
        ),
        ("operator_evidence_submission_blocking_reasons", "blocking_reasons"),
        (
            "operator_evidence_submission_blocking_slot_summary",
            "blocking_slot_summary",
        ),
        ("operator_evidence_submission_command_sequence", "command_sequence"),
    ]
    for release_field, status_field in field_pairs:
        if (
            release_field in payload
            and status_field in status
            and payload.get(release_field) != status.get(status_field)
        ):
            errors.append(
                f"{prefix}.{release_field} must match "
                f"operator_evidence_submission_status_report.{status_field}"
            )
    slot_statuses = status.get("slot_statuses")
    if isinstance(slot_statuses, list):
        state_fields = [
            ("submitted", "operator_evidence_submitted_submission_slot_ids"),
            ("missing", "operator_evidence_missing_submission_slot_ids"),
            ("rejected", "operator_evidence_rejected_submission_slot_ids"),
            ("not_needed", "operator_evidence_not_needed_submission_slot_ids"),
        ]
        for state, release_field in state_fields:
            expected_ids = unique_non_empty_strings(
                item.get("slot_id")
                for item in slot_statuses
                if isinstance(item, dict) and item.get("slot_status") == state
            )
            if release_field in payload and payload.get(release_field) != expected_ids:
                errors.append(
                    f"{prefix}.{release_field} must match "
                    f"operator_evidence_submission_status_report {state} slot ids"
                )
        expected_blocking_slots = [
            item
            for item in slot_statuses
            if isinstance(item, dict) and item.get("slot_status") in {"missing", "rejected"}
        ]
        if (
            "operator_evidence_blocking_submission_slots" in payload
            and payload.get("operator_evidence_blocking_submission_slots")
            != expected_blocking_slots
        ):
            errors.append(
                f"{prefix}.operator_evidence_blocking_submission_slots must match "
                "operator_evidence_submission_status_report missing/rejected slots"
            )


def enforce_official_release_request_report_copy_invariants(
    payload,
    errors,
    prefix,
):
    request = read_linked_manifest_if_available(
        payload,
        "operator_evidence_request_report_path",
        "official_comparison_operator_evidence_request_report",
        errors,
        prefix,
    )
    if request is None:
        return
    field_pairs = [
        ("operator_evidence_request_state", "request_state"),
        (
            "operator_evidence_request_target_reference_version",
            "target_reference_version",
        ),
        ("operator_evidence_requested_task_count", "requested_task_count"),
        ("operator_evidence_return_template_path", "return_template_path"),
        (
            "operator_evidence_return_guide_markdown_path",
            "return_guide_markdown_path",
        ),
        (
            "operator_evidence_return_guide_html_path",
            "return_guide_html_path",
        ),
        (
            "operator_evidence_return_template_fill_command_template_path",
            "return_template_fill_command_template_path",
        ),
        (
            "operator_evidence_return_workflow_command_template_path",
            "return_workflow_command_template_path",
        ),
        (
            "operator_evidence_intake_command_template_path",
            "intake_command_template_path",
        ),
        (
            "operator_evidence_release_workflow_command_template_path",
            "release_workflow_command_template_path",
        ),
        (
            "operator_evidence_return_field_requirements",
            "return_field_requirements",
        ),
    ]
    for release_field, request_field in field_pairs:
        if (
            release_field in payload
            and request_field in request
            and payload.get(release_field) != request.get(request_field)
        ):
            errors.append(
                f"{prefix}.{release_field} must match "
                f"operator_evidence_request_report.{request_field}"
            )
    if (
        isinstance(payload.get("command_template_paths"), list)
        and isinstance(request.get("command_template_paths"), list)
    ):
        release_commands = set(payload.get("command_template_paths", []))
        missing_commands = [
            command
            for command in request.get("command_template_paths", [])
            if command not in release_commands
        ]
        if missing_commands:
            errors.append(
                f"{prefix}.command_template_paths must include "
                "operator_evidence_request_report.command_template_paths"
            )


def enforce_official_release_adoption_remediation_plan_copy_invariants(
    payload,
    errors,
    prefix,
):
    remediation = read_linked_manifest_if_available(
        payload,
        "adoption_remediation_plan_path",
        "official_comparison_adoption_remediation_plan",
        errors,
        prefix,
    )
    if remediation is None:
        return
    field_pairs = [
        ("adoption_remediation_plan_state", "plan_state"),
        ("adoption_state", "adoption_state"),
        (
            "adoption_remediation_target_reference_version",
            "target_reference_version",
        ),
        ("adoption_remediation_task_count", "task_count"),
        ("adoption_remediation_open_task_count", "open_task_count"),
    ]
    for release_field, remediation_field in field_pairs:
        if (
            release_field in payload
            and remediation_field in remediation
            and payload.get(release_field) != remediation.get(remediation_field)
        ):
            errors.append(
                f"{prefix}.{release_field} must match "
                f"adoption_remediation_plan.{remediation_field}"
            )
    if (
        isinstance(payload.get("command_template_paths"), list)
        and isinstance(remediation.get("command_template_paths"), list)
    ):
        release_commands = set(payload.get("command_template_paths", []))
        missing_commands = [
            command
            for command in remediation.get("command_template_paths", [])
            if command not in release_commands
        ]
        if missing_commands:
            errors.append(
                f"{prefix}.command_template_paths must include "
                "adoption_remediation_plan.command_template_paths"
            )


def enforce_official_release_adoption_checklist_report_copy_invariants(
    payload,
    errors,
    prefix,
):
    checklist = read_linked_manifest_if_available(
        payload,
        "adoption_checklist_report_path",
        "official_comparison_adoption_checklist_report",
        errors,
        prefix,
    )
    if checklist is None:
        return
    field_pairs = [
        ("workflow_state", "workflow_state"),
        ("release_state", "release_state"),
        ("eligible_for_default_release", "eligible_for_default_release"),
        ("adoption_state", "adoption_state"),
        ("adoption_passed_item_count", "passed_item_count"),
        ("adoption_blocked_item_count", "blocked_item_count"),
        ("adoption_unknown_item_count", "unknown_item_count"),
    ]
    for release_field, checklist_field in field_pairs:
        if (
            release_field in payload
            and checklist_field in checklist
            and payload.get(release_field) != checklist.get(checklist_field)
        ):
            errors.append(
                f"{prefix}.{release_field} must match "
                f"adoption_checklist_report.{checklist_field}"
            )
    checklist_items = checklist.get("checklist_items")
    blockers = payload.get("adoption_blockers")
    if isinstance(checklist_items, list) and isinstance(blockers, list):
        expected_blocker_ids = [
            item.get("item_id")
            for item in checklist_items
            if isinstance(item, dict)
            and item.get("state") in {"blocked", "unknown"}
            and isinstance(item.get("item_id"), str)
            and item.get("item_id")
        ]
        actual_blocker_ids = [
            item.get("item_id")
            for item in blockers
            if isinstance(item, dict)
            and isinstance(item.get("item_id"), str)
            and item.get("item_id")
        ]
        if actual_blocker_ids != expected_blocker_ids:
            errors.append(
                f"{prefix}.adoption_blockers item ids must match "
                "adoption_checklist_report blocked/unknown item ids"
            )


def enforce_official_release_submission_values_template_copy_invariants(
    payload,
    errors,
    prefix,
):
    values = read_linked_manifest_if_available(
        payload,
        "operator_evidence_submission_values_template_path",
        "official_comparison_operator_evidence_submission_values_template",
        errors,
        prefix,
    )
    if values is None:
        return
    field_pairs = [
        (
            "operator_evidence_submission_values_template_markdown_path",
            "markdown_report_path",
        ),
        (
            "operator_evidence_submission_values_template_html_path",
            "html_report_path",
        ),
        (
            "operator_evidence_submission_values_filled_path_count",
            "filled_path_count",
        ),
        (
            "operator_evidence_submission_values_blank_path_count",
            "blank_path_count",
        ),
        (
            "operator_evidence_submission_values_minimum_required_filled_path_count",
            "minimum_required_filled_path_count",
        ),
        (
            "operator_evidence_submission_values_fill_command_readiness_state",
            "fill_command_readiness_state",
        ),
        (
            "operator_evidence_submission_values_fill_command_blocking_reasons",
            "fill_command_blocking_reasons",
        ),
        ("target_reference_version", "target_reference_version"),
        (
            "operator_evidence_return_template_path",
            "operator_evidence_return_template_path",
        ),
    ]
    for release_field, values_field in field_pairs:
        if (
            release_field in payload
            and values_field in values
            and payload.get(release_field) != values.get(values_field)
        ):
            errors.append(
                f"{prefix}.{release_field} must match "
                f"operator_evidence_submission_values_template.{values_field}"
            )


def enforce_official_release_return_workflow_report_copy_invariants(
    payload,
    errors,
    prefix,
):
    return_report = read_linked_manifest_if_available(
        payload,
        "operator_evidence_return_workflow_report_path",
        "official_comparison_operator_evidence_return_workflow_report",
        errors,
        prefix,
    )
    if return_report is None:
        return
    field_pairs = [
        ("operator_evidence_return_state", "return_state"),
        (
            "operator_evidence_return_target_reference_version",
            "target_reference_version",
        ),
        (
            "operator_evidence_return_intake_state",
            "operator_evidence_intake_state",
        ),
        (
            "operator_evidence_return_accepted_item_count",
            "operator_evidence_accepted_item_count",
        ),
        (
            "operator_evidence_return_missing_item_count",
            "operator_evidence_missing_item_count",
        ),
        (
            "operator_evidence_return_rejected_item_count",
            "operator_evidence_rejected_item_count",
        ),
        (
            "operator_evidence_return_preflight_resume_plan_state",
            "preflight_resume_plan_state",
        ),
        (
            "operator_evidence_return_ready_to_rerun_preflight",
            "preflight_resume_ready_to_rerun",
        ),
        ("operator_evidence_return_field_statuses", "return_field_statuses"),
        (
            "operator_evidence_return_submission_slot_values",
            "submission_slot_values",
        ),
    ]
    for release_field, return_field in field_pairs:
        if (
            release_field in payload
            and return_field in return_report
            and payload.get(release_field) != return_report.get(return_field)
        ):
            errors.append(
                f"{prefix}.{release_field} must match "
                f"operator_evidence_return_workflow_report.{return_field}"
            )


def expected_submission_status_state_from_counts(submitted, missing, rejected, total):
    if total == 0:
        return "no_operator_evidence_needed"
    if rejected > 0:
        return "blocked_invalid_submissions"
    if missing == 0:
        return "all_slots_submitted"
    if submitted > 0:
        return "partially_submitted"
    return "waiting_for_submissions"


def enforce_official_comparison_operator_evidence_submission_action_group_invariants(
    payload,
    slots,
    group_count_field,
    groups_field,
    errors,
    prefix,
):
    groups = payload.get(groups_field)
    if not isinstance(groups, list) or not isinstance(slots, list):
        return
    if payload.get(group_count_field) != len(groups):
        errors.append(f"{prefix}.{group_count_field} must equal {groups_field} length")
    slot_status_by_id = {
        item.get("slot_id"): item.get("slot_status")
        for item in slots
        if isinstance(item, dict)
        and isinstance(item.get("slot_id"), str)
        and item.get("slot_id")
    }
    slot_by_id = {
        item.get("slot_id"): item
        for item in slots
        if isinstance(item, dict)
        and isinstance(item.get("slot_id"), str)
        and item.get("slot_id")
    }
    target_reference_by_id = {
        item.get("slot_id"): item.get("target_reference_version")
        for item in slots
        if isinstance(item, dict)
        and isinstance(item.get("slot_id"), str)
        and item.get("slot_id")
    }
    seen_group_ids = set()
    covered_slot_ids = []
    for index, group in enumerate(groups):
        if not isinstance(group, dict):
            continue
        expected_order = index + 1
        if group.get("group_order") != expected_order:
            errors.append(
                f"{prefix}.{groups_field}[{index}].group_order must be {expected_order}"
            )
        group_id = group.get("group_id")
        if isinstance(group_id, str) and group_id:
            if group_id in seen_group_ids:
                errors.append(
                    f"{prefix}.{groups_field}[{index}].group_id must be unique: {group_id}"
                )
            seen_group_ids.add(group_id)
        slot_ids = group.get("slot_ids")
        if not isinstance(slot_ids, list):
            continue
        group_state_counts = {
            "submitted": 0,
            "missing": 0,
            "rejected": 0,
            "not_needed": 0,
        }
        group_slots = []
        has_unknown_slot = False
        for slot_id in slot_ids:
            if not isinstance(slot_id, str) or not slot_id:
                continue
            covered_slot_ids.append(slot_id)
            if slot_id not in slot_status_by_id:
                has_unknown_slot = True
                errors.append(
                    f"{prefix}.{groups_field}[{index}].slot_ids contains unknown slot_id: "
                    f"{slot_id}"
                )
                continue
            group_slots.append(slot_by_id[slot_id])
            state = slot_status_by_id[slot_id]
            if state in group_state_counts:
                group_state_counts[state] += 1
        expected_counts = {
            "slot_count": len(slot_ids),
            "submitted_slot_count": group_state_counts["submitted"],
            "missing_slot_count": group_state_counts["missing"],
            "rejected_slot_count": group_state_counts["rejected"],
            "not_needed_slot_count": group_state_counts["not_needed"],
        }
        for field, expected in expected_counts.items():
            if group.get(field) != expected:
                errors.append(
                    f"{prefix}.{groups_field}[{index}].{field} must be {expected}"
                )
        expected_group_status = expected_submission_status_state_from_counts(
            group_state_counts["submitted"],
            group_state_counts["missing"],
            group_state_counts["rejected"],
            len(slot_ids),
        )
        if group.get("group_status") in (
            OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_SUBMISSION_STATUS_STATES
        ) and group.get("group_status") != expected_group_status:
            errors.append(
                f"{prefix}.{groups_field}[{index}].group_status must be "
                f"{expected_group_status}"
            )
        expected_blocking_slot_ids = {
            slot_id
            for slot_id in slot_ids
            if slot_status_by_id.get(slot_id) in {"missing", "rejected"}
        }
        blocking_slot_ids = group.get("blocking_slot_ids")
        if isinstance(blocking_slot_ids, list):
            if set(blocking_slot_ids) != expected_blocking_slot_ids:
                errors.append(
                    f"{prefix}.{groups_field}[{index}].blocking_slot_ids must equal "
                    "missing/rejected slot ids"
                )
        target_references = {
            target_reference_by_id.get(slot_id)
            for slot_id in slot_ids
            if isinstance(target_reference_by_id.get(slot_id), str)
            and target_reference_by_id.get(slot_id)
        }
        if len(target_references) == 1:
            expected_target = next(iter(target_references))
            if group.get("target_reference_version") != expected_target:
                errors.append(
                    f"{prefix}.{groups_field}[{index}].target_reference_version "
                    "must match grouped slot target_reference_version"
                )
        grouped_list_fields = [
            "expected_manifest_types",
            "evidence_to_collect",
            "acceptance_criteria",
            "source_paths",
            "command_template_paths",
        ]
        for field in grouped_list_fields:
            group_has_field = any(
                isinstance(slot, dict) and field in slot for slot in group_slots
            )
            if (
                not has_unknown_slot
                and group_has_field
                and isinstance(group.get(field), list)
            ):
                expected_values = (
                    expected_official_comparison_operator_evidence_submission_group_list_for_slots(
                        group_slots,
                        field,
                    )
                )
                if group.get(field) != expected_values:
                    errors.append(
                        f"{prefix}.{groups_field}[{index}].{field} "
                        f"must match grouped slot {field}"
                    )
        grouped_scalar_list_fields = [
            ("return_fields", "return_field"),
            ("slot_types", "slot_type"),
            ("engine_ids", "engine_id"),
            ("benchmark_kinds", "benchmark_kind"),
            ("sample_sets", "sample_set"),
            ("current_reference_versions", "current_reference_version"),
        ]
        for group_field, slot_field in grouped_scalar_list_fields:
            group_has_field = any(
                isinstance(slot, dict) and slot_field in slot for slot in group_slots
            )
            if (
                not has_unknown_slot
                and group_has_field
                and isinstance(group.get(group_field), list)
            ):
                expected_values = (
                    expected_official_comparison_operator_evidence_submission_group_scalar_list_for_slots(
                        group_slots,
                        slot_field,
                    )
                )
                if group.get(group_field) != expected_values:
                    errors.append(
                        f"{prefix}.{groups_field}[{index}].{group_field} "
                        "must match grouped slot context"
                    )
        group_has_source_candidate_diagnostics = any(
            isinstance(slot, dict) and "source_candidate_diagnostics" in slot
            for slot in group_slots
        )
        if (
            not has_unknown_slot
            and group_has_source_candidate_diagnostics
            and isinstance(group.get("source_candidate_summary"), list)
        ):
            expected_summary = (
                expected_official_comparison_operator_evidence_source_candidate_summary_for_slots(
                    group_slots
                )
            )
            if group.get("source_candidate_summary") != expected_summary:
                errors.append(
                    f"{prefix}.{groups_field}[{index}].source_candidate_summary "
                    "must match grouped slot source_candidate_diagnostics"
                )
        group_has_next_actions = any(
            isinstance(slot, dict) and "next_actions" in slot
            for slot in group_slots
        )
        if (
            not has_unknown_slot
            and group_has_next_actions
            and isinstance(group.get("next_actions"), list)
        ):
            expected_next_actions = (
                expected_official_comparison_operator_evidence_submission_next_actions_for_slots(
                    group_slots
                )
            )
            if group.get("next_actions") != expected_next_actions:
                errors.append(
                    f"{prefix}.{groups_field}[{index}].next_actions "
                    "must match grouped slot next_actions"
                )
    expected_slot_ids = set(slot_status_by_id)
    duplicate_slot_ids = {
        slot_id
        for slot_id in covered_slot_ids
        if covered_slot_ids.count(slot_id) > 1
    }
    if duplicate_slot_ids:
        errors.append(f"{prefix}.{groups_field}.slot_ids must be unique across groups")
    if set(covered_slot_ids) != expected_slot_ids:
        errors.append(f"{prefix}.{groups_field}.slot_ids must cover all slot statuses")


def expected_official_comparison_operator_evidence_completion_summary(items):
    actionable_items = [
        item
        for item in items
        if isinstance(item, dict) and item.get("slot_status") != "not_needed"
    ]
    missing_slot_ids = unique_non_empty_strings(
        item.get("slot_id", "")
        for item in actionable_items
        if item.get("slot_status") == "missing"
    )
    rejected_slot_ids = unique_non_empty_strings(
        item.get("slot_id", "")
        for item in actionable_items
        if item.get("slot_status") == "rejected"
    )
    submitted_slot_ids = unique_non_empty_strings(
        item.get("slot_id", "")
        for item in actionable_items
        if item.get("slot_status") == "submitted"
    )
    remaining_slot_ids = unique_non_empty_strings(missing_slot_ids + rejected_slot_ids)
    if not actionable_items:
        completion_state = "no_operator_evidence_needed"
    elif rejected_slot_ids:
        completion_state = "blocked_invalid_submissions"
    elif not remaining_slot_ids:
        completion_state = "complete_submission_ready"
    elif submitted_slot_ids:
        completion_state = "partial_submission_ready"
    else:
        completion_state = "waiting_for_required_submissions"
    return {
        "submission_completion_state": completion_state,
        "full_submission_ready": completion_state == "complete_submission_ready",
        "submitted_required_slot_ids": submitted_slot_ids,
        "missing_required_slot_ids": missing_slot_ids,
        "rejected_required_slot_ids": rejected_slot_ids,
        "remaining_required_slot_ids": remaining_slot_ids,
        "remaining_required_slot_count": len(remaining_slot_ids),
    }


def enforce_official_comparison_operator_evidence_completion_summary(
    payload,
    items,
    errors,
    prefix,
):
    expected = expected_official_comparison_operator_evidence_completion_summary(items)
    if payload.get("submission_completion_state") in (
        OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_SUBMISSION_COMPLETION_STATES
    ):
        if payload.get("submission_completion_state") != expected[
            "submission_completion_state"
        ]:
            errors.append(
                f"{prefix}.submission_completion_state must be "
                f"{expected['submission_completion_state']}"
            )
    if isinstance(payload.get("full_submission_ready"), bool):
        if payload.get("full_submission_ready") != expected["full_submission_ready"]:
            errors.append(
                f"{prefix}.full_submission_ready must be "
                f"{expected['full_submission_ready']}"
            )
    if isinstance(payload.get("remaining_required_slot_count"), int):
        if payload.get("remaining_required_slot_count") != expected[
            "remaining_required_slot_count"
        ]:
            errors.append(
                f"{prefix}.remaining_required_slot_count must be "
                f"{expected['remaining_required_slot_count']}"
            )
    for field in [
        "submitted_required_slot_ids",
        "missing_required_slot_ids",
        "rejected_required_slot_ids",
        "remaining_required_slot_ids",
    ]:
        if isinstance(payload.get(field), list) and payload.get(field) != expected[field]:
            errors.append(f"{prefix}.{field} must match slot statuses")


def enforce_official_comparison_operator_evidence_submission_status_invariants(
    payload,
    errors,
    prefix,
):
    statuses = payload.get("slot_statuses")
    if not isinstance(statuses, list):
        return
    if payload.get("submission_slot_count") != len(statuses):
        errors.append(f"{prefix}.submission_slot_count must equal slot_statuses length")
    enforce_official_comparison_operator_evidence_completion_summary(
        payload,
        statuses,
        errors,
        prefix,
    )
    enforce_official_comparison_operator_evidence_submission_action_group_invariants(
        payload,
        statuses,
        "submission_action_group_count",
        "submission_action_groups",
        errors,
        prefix,
    )
    seen_slot_ids = set()
    state_counts = {
        "submitted": 0,
        "missing": 0,
        "rejected": 0,
        "not_needed": 0,
    }
    target_reference_version = payload.get("target_reference_version")
    for index, item in enumerate(statuses):
        if not isinstance(item, dict):
            continue
        if (
            isinstance(target_reference_version, str)
            and target_reference_version
            and isinstance(item.get("target_reference_version"), str)
            and item.get("target_reference_version") != target_reference_version
        ):
            errors.append(
                f"{prefix}.slot_statuses[{index}].target_reference_version "
                "must match target_reference_version"
            )
        slot_id = item.get("slot_id")
        if isinstance(slot_id, str) and slot_id:
            if slot_id in seen_slot_ids:
                errors.append(
                    f"{prefix}.slot_statuses[{index}].slot_id "
                    f"must be unique: {slot_id}"
                )
            seen_slot_ids.add(slot_id)
        state = item.get("slot_status")
        if state in state_counts:
            state_counts[state] += 1
    count_fields = {
        "submitted_submission_slot_count": "submitted",
        "missing_submission_slot_count": "missing",
        "rejected_submission_slot_count": "rejected",
        "not_needed_submission_slot_count": "not_needed",
    }
    for field, state in count_fields.items():
        if payload.get(field) != state_counts[state]:
            errors.append(f"{prefix}.{field} must equal {state} slot statuses")
    enforce_official_comparison_operator_evidence_submission_path_file_state_summary(
        payload,
        statuses,
        errors,
        prefix,
    )
    status_state = payload.get("status_state")
    expected_state = "no_operator_evidence_needed"
    if statuses:
        if state_counts["rejected"]:
            expected_state = "blocked_invalid_submissions"
        elif state_counts["missing"] == 0:
            expected_state = "all_slots_submitted"
        elif state_counts["submitted"]:
            expected_state = "partially_submitted"
        else:
            expected_state = "waiting_for_submissions"
    if status_state in OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_SUBMISSION_STATUS_STATES:
        if status_state != expected_state:
            errors.append(f"{prefix}.status_state must be {expected_state}")
    if status_state in {"waiting_for_submissions", "partially_submitted", "blocked_invalid_submissions"}:
        if not payload.get("blocking_reasons"):
            errors.append(f"{prefix}.{status_state} requires blocking_reasons")
    enforce_official_comparison_operator_evidence_blocking_slot_summary_invariants(
        payload,
        statuses,
        errors,
        prefix,
    )
    submission_value_count = len(statuses) - state_counts["not_needed"]
    expected_filled_paths = sum(
        1
        for item in statuses
        if isinstance(item, dict)
        and item.get("slot_status") != "not_needed"
        and item.get("matched_evidence_paths")
    )
    expected_blank_paths = submission_value_count - expected_filled_paths
    filled_paths = payload.get("submission_values_filled_path_count")
    blank_paths = payload.get("submission_values_blank_path_count")
    minimum_required = payload.get(
        "submission_values_minimum_required_filled_path_count"
    )
    fill_state = payload.get("submission_values_fill_command_readiness_state")
    if isinstance(filled_paths, int) and isinstance(blank_paths, int):
        if filled_paths + blank_paths != submission_value_count:
            errors.append(
                f"{prefix}.submission_values_filled_path_count plus "
                "submission_values_blank_path_count must equal non-not-needed slots"
            )
        if filled_paths != expected_filled_paths:
            errors.append(
                f"{prefix}.submission_values_filled_path_count must equal "
                "slot_statuses with matched_evidence_paths"
            )
        if blank_paths != expected_blank_paths:
            errors.append(
                f"{prefix}.submission_values_blank_path_count must equal "
                "slot_statuses without matched_evidence_paths"
            )
    expected_minimum = 1 if submission_value_count else 0
    if isinstance(minimum_required, int) and minimum_required != expected_minimum:
        errors.append(
            f"{prefix}.submission_values_minimum_required_filled_path_count "
            f"must be {expected_minimum}"
        )
    if (
        isinstance(filled_paths, int)
        and isinstance(minimum_required, int)
        and fill_state
        in OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_SUBMISSION_VALUES_FILL_STATES
    ):
        expected_fill_state = (
            "no_submission_values_needed"
            if submission_value_count == 0
            else (
                "blocked_invalid_submission_values"
                if state_counts["rejected"]
                else (
                    "ready_to_fill_return_template"
                    if filled_paths >= minimum_required
                    else "blocked_empty_submission_values"
                )
            )
        )
        if fill_state != expected_fill_state:
            errors.append(
                f"{prefix}.submission_values_fill_command_readiness_state "
                f"must be {expected_fill_state}"
            )
    if fill_state in {
        "blocked_empty_submission_values",
        "blocked_invalid_submission_values",
    } and not payload.get("submission_values_fill_command_blocking_reasons"):
        errors.append(
            f"{prefix}.{fill_state} requires "
            "submission_values_fill_command_blocking_reasons"
        )
    if isinstance(payload.get("command_template_paths"), list):
        command_paths = set(payload.get("command_template_paths", []))
        required_commands = [
            "return_template_fill_from_status_command_template_path",
            "return_workflow_from_status_command_template_path",
            "release_workflow_from_status_command_template_path",
        ]
        for field in required_commands:
            command = payload.get(field)
            if command and command not in command_paths:
                errors.append(
                    f"{prefix}.command_template_paths must include {field}"
                )
        for index, item in enumerate(payload.get("command_sequence", [])):
            if not isinstance(item, dict):
                continue
            command = item.get("command_template_path")
            if command and command not in command_paths:
                errors.append(
                    f"{prefix}.command_template_paths must include "
                    f"command_sequence[{index}].command_template_path"
                )
        for index, item in enumerate(statuses):
            if not isinstance(item, dict):
                continue
            for path in item.get("command_template_paths", []):
                if path not in command_paths:
                    errors.append(
                        f"{prefix}.command_template_paths must include "
                        f"slot_statuses[{index}].command_template_paths"
                    )
    if isinstance(payload.get("evidence_paths"), list):
        evidence_paths = set(payload.get("evidence_paths", []))
        required_commands = [
            "return_template_fill_from_status_command_template_path",
            "return_workflow_from_status_command_template_path",
            "release_workflow_from_status_command_template_path",
            "submission_values_template_path",
            "submission_values_template_markdown_path",
            "submission_values_template_html_path",
        ]
        for field in required_commands:
            command = payload.get(field)
            if command and command not in evidence_paths:
                errors.append(f"{prefix}.evidence_paths must include {field}")
    sequence = payload.get("command_sequence")
    if isinstance(sequence, list):
        expected_step_ids = [
            "fill_return_template_from_status",
            "run_return_workflow_from_status",
            "rerun_release_workflow_from_status_return",
        ]
        actual_step_ids = [
            item.get("step_id") for item in sequence if isinstance(item, dict)
        ]
        if actual_step_ids != expected_step_ids:
            errors.append(f"{prefix}.command_sequence step_id order is invalid")
        if sequence and isinstance(sequence[0], dict):
            expected_first_step_state = (
                expected_official_operator_evidence_submission_fill_step_state(
                    payload.get("submission_values_fill_command_readiness_state")
                )
            )
            if sequence[0].get("step_state") != expected_first_step_state:
                errors.append(
                    f"{prefix}.command_sequence[0].step_state must be "
                    f"{expected_first_step_state}"
                )
        for expected_order, item in enumerate(sequence, start=1):
            if not isinstance(item, dict):
                continue
            if item.get("step_order") != expected_order:
                errors.append(
                    f"{prefix}.command_sequence[{expected_order - 1}].step_order "
                    f"must be {expected_order}"
                )
        seen_step_ids = set()
        for index, item in enumerate(sequence):
            if not isinstance(item, dict):
                continue
            for dependency in item.get("depends_on_step_ids", []):
                if dependency not in seen_step_ids:
                    errors.append(
                        f"{prefix}.command_sequence[{index}].depends_on_step_ids "
                        "must reference earlier steps"
                    )
            seen_step_ids.add(item.get("step_id"))
        enforce_official_comparison_operator_evidence_submission_command_sequence_contract(
            sequence,
            errors,
            f"{prefix}.command_sequence",
            {
                "fill_return_template_from_status": (
                    "return_template_fill_from_status_command_template_path",
                    payload.get("return_template_fill_from_status_command_template_path"),
                ),
                "run_return_workflow_from_status": (
                    "return_workflow_from_status_command_template_path",
                    payload.get("return_workflow_from_status_command_template_path"),
                ),
                "rerun_release_workflow_from_status_return": (
                    "release_workflow_from_status_command_template_path",
                    payload.get("release_workflow_from_status_command_template_path"),
                ),
            },
            {
                "run_return_workflow_from_status": "blocked",
                "rerun_release_workflow_from_status_return": "blocked",
            },
        )
    enforce_official_comparison_operator_evidence_fill_quickstart_invariants(
        payload,
        errors,
        prefix,
        "slot_statuses",
        (
            "status_state",
            "submission_values_fill_command_readiness_state",
            "submission_values_filled_path_count",
            "submission_values_blank_path_count",
        ),
        (
            "submission_values_template_path",
            "return_template_fill_from_status_command_template_path",
        ),
    )


def validate_official_comparison_operator_evidence_submission_values_template(
    payload,
    errors,
    prefix,
):
    require_fields(
        errors,
        payload,
        [
            "submission_status_report_path",
            "submission_checklist_path",
            "operator_evidence_return_template_path",
            "target_reference_version",
            "markdown_report_path",
            "html_report_path",
            "return_template_fill_from_status_command_template_path",
            "return_workflow_from_status_command_template_path",
            "release_workflow_from_status_command_template_path",
            "editable_fields",
            "path_editing_instructions",
            "slot_value_count",
            "submission_action_group_count",
            "submission_action_groups",
            "filled_path_count",
            "blank_path_count",
            "submission_completion_state",
            "full_submission_ready",
            "remaining_required_slot_count",
            "remaining_required_slot_ids",
            "submitted_required_slot_ids",
            "missing_required_slot_ids",
            "rejected_required_slot_ids",
            "expected_submission_path_exists_count",
            "expected_submission_path_missing_count",
            "expected_submission_path_not_applicable_count",
            "expected_submission_path_missing_slot_ids",
            "minimum_required_filled_path_count",
            "fill_command_readiness_state",
            "fill_command_blocking_reasons",
            "slot_values",
            "command_sequence",
            "next_actions",
            "evidence_paths",
        ],
        prefix,
    )
    require_non_negative_int(errors, payload.get("schema_version"), f"{prefix}.schema_version")
    for name in [
        "submission_status_report_path",
        "submission_checklist_path",
        "operator_evidence_return_template_path",
        "target_reference_version",
        "markdown_report_path",
        "html_report_path",
        "return_template_fill_from_status_command_template_path",
        "return_workflow_from_status_command_template_path",
        "release_workflow_from_status_command_template_path",
    ]:
        require_non_empty_string(errors, payload.get(name), f"{prefix}.{name}")
    require_non_negative_int(errors, payload.get("slot_value_count"), f"{prefix}.slot_value_count")
    require_non_negative_int(
        errors,
        payload.get("submission_action_group_count"),
        f"{prefix}.submission_action_group_count",
    )
    require_non_negative_int(errors, payload.get("filled_path_count"), f"{prefix}.filled_path_count")
    require_non_negative_int(errors, payload.get("blank_path_count"), f"{prefix}.blank_path_count")
    require_non_negative_int(
        errors,
        payload.get("remaining_required_slot_count"),
        f"{prefix}.remaining_required_slot_count",
    )
    require_non_negative_int(
        errors,
        payload.get("expected_submission_path_exists_count"),
        f"{prefix}.expected_submission_path_exists_count",
    )
    require_non_negative_int(
        errors,
        payload.get("expected_submission_path_missing_count"),
        f"{prefix}.expected_submission_path_missing_count",
    )
    require_non_negative_int(
        errors,
        payload.get("expected_submission_path_not_applicable_count"),
        f"{prefix}.expected_submission_path_not_applicable_count",
    )
    require_non_negative_int(
        errors,
        payload.get("minimum_required_filled_path_count"),
        f"{prefix}.minimum_required_filled_path_count",
    )
    if payload.get("fill_command_readiness_state") not in (
        OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_SUBMISSION_VALUES_FILL_STATES
    ):
        errors.append(
            f"{prefix}.fill_command_readiness_state is invalid: "
            f"{payload.get('fill_command_readiness_state')!r}"
        )
    if payload.get("submission_completion_state") not in (
        OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_SUBMISSION_COMPLETION_STATES
    ):
        errors.append(
            f"{prefix}.submission_completion_state is invalid: "
            f"{payload.get('submission_completion_state')!r}"
        )
    require_type(
        errors,
        payload.get("full_submission_ready"),
        bool,
        f"{prefix}.full_submission_ready",
    )
    require_type(errors, payload.get("slot_values"), list, f"{prefix}.slot_values")
    if isinstance(payload.get("slot_values"), list):
        for index, item in enumerate(payload["slot_values"]):
            validate_official_comparison_operator_evidence_submission_slot_value(
                item,
                errors,
                f"{prefix}.slot_values[{index}]",
            )
    require_type(
        errors,
        payload.get("submission_action_groups"),
        list,
        f"{prefix}.submission_action_groups",
    )
    if isinstance(payload.get("submission_action_groups"), list):
        for index, item in enumerate(payload["submission_action_groups"]):
            validate_official_comparison_operator_evidence_submission_action_group(
                item,
                errors,
                f"{prefix}.submission_action_groups[{index}]",
            )
    require_type(errors, payload.get("command_sequence"), list, f"{prefix}.command_sequence")
    if isinstance(payload.get("command_sequence"), list):
        for index, item in enumerate(payload["command_sequence"]):
            validate_official_comparison_operator_evidence_submission_command_step(
                item,
                errors,
                f"{prefix}.command_sequence[{index}]",
            )
    if "blocking_slot_summary" in payload:
        require_type(
            errors,
            payload.get("blocking_slot_summary"),
            list,
            f"{prefix}.blocking_slot_summary",
        )
    if isinstance(payload.get("blocking_slot_summary"), list):
        for index, item in enumerate(payload["blocking_slot_summary"]):
            validate_official_comparison_operator_evidence_blocking_slot_summary_item(
                item,
                errors,
                f"{prefix}.blocking_slot_summary[{index}]",
            )
    if "operator_fill_quickstart" in payload:
        validate_official_comparison_operator_evidence_fill_quickstart(
            payload.get("operator_fill_quickstart"),
            errors,
            f"{prefix}.operator_fill_quickstart",
        )
    for name in [
        "editable_fields",
        "path_editing_instructions",
        "fill_command_blocking_reasons",
        "expected_submission_path_missing_slot_ids",
        "remaining_required_slot_ids",
        "submitted_required_slot_ids",
        "missing_required_slot_ids",
        "rejected_required_slot_ids",
        "next_actions",
        "evidence_paths",
    ]:
        require_string_list(errors, payload.get(name), f"{prefix}.{name}")
    enforce_official_comparison_operator_evidence_submission_values_invariants(
        payload,
        errors,
        prefix,
    )


def validate_official_comparison_operator_evidence_submission_slot_value(
    item,
    errors,
    prefix,
):
    if not isinstance(item, dict):
        errors.append(f"{prefix} must be an object")
        return
    require_fields(
        errors,
        item,
        [
            "slot_id",
            "slot_status",
            "slot_type",
            "task_id",
            "title",
            "return_field",
            "engine_id",
            "benchmark_kind",
            "sample_set",
            "current_reference_version",
            "target_reference_version",
            "editable_fields",
            "path",
            "path_value_hint",
            "expected_submission_path",
            "expected_submission_path_state",
            "expected_submission_path_file_state",
            "expected_submission_path_note",
            "expected_manifest_types",
            "evidence_to_collect",
            "acceptance_criteria",
            "source_paths",
            "source_artifact_hint_paths",
            "command_template_paths",
            "command_templates",
            "missing_reasons",
            "rejection_reasons",
            "next_actions",
            "source_candidate_diagnostics",
            "metadata",
        ],
        prefix,
    )
    for name in ["slot_id", "slot_status", "slot_type", "task_id", "title", "return_field"]:
        require_non_empty_string(errors, item.get(name), f"{prefix}.{name}")
    for name in [
        "engine_id",
        "benchmark_kind",
        "sample_set",
        "current_reference_version",
        "target_reference_version",
    ]:
        require_type(errors, item.get(name), str, f"{prefix}.{name}")
    if isinstance(item.get("sample_set"), str):
        sample_set = item.get("sample_set", "").strip()
        if sample_set.startswith("[") and sample_set.endswith("]"):
            errors.append(f"{prefix}.sample_set must not use list literal formatting")
    require_type(errors, item.get("path"), str, f"{prefix}.path")
    require_non_empty_string(errors, item.get("path_value_hint"), f"{prefix}.path_value_hint")
    enforce_official_comparison_operator_evidence_expected_submission_path_contract(
        item,
        errors,
        prefix,
    )
    if item.get("slot_status") not in (
        OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_SUBMISSION_SLOT_STATUS_STATES
    ):
        errors.append(f"{prefix}.slot_status is invalid: {item.get('slot_status')!r}")
    if item.get("slot_type") not in (
        OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_SUBMISSION_SLOT_TYPES
    ):
        errors.append(f"{prefix}.slot_type is invalid: {item.get('slot_type')!r}")
    if item.get("return_field") not in {
        "reference_review_workflow_report_path",
        "run_bundle_manifest_paths",
    }:
        errors.append(f"{prefix}.return_field is invalid: {item.get('return_field')!r}")
    expected_path_value_hint = (
        expected_official_comparison_operator_evidence_submission_path_value_hint(
            item.get("return_field")
        )
    )
    if (
        expected_path_value_hint
        and isinstance(item.get("path_value_hint"), str)
        and item.get("path_value_hint") != expected_path_value_hint
    ):
        errors.append(
            f"{prefix}.path_value_hint must be {expected_path_value_hint!r}"
        )
    require_type(errors, item.get("metadata"), dict, f"{prefix}.metadata")
    enforce_official_comparison_operator_evidence_submission_manifest_types(
        item,
        errors,
        prefix,
    )
    enforce_official_comparison_operator_evidence_submission_slot_context(
        item,
        errors,
        prefix,
    )
    for name in [
        "editable_fields",
        "expected_manifest_types",
        "evidence_to_collect",
        "acceptance_criteria",
        "source_paths",
        "source_artifact_hint_paths",
        "command_template_paths",
        "command_templates",
        "missing_reasons",
        "rejection_reasons",
        "next_actions",
    ]:
        require_string_list(errors, item.get(name), f"{prefix}.{name}")
    if item.get("slot_status") == "submitted" and not item.get("path"):
        errors.append(f"{prefix}.submitted slot requires path")
    if item.get("slot_status") in {"missing", "rejected"}:
        if not item.get("expected_manifest_types"):
            errors.append(
                f"{prefix}.{item.get('slot_status')} slot requires "
                "expected_manifest_types"
            )
        if not item.get("evidence_to_collect"):
            errors.append(
                f"{prefix}.{item.get('slot_status')} slot requires "
                "evidence_to_collect"
            )
        if not item.get("acceptance_criteria"):
            errors.append(
                f"{prefix}.{item.get('slot_status')} slot requires "
                "acceptance_criteria"
            )
    if item.get("slot_status") == "missing" and not item.get("missing_reasons"):
        errors.append(f"{prefix}.missing slot requires missing_reasons")
    if item.get("slot_status") == "rejected" and not item.get("rejection_reasons"):
        errors.append(f"{prefix}.rejected slot requires rejection_reasons")
    validate_official_comparison_operator_evidence_source_candidate_diagnostics(
        item.get("source_candidate_diagnostics"),
        errors,
        f"{prefix}.source_candidate_diagnostics",
    )
    if item.get("source_paths") and not item.get("source_candidate_diagnostics"):
        errors.append(
            f"{prefix}.source_candidate_diagnostics must not be empty "
            "when source_paths exist"
        )
    expected_source_artifact_hints = (
        expected_official_comparison_operator_evidence_source_artifact_hint_paths(
            item
        )
    )
    if item.get("source_artifact_hint_paths") != expected_source_artifact_hints:
        errors.append(f"{prefix}.source_artifact_hint_paths must match source_paths")


def expected_official_comparison_operator_evidence_submission_path_value_hint(
    return_field,
):
    if return_field == "reference_review_workflow_report_path":
        return "Path to a reference_review_batch_workflow_report JSON file."
    if return_field == "run_bundle_manifest_paths":
        return "Path to an engine_run_bundle_manifest JSON file."
    return None


def official_comparison_command_parts(command):
    if not isinstance(command, str) or not command.strip():
        return []
    try:
        return shlex.split(command)
    except ValueError:
        return command.split()


def official_comparison_command_output_root(command):
    parts = official_comparison_command_parts(command)
    for index, part in enumerate(parts):
        if part == "--output-root" and index + 1 < len(parts):
            return parts[index + 1]
        if part.startswith("--output-root="):
            return part.split("=", 1)[1]
    return ""


def official_comparison_submission_output_command_template(item):
    if not isinstance(item, dict):
        return ""
    commands = item.get("command_templates")
    if not isinstance(commands, list):
        return ""
    markers = SUBMISSION_COMMAND_MARKERS_BY_RETURN_FIELD.get(
        item.get("return_field", ""),
        [],
    )
    for marker in markers:
        for command in commands:
            if isinstance(command, str) and marker in command:
                return command
    return ""


def expected_official_comparison_operator_evidence_submission_path_details(item):
    filename = SUBMISSION_OUTPUT_FILENAMES_BY_RETURN_FIELD.get(
        item.get("return_field", "") if isinstance(item, dict) else "",
        "",
    )
    command = official_comparison_submission_output_command_template(item)
    if not filename:
        return {
            "expected_submission_path": "",
            "expected_submission_path_state": "unsupported_return_field",
            "expected_submission_path_file_state": "not_applicable",
            "expected_submission_path_note": (
                "No expected submission manifest filename is defined for this return_field."
            ),
        }
    if not command:
        return {
            "expected_submission_path": "",
            "expected_submission_path_state": "no_submission_manifest_command_template",
            "expected_submission_path_file_state": "not_applicable",
            "expected_submission_path_note": (
                "No direct command template writes the submission manifest; "
                f"produce a {filename} that satisfies the acceptance criteria and "
                "paste that path into slot_values[].path."
            ),
        }
    output_root = official_comparison_command_output_root(command)
    if not output_root:
        return {
            "expected_submission_path": "",
            "expected_submission_path_state": "missing_output_root_in_submission_command",
            "expected_submission_path_file_state": "not_applicable",
            "expected_submission_path_note": (
                "The submission command template does not expose --output-root; "
                f"paste the generated {filename} path after the command succeeds."
            ),
        }
    expected_path = str(Path(output_root) / filename)
    return {
        "expected_submission_path": expected_path,
        "expected_submission_path_state": "known_from_command_template",
        "expected_submission_path_file_state": (
            "exists" if Path(expected_path).is_file() else "missing"
        ),
        "expected_submission_path_note": (
            "After the submission command succeeds, copy this path into "
            "slot_values[].path."
        ),
    }


def enforce_official_comparison_operator_evidence_expected_submission_path_contract(
    item,
    errors,
    prefix,
):
    require_non_empty_string(
        errors,
        item.get("expected_submission_path_state"),
        f"{prefix}.expected_submission_path_state",
    )
    require_non_empty_string(
        errors,
        item.get("expected_submission_path_note"),
        f"{prefix}.expected_submission_path_note",
    )
    require_non_empty_string(
        errors,
        item.get("expected_submission_path_file_state"),
        f"{prefix}.expected_submission_path_file_state",
    )
    require_type(
        errors,
        item.get("expected_submission_path"),
        str,
        f"{prefix}.expected_submission_path",
    )
    state = item.get("expected_submission_path_state")
    if (
        isinstance(state, str)
        and state
        and state
        not in OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_EXPECTED_SUBMISSION_PATH_STATES
    ):
        errors.append(
            f"{prefix}.expected_submission_path_state is invalid: {state!r}"
        )
    file_state = item.get("expected_submission_path_file_state")
    if (
        isinstance(file_state, str)
        and file_state
        and file_state
        not in OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_EXPECTED_SUBMISSION_PATH_FILE_STATES
    ):
        errors.append(
            f"{prefix}.expected_submission_path_file_state is invalid: {file_state!r}"
        )
    expected = expected_official_comparison_operator_evidence_submission_path_details(
        item
    )
    for field, value in expected.items():
        if item.get(field) != value:
            errors.append(f"{prefix}.{field} must be {value!r}")
    if (
        item.get("expected_submission_path_state") == "known_from_command_template"
        and not item.get("expected_submission_path")
    ):
        errors.append(
            f"{prefix}.expected_submission_path is required when "
            "expected_submission_path_state=known_from_command_template"
        )


def expected_official_comparison_operator_evidence_submission_path_file_state_summary(
    slots,
):
    counts = {
        "exists": 0,
        "missing": 0,
        "not_applicable": 0,
    }
    missing_slot_ids = []
    for slot in slots:
        if not isinstance(slot, dict):
            continue
        state = slot.get("expected_submission_path_file_state", "not_applicable")
        if state not in counts:
            state = "not_applicable"
        counts[state] += 1
        slot_id = slot.get("slot_id")
        if state == "missing" and isinstance(slot_id, str) and slot_id:
            missing_slot_ids.append(slot_id)
    return {
        "expected_submission_path_exists_count": counts["exists"],
        "expected_submission_path_missing_count": counts["missing"],
        "expected_submission_path_not_applicable_count": counts["not_applicable"],
        "expected_submission_path_missing_slot_ids": unique_non_empty_strings(
            missing_slot_ids
        ),
    }


def enforce_official_comparison_operator_evidence_submission_path_file_state_summary(
    payload,
    slots,
    errors,
    prefix,
):
    expected = (
        expected_official_comparison_operator_evidence_submission_path_file_state_summary(
            slots
        )
    )
    for field, value in expected.items():
        if payload.get(field) != value:
            errors.append(f"{prefix}.{field} must match expected_submission_path_file_state")


def validate_official_comparison_operator_evidence_source_candidate_diagnostics(
    value,
    errors,
    prefix,
):
    require_type(errors, value, list, prefix)
    if not isinstance(value, list):
        return
    for index, item in enumerate(value):
        item_prefix = f"{prefix}[{index}]"
        if not isinstance(item, dict):
            errors.append(f"{item_prefix} must be an object")
            continue
        require_fields(
            errors,
            item,
            [
                "path",
                "candidate_state",
                "manifest_type",
                "engine_id",
                "benchmark_kind",
                "reference_version",
                "benchmark_reference_version",
                "product_path_state",
                "runner_contract_dry_run_state",
                "benchmark_run_manifest_path",
                "reasons",
            ],
            item_prefix,
        )
        for name in [
            "path",
            "candidate_state",
            "manifest_type",
            "engine_id",
            "benchmark_kind",
            "reference_version",
            "benchmark_reference_version",
            "product_path_state",
            "runner_contract_dry_run_state",
            "benchmark_run_manifest_path",
        ]:
            require_type(errors, item.get(name), str, f"{item_prefix}.{name}")
        require_string_list(errors, item.get("reasons"), f"{item_prefix}.reasons")
        if item.get("candidate_state") not in (
            OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_SOURCE_CANDIDATE_STATES
        ):
            errors.append(
                f"{item_prefix}.candidate_state is invalid: "
                f"{item.get('candidate_state')!r}"
            )
        if item.get("candidate_state") != "usable_as_submission" and not item.get("reasons"):
            errors.append(f"{item_prefix}.non-usable candidate requires reasons")


def enforce_official_comparison_operator_evidence_submission_values_invariants(
    payload,
    errors,
    prefix,
):
    slot_values = payload.get("slot_values")
    if isinstance(slot_values, list) and payload.get("slot_value_count") != len(slot_values):
        errors.append(f"{prefix}.slot_value_count must equal slot_values length")
    if isinstance(slot_values, list):
        enforce_official_comparison_operator_evidence_completion_summary(
            payload,
            slot_values,
            errors,
            prefix,
        )
        enforce_official_comparison_operator_evidence_submission_action_group_invariants(
            payload,
            slot_values,
            "submission_action_group_count",
            "submission_action_groups",
            errors,
            prefix,
        )
        enforce_official_comparison_operator_evidence_submission_path_file_state_summary(
            payload,
            slot_values,
            errors,
            prefix,
        )
        seen_slot_ids = set()
        target_reference_version = payload.get("target_reference_version")
        for index, item in enumerate(slot_values):
            if not isinstance(item, dict):
                continue
            if (
                isinstance(target_reference_version, str)
                and target_reference_version
                and isinstance(item.get("target_reference_version"), str)
                and item.get("target_reference_version") != target_reference_version
            ):
                errors.append(
                    f"{prefix}.slot_values[{index}].target_reference_version "
                    "must match target_reference_version"
                )
            slot_id = item.get("slot_id")
            if not isinstance(slot_id, str) or not slot_id:
                continue
            if slot_id in seen_slot_ids:
                errors.append(
                    f"{prefix}.slot_values[{index}].slot_id must be unique: {slot_id}"
                )
            seen_slot_ids.add(slot_id)
        filled_path_count = sum(
            1
            for item in slot_values
            if isinstance(item, dict)
            and isinstance(item.get("path"), str)
            and item.get("path").strip()
        )
        blank_path_count = len(slot_values) - filled_path_count
        rejected_path_count = sum(
            1
            for item in slot_values
            if isinstance(item, dict)
            and item.get("slot_status") == "rejected"
            and isinstance(item.get("path"), str)
            and item.get("path").strip()
        )
        minimum_required = 1 if slot_values else 0
        expected_state = (
            "no_submission_values_needed"
            if not slot_values
            else (
                "blocked_invalid_submission_values"
                if rejected_path_count
                else (
                    "ready_to_fill_return_template"
                    if filled_path_count >= minimum_required
                    else "blocked_empty_submission_values"
                )
            )
        )
        if payload.get("filled_path_count") != filled_path_count:
            errors.append(f"{prefix}.filled_path_count must equal filled slot_values paths")
        if payload.get("blank_path_count") != blank_path_count:
            errors.append(f"{prefix}.blank_path_count must equal blank slot_values paths")
        if payload.get("minimum_required_filled_path_count") != minimum_required:
            errors.append(
                f"{prefix}.minimum_required_filled_path_count must be {minimum_required}"
            )
        if payload.get("fill_command_readiness_state") in {
            "blocked_empty_submission_values",
            "blocked_invalid_submission_values",
        }:
            if not payload.get("fill_command_blocking_reasons"):
                errors.append(
                    f"{prefix}.{payload.get('fill_command_readiness_state')} requires "
                    "fill_command_blocking_reasons"
                )
        if payload.get("fill_command_readiness_state") in (
            OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_SUBMISSION_VALUES_FILL_STATES
        ):
            if payload.get("fill_command_readiness_state") != expected_state:
                errors.append(
                    f"{prefix}.fill_command_readiness_state must be {expected_state}"
                )
    editable_fields = payload.get("editable_fields")
    if isinstance(editable_fields, list) and editable_fields != ["slot_values[].path"]:
        errors.append(f"{prefix}.editable_fields must be ['slot_values[].path']")
    path_editing_instructions = payload.get("path_editing_instructions")
    if isinstance(path_editing_instructions, list):
        instruction_text = "\n".join(
            value for value in path_editing_instructions if isinstance(value, str)
        )
        for field in [
            "target_reference_version",
            "operator_evidence_return_template_path",
        ]:
            if field not in instruction_text:
                errors.append(
                    f"{prefix}.path_editing_instructions must mention {field}"
                )
    if isinstance(slot_values, list):
        for index, item in enumerate(slot_values):
            if not isinstance(item, dict):
                continue
            item_editable_fields = item.get("editable_fields")
            if isinstance(item_editable_fields, list) and item_editable_fields != ["path"]:
                errors.append(
                    f"{prefix}.slot_values[{index}].editable_fields must be ['path']"
                )
        enforce_official_comparison_operator_evidence_blocking_slot_summary_invariants(
            payload,
            slot_values,
            errors,
            prefix,
        )
    if isinstance(payload.get("evidence_paths"), list):
        evidence_paths = set(payload.get("evidence_paths", []))
        for field in [
            "submission_status_report_path",
            "submission_checklist_path",
            "operator_evidence_return_template_path",
            "return_template_fill_from_status_command_template_path",
            "return_workflow_from_status_command_template_path",
            "release_workflow_from_status_command_template_path",
        ]:
            path = payload.get(field)
            if path and path not in evidence_paths:
                errors.append(f"{prefix}.evidence_paths must include {field}")
    sequence = payload.get("command_sequence")
    if isinstance(sequence, list):
        expected_step_ids = [
            "fill_return_template_from_status",
            "run_return_workflow_from_status",
            "rerun_release_workflow_from_status_return",
        ]
        actual_step_ids = [
            item.get("step_id") for item in sequence if isinstance(item, dict)
        ]
        if actual_step_ids != expected_step_ids:
            errors.append(f"{prefix}.command_sequence step_id order is invalid")
        if sequence and isinstance(sequence[0], dict):
            expected_first_step_state = (
                expected_official_operator_evidence_submission_fill_step_state(
                    payload.get("fill_command_readiness_state")
                )
            )
            if sequence[0].get("step_state") != expected_first_step_state:
                errors.append(
                    f"{prefix}.command_sequence[0].step_state must be "
                    f"{expected_first_step_state}"
                )
        for expected_order, item in enumerate(sequence, start=1):
            if not isinstance(item, dict):
                continue
            if item.get("step_order") != expected_order:
                errors.append(
                    f"{prefix}.command_sequence[{expected_order - 1}].step_order "
                    f"must be {expected_order}"
                )
        seen_step_ids = set()
        for index, item in enumerate(sequence):
            if not isinstance(item, dict):
                continue
            for dependency in item.get("depends_on_step_ids", []):
                if dependency not in seen_step_ids:
                    errors.append(
                        f"{prefix}.command_sequence[{index}].depends_on_step_ids "
                        "must reference earlier steps"
                    )
            seen_step_ids.add(item.get("step_id"))
        enforce_official_comparison_operator_evidence_submission_command_sequence_contract(
            sequence,
            errors,
            f"{prefix}.command_sequence",
            {
                "fill_return_template_from_status": (
                    "return_template_fill_from_status_command_template_path",
                    payload.get("return_template_fill_from_status_command_template_path"),
                ),
                "run_return_workflow_from_status": (
                    "return_workflow_from_status_command_template_path",
                    payload.get("return_workflow_from_status_command_template_path"),
                ),
                "rerun_release_workflow_from_status_return": (
                    "release_workflow_from_status_command_template_path",
                    payload.get("release_workflow_from_status_command_template_path"),
                ),
            },
            {
                "run_return_workflow_from_status": "blocked",
                "rerun_release_workflow_from_status_return": "blocked",
            },
        )
    status_report = read_linked_manifest_if_available(
        payload,
        "submission_status_report_path",
        "official_comparison_operator_evidence_submission_status_report",
        errors,
        prefix,
    )
    if isinstance(status_report, dict):
        for value_field, status_field in [
            (
                "return_workflow_from_status_command_template_path",
                "return_workflow_from_status_command_template_path",
            ),
            (
                "release_workflow_from_status_command_template_path",
                "release_workflow_from_status_command_template_path",
            ),
            ("command_sequence", "command_sequence"),
        ]:
            if (
                value_field in payload
                and status_field in status_report
                and payload.get(value_field) != status_report.get(status_field)
            ):
                errors.append(
                    f"{prefix}.{value_field} must match "
                    f"submission_status_report.{status_field}"
                )
        status_slots = status_report.get("slot_statuses")
        if isinstance(slot_values, list) and isinstance(status_slots, list):
            status_slot_by_id = {
                item.get("slot_id"): item
                for item in status_slots
                if isinstance(item, dict) and isinstance(item.get("slot_id"), str)
            }
            for index, item in enumerate(slot_values):
                if not isinstance(item, dict):
                    continue
                source = status_slot_by_id.get(item.get("slot_id"))
                if not isinstance(source, dict):
                    continue
                source_metadata = (
                    source.get("metadata", {})
                    if isinstance(source.get("metadata"), dict)
                    else {}
                )
                if item.get("metadata") != source_metadata:
                    errors.append(
                        f"{prefix}.slot_values[{index}].metadata must match "
                        "submission_status_report.slot_statuses"
                    )
    if "operator_fill_quickstart" in payload:
        enforce_official_comparison_operator_evidence_fill_quickstart_invariants(
            payload,
            errors,
            prefix,
            "slot_values",
            (
                "",
                "fill_command_readiness_state",
                "filled_path_count",
                "blank_path_count",
            ),
            None,
        )


def validate_official_comparison_operator_evidence_task_result(item, errors, prefix):
    if not isinstance(item, dict):
        errors.append(f"{prefix} must be an object")
        return
    require_fields(
        errors,
        item,
        [
            "task_id",
            "title",
            "state",
            "request_state",
            "adoption_item_ids",
            "return_fields",
            "provided_return_fields",
            "missing_return_fields",
            "evidence_to_return",
            "acceptance_criteria",
            "reasons",
            "next_action",
            "source_paths",
            "evidence_paths",
            "command_template_paths",
        ],
        prefix,
    )
    if item.get("state") not in OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_ITEM_STATES:
        errors.append(f"{prefix}.state is invalid: {item.get('state')!r}")
    request_state = item.get("request_state")
    if request_state:
        if request_state not in OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_REQUEST_ITEM_STATES:
            errors.append(f"{prefix}.request_state is invalid: {request_state!r}")
    for name in ["task_id", "title", "state", "next_action"]:
        require_non_empty_string(errors, item.get(name), f"{prefix}.{name}")
    for name in [
        "adoption_item_ids",
        "return_fields",
        "provided_return_fields",
        "missing_return_fields",
        "evidence_to_return",
        "acceptance_criteria",
        "reasons",
        "source_paths",
        "evidence_paths",
        "command_template_paths",
    ]:
        require_string_list(errors, item.get(name), f"{prefix}.{name}")
    if item.get("state") in {"missing", "rejected"} and not item.get("reasons"):
        errors.append(f"{prefix}.{item.get('state')} requires reasons")
    if item.get("request_state") == "requested":
        if not item.get("return_fields"):
            errors.append(f"{prefix}.requested item requires return_fields")
        if not item.get("evidence_to_return"):
            errors.append(f"{prefix}.requested item requires evidence_to_return")
        if not item.get("acceptance_criteria"):
            errors.append(f"{prefix}.requested item requires acceptance_criteria")
    return_fields = item.get("return_fields")
    provided_fields = item.get("provided_return_fields")
    missing_fields = item.get("missing_return_fields")
    if (
        isinstance(return_fields, list)
        and isinstance(provided_fields, list)
        and isinstance(missing_fields, list)
    ):
        provided = set(provided_fields)
        missing = set(missing_fields)
        if provided & missing:
            errors.append(f"{prefix}.provided_return_fields overlaps missing_return_fields")
        if provided | missing != set(return_fields):
            errors.append(
                f"{prefix}.provided_return_fields and missing_return_fields must cover return_fields"
            )


def validate_official_comparison_operator_evidence_return_field_status(item, errors, prefix):
    if not isinstance(item, dict):
        errors.append(f"{prefix} must be an object")
        return
    require_fields(
        errors,
        item,
        [
            "field",
            "provided",
            "value_count",
            "values",
            "task_ids",
            "requested_task_ids",
            "provided_task_ids",
            "missing_task_ids",
            "adoption_item_ids",
            "source_paths",
            "evidence_to_return",
            "acceptance_criteria",
            "next_actions",
            "command_template_paths",
        ],
        prefix,
    )
    require_non_empty_string(errors, item.get("field"), f"{prefix}.field")
    if "value_type" in item:
        require_non_empty_string(errors, item.get("value_type"), f"{prefix}.value_type")
        if item.get("value_type") not in {"path", "path_list", "string"}:
            errors.append(f"{prefix}.value_type is invalid: {item.get('value_type')!r}")
    if "allow_multiple" in item:
        require_type(errors, item.get("allow_multiple"), bool, f"{prefix}.allow_multiple")
    if "expected_manifest_types" in item:
        require_string_list(
            errors,
            item.get("expected_manifest_types"),
            f"{prefix}.expected_manifest_types",
        )
    if "expected_value" in item:
        require_type(errors, item.get("expected_value"), str, f"{prefix}.expected_value")
    if "resolved_expected_value" in item:
        require_type(
            errors,
            item.get("resolved_expected_value"),
            str,
            f"{prefix}.resolved_expected_value",
        )
    if "value_contract_state" in item:
        require_non_empty_string(
            errors,
            item.get("value_contract_state"),
            f"{prefix}.value_contract_state",
        )
        if item.get("value_contract_state") not in (
            OFFICIAL_COMPARISON_RETURN_FIELD_VALUE_CONTRACT_STATES
        ):
            errors.append(
                f"{prefix}.value_contract_state is invalid: "
                f"{item.get('value_contract_state')!r}"
            )
    if "value_contract_errors" in item:
        require_string_list(
            errors,
            item.get("value_contract_errors"),
            f"{prefix}.value_contract_errors",
        )
    if ("value_contract_state" in item) != ("value_contract_errors" in item):
        errors.append(
            f"{prefix}.value_contract_state and value_contract_errors must appear together"
        )
    if "field_resolution_state" in item:
        require_non_empty_string(
            errors,
            item.get("field_resolution_state"),
            f"{prefix}.field_resolution_state",
        )
        if item.get("field_resolution_state") not in (
            OFFICIAL_COMPARISON_RETURN_FIELD_RESOLUTION_STATES
        ):
            errors.append(
                f"{prefix}.field_resolution_state is invalid: "
                f"{item.get('field_resolution_state')!r}"
            )
    require_type(errors, item.get("provided"), bool, f"{prefix}.provided")
    require_non_negative_int(errors, item.get("value_count"), f"{prefix}.value_count")
    for name in [
        "values",
        "task_ids",
        "requested_task_ids",
        "provided_task_ids",
        "missing_task_ids",
        "adoption_item_ids",
        "source_paths",
        "evidence_to_return",
        "acceptance_criteria",
        "next_actions",
        "command_template_paths",
    ]:
        require_string_list(errors, item.get(name), f"{prefix}.{name}")
    for name in [
        "accepted_evidence_task_ids",
        "missing_evidence_task_ids",
        "rejected_evidence_task_ids",
        "not_needed_evidence_task_ids",
        "blocked_evidence_task_ids",
    ]:
        if name in item:
            require_string_list(errors, item.get(name), f"{prefix}.{name}")
    if isinstance(item.get("values"), list) and item.get("value_count") != len(item["values"]):
        errors.append(f"{prefix}.value_count must equal values length")
    if "value_contract_state" in item and "value_contract_errors" in item:
        state = item.get("value_contract_state")
        contract_errors = item.get("value_contract_errors")
        if item.get("provided") is False and state != "missing":
            errors.append(f"{prefix}.provided=false requires value_contract_state=missing")
        if state == "missing" and item.get("provided") is True:
            errors.append(f"{prefix}.value_contract_state=missing requires provided=false")
        if state == "valid" and contract_errors:
            errors.append(f"{prefix}.value_contract_state=valid requires empty value_contract_errors")
        if state == "invalid" and not contract_errors:
            errors.append(f"{prefix}.value_contract_state=invalid requires value_contract_errors")
    if isinstance(item.get("task_ids"), list):
        task_ids = set(item.get("task_ids", []))
        provided_ids = set(item.get("provided_task_ids", []))
        missing_ids = set(item.get("missing_task_ids", []))
        if provided_ids & missing_ids:
            errors.append(f"{prefix}.provided_task_ids overlaps missing_task_ids")
        if provided_ids | missing_ids != task_ids:
            errors.append(f"{prefix}.provided_task_ids and missing_task_ids must cover task_ids")
        requested_ids = set(item.get("requested_task_ids", []))
        if not requested_ids.issubset(task_ids):
            errors.append(f"{prefix}.requested_task_ids must be a subset of task_ids")
        if item.get("provided") is True and missing_ids:
            errors.append(f"{prefix}.provided=true requires empty missing_task_ids")
        if item.get("provided") is False and provided_ids:
            errors.append(f"{prefix}.provided=false requires empty provided_task_ids")


def return_field_resolution_state_for(accepted, missing, rejected, not_needed):
    if not (accepted or missing or rejected or not_needed):
        return "no_tasks"
    if not (missing or rejected):
        if accepted:
            return "accepted"
        return "not_needed"
    if accepted or not_needed:
        return "partially_accepted"
    if rejected:
        return "rejected"
    return "missing"


def compare_optional_return_field_task_ids(
    errors,
    prefix,
    field_statuses,
    field_name,
    expected_by_field,
):
    actual_by_field = {
        item.get("field", ""): set(item.get(field_name, []))
        for item in field_statuses
        if isinstance(item, dict) and field_name in item
    }
    if actual_by_field and actual_by_field != expected_by_field:
        errors.append(
            f"{prefix}.return_field_statuses {field_name} "
            "must match operator_evidence_task_results"
        )


def return_field_task_verdicts_apply_to_field(field_status):
    return not (
        field_status.get("field") == "target_reference_version"
        and field_status.get("value_type") == "string"
        and field_status.get("provided") is True
        and field_status.get("value_contract_state") in {"valid", "unchecked"}
    )


def return_field_status_blocks_adoption(field_status):
    if field_status.get("value_contract_state") in {"missing", "invalid"}:
        return True
    if field_status.get("provided") is False:
        return True
    if not return_field_task_verdicts_apply_to_field(field_status):
        return False
    if field_status.get("missing_task_ids") or field_status.get("missing_evidence_task_ids"):
        return True
    return bool(field_status.get("rejected_evidence_task_ids"))


def return_blocker_summary_state_for(field_status, blocked_adoption_item_ids):
    if blocked_adoption_item_ids:
        return "blocking_adoption"
    if field_status.get("value_contract_state") in {"missing", "invalid"}:
        return "field_contract_blocked"
    if return_field_task_verdicts_apply_to_field(field_status) and (
        field_status.get("missing_task_ids")
        or field_status.get("missing_evidence_task_ids")
        or field_status.get("rejected_evidence_task_ids")
    ):
        return "field_verdict_blocked"
    if (
        field_status.get("provided") is True
        and field_status.get("value_contract_state") in {"valid", "unchecked"}
    ):
        return "not_blocking"
    if field_status.get("field_resolution_state") in {"accepted", "not_needed"}:
        return "not_blocking"
    return "unknown"


def expected_operator_evidence_return_blocker_summary(payload):
    task_results = payload.get("operator_evidence_task_results", [])
    tasks_by_id = {}
    if isinstance(task_results, list):
        tasks_by_id = {
            item.get("task_id", ""): item
            for item in task_results
            if isinstance(item, dict)
        }
    result = []
    field_statuses = payload.get("return_field_statuses", [])
    if not isinstance(field_statuses, list):
        return result
    for status in field_statuses:
        if not isinstance(status, dict):
            continue
        blocks_adoption = return_field_status_blocks_adoption(status)
        blocked_task_ids = release_stable_string_unique(
            release_string_list_or_empty(status.get("missing_task_ids", []))
            + release_string_list_or_empty(status.get("missing_evidence_task_ids", []))
            + release_string_list_or_empty(status.get("rejected_evidence_task_ids", []))
        )
        if not blocks_adoption:
            blocked_task_ids = []
        if blocks_adoption and not blocked_task_ids:
            blocked_task_ids = release_stable_string_unique(
                release_string_list_or_empty(status.get("task_ids", []))
            )
        blocked_tasks = [
            tasks_by_id[task_id]
            for task_id in blocked_task_ids
            if task_id in tasks_by_id
        ]
        blocked_adoption_item_ids = release_stable_string_unique(
            item_id
            for task in blocked_tasks
            for item_id in release_string_list_or_empty(
                task.get("adoption_item_ids", [])
            )
        )
        result.append({
            "field": status.get("field", ""),
            "summary_state": return_blocker_summary_state_for(
                status,
                blocked_adoption_item_ids,
            ),
            "provided": status.get("provided") is True,
            "value_contract_state": status.get("value_contract_state", ""),
            "field_resolution_state": status.get("field_resolution_state", ""),
            "related_adoption_item_ids": release_stable_string_unique(
                release_string_list_or_empty(status.get("adoption_item_ids", []))
            ),
            "blocked_adoption_item_ids": blocked_adoption_item_ids,
            "blocked_adoption_item_titles": [],
            "remediation_task_ids": blocked_task_ids if blocks_adoption else [],
            "accepted_evidence_task_ids": release_stable_string_unique(
                release_string_list_or_empty(status.get("accepted_evidence_task_ids", []))
            ),
            "missing_evidence_task_ids": release_stable_string_unique(
                release_string_list_or_empty(status.get("missing_evidence_task_ids", []))
            ),
            "rejected_evidence_task_ids": release_stable_string_unique(
                release_string_list_or_empty(status.get("rejected_evidence_task_ids", []))
            ),
            "blocked_evidence_task_ids": release_stable_string_unique(
                release_string_list_or_empty(status.get("blocked_evidence_task_ids", []))
            ),
            "value_contract_errors": release_stable_string_unique(
                release_string_list_or_empty(status.get("value_contract_errors", []))
            ),
            "evidence_to_return": release_stable_string_unique(
                release_string_list_or_empty(status.get("evidence_to_return", []))
            ),
            "acceptance_criteria": release_stable_string_unique(
                release_string_list_or_empty(status.get("acceptance_criteria", []))
            ),
            "command_template_paths": release_stable_string_unique(
                release_string_list_or_empty(status.get("command_template_paths", []))
            ),
            "next_actions": release_stable_string_unique(
                release_string_list_or_empty(status.get("next_actions", []))
            ),
        })
    return result


def enforce_official_comparison_operator_evidence_return_workflow_invariants(payload, errors, prefix):
    return_state = payload.get("return_state")
    intake_ready = payload.get("operator_evidence_ready_to_rerun_preflight")
    resume_ready = payload.get("preflight_resume_ready_to_rerun")
    target_reference_version = payload.get("target_reference_version")
    items = payload.get("operator_evidence_items") or []
    task_results = payload.get("operator_evidence_task_results") or []
    field_statuses = payload.get("return_field_statuses") or []
    slot_values = payload.get("submission_slot_values")
    if isinstance(slot_values, list):
        enforce_official_comparison_operator_evidence_submission_slot_value_uniqueness(
            slot_values,
            errors,
            f"{prefix}.submission_slot_values",
        )
        reference_slot_paths = [
            item.get("path")
            for item in slot_values
            if isinstance(item, dict)
            and item.get("return_field") == "reference_review_workflow_report_path"
        ]
        for path in reference_slot_paths:
            if path != payload.get("reference_review_workflow_report_path"):
                errors.append(
                    f"{prefix}.submission_slot_values reference path must match "
                    "reference_review_workflow_report_path"
                )
        run_bundle_paths = set(payload.get("run_bundle_manifest_paths", []))
        for item in slot_values:
            if not isinstance(item, dict):
                continue
            if item.get("return_field") != "run_bundle_manifest_paths":
                continue
            if item.get("path") not in run_bundle_paths:
                errors.append(
                    f"{prefix}.submission_slot_values run bundle path must be in "
                    "run_bundle_manifest_paths"
                )
    if isinstance(items, list):
        accepted_count = sum(
            1 for item in items
            if isinstance(item, dict) and item.get("state") == "accepted"
        )
        missing_count = sum(
            1 for item in items
            if isinstance(item, dict) and item.get("state") == "missing"
        )
        rejected_count = sum(
            1 for item in items
            if isinstance(item, dict) and item.get("state") == "rejected"
        )
        not_needed_count = sum(
            1 for item in items
            if isinstance(item, dict) and item.get("state") == "not_needed"
        )
        if payload.get("operator_evidence_accepted_item_count") != accepted_count:
            errors.append(
                f"{prefix}.operator_evidence_accepted_item_count must equal accepted items"
            )
        if payload.get("operator_evidence_missing_item_count") != missing_count:
            errors.append(
                f"{prefix}.operator_evidence_missing_item_count must equal missing items"
            )
        if payload.get("operator_evidence_rejected_item_count") != rejected_count:
            errors.append(
                f"{prefix}.operator_evidence_rejected_item_count must equal rejected items"
            )
        if accepted_count + missing_count + rejected_count + not_needed_count != len(items):
            errors.append(f"{prefix}.operator_evidence item states must account for every item")
        if items:
            expected_ready = missing_count == 0 and rejected_count == 0
            if intake_ready is not expected_ready:
                errors.append(
                    f"{prefix}.operator_evidence_ready_to_rerun_preflight "
                    "must reflect accepted/not_needed items only"
                )
    if isinstance(items, list) and isinstance(task_results, list):
        item_states = {
            item.get("task_id", ""): item.get("state", "")
            for item in items
            if isinstance(item, dict)
        }
        result_states = {
            item.get("task_id", ""): item.get("state", "")
            for item in task_results
            if isinstance(item, dict)
        }
        if item_states != result_states:
            errors.append(
                f"{prefix}.operator_evidence_task_results must match operator_evidence_items task states"
            )
        item_details = {
            item.get("task_id", ""): {
                "state": item.get("state", ""),
                "reasons": item.get("reasons", []),
                "next_action": item.get("next_action", ""),
                "evidence_paths": item.get("evidence_paths", []),
            }
            for item in items
            if isinstance(item, dict)
        }
        result_details = {
            item.get("task_id", ""): {
                "state": item.get("state", ""),
                "reasons": item.get("reasons", []),
                "next_action": item.get("next_action", ""),
                "evidence_paths": item.get("evidence_paths", []),
            }
            for item in task_results
            if isinstance(item, dict)
        }
        if item_details != result_details:
            errors.append(
                f"{prefix}.operator_evidence_task_results must match operator_evidence_items task details"
            )
    if isinstance(task_results, list) and isinstance(field_statuses, list):
        expected_tasks_by_field = {}
        expected_requested_tasks_by_field = {}
        expected_adoption_items_by_field = {}
        expected_accepted_tasks_by_field = {}
        expected_missing_tasks_by_field = {}
        expected_rejected_tasks_by_field = {}
        expected_not_needed_tasks_by_field = {}
        expected_blocked_tasks_by_field = {}
        expected_resolution_state_by_field = {}
        for item in task_results:
            if not isinstance(item, dict):
                continue
            task_id = item.get("task_id", "")
            for field in item.get("return_fields", []):
                expected_tasks_by_field.setdefault(field, set()).add(task_id)
                if item.get("request_state") == "requested":
                    expected_requested_tasks_by_field.setdefault(field, set()).add(task_id)
                expected_adoption_items_by_field.setdefault(field, set()).update(
                    item.get("adoption_item_ids", [])
                )
                state = item.get("state")
                if state == "accepted":
                    expected_accepted_tasks_by_field.setdefault(field, set()).add(task_id)
                elif state == "missing":
                    expected_missing_tasks_by_field.setdefault(field, set()).add(task_id)
                elif state == "rejected":
                    expected_rejected_tasks_by_field.setdefault(field, set()).add(task_id)
                elif state == "not_needed":
                    expected_not_needed_tasks_by_field.setdefault(field, set()).add(task_id)
        for field in expected_tasks_by_field:
            accepted = expected_accepted_tasks_by_field.get(field, set())
            missing = expected_missing_tasks_by_field.get(field, set())
            rejected = expected_rejected_tasks_by_field.get(field, set())
            not_needed = expected_not_needed_tasks_by_field.get(field, set())
            expected_accepted_tasks_by_field.setdefault(field, set())
            expected_missing_tasks_by_field.setdefault(field, set())
            expected_rejected_tasks_by_field.setdefault(field, set())
            expected_not_needed_tasks_by_field.setdefault(field, set())
            expected_blocked_tasks_by_field[field] = missing | rejected
            expected_resolution_state_by_field[field] = (
                return_field_resolution_state_for(accepted, missing, rejected, not_needed)
            )
        actual_tasks_by_field = {
            item.get("field", ""): set(item.get("task_ids", []))
            for item in field_statuses
            if isinstance(item, dict)
        }
        actual_requested_tasks_by_field = {
            item.get("field", ""): set(item.get("requested_task_ids", []))
            for item in field_statuses
            if isinstance(item, dict)
        }
        actual_adoption_items_by_field = {
            item.get("field", ""): set(item.get("adoption_item_ids", []))
            for item in field_statuses
            if isinstance(item, dict)
        }
        if actual_tasks_by_field != expected_tasks_by_field:
            errors.append(
                f"{prefix}.return_field_statuses must match operator_evidence_task_results return_fields"
            )
        if actual_requested_tasks_by_field != expected_requested_tasks_by_field:
            errors.append(
                f"{prefix}.return_field_statuses requested_task_ids must match operator_evidence_task_results"
            )
        if actual_adoption_items_by_field != expected_adoption_items_by_field:
            errors.append(
                f"{prefix}.return_field_statuses adoption_item_ids must match operator_evidence_task_results"
            )
        compare_optional_return_field_task_ids(
            errors,
            prefix,
            field_statuses,
            "accepted_evidence_task_ids",
            expected_accepted_tasks_by_field,
        )
        compare_optional_return_field_task_ids(
            errors,
            prefix,
            field_statuses,
            "missing_evidence_task_ids",
            expected_missing_tasks_by_field,
        )
        compare_optional_return_field_task_ids(
            errors,
            prefix,
            field_statuses,
            "rejected_evidence_task_ids",
            expected_rejected_tasks_by_field,
        )
        compare_optional_return_field_task_ids(
            errors,
            prefix,
            field_statuses,
            "not_needed_evidence_task_ids",
            expected_not_needed_tasks_by_field,
        )
        compare_optional_return_field_task_ids(
            errors,
            prefix,
            field_statuses,
            "blocked_evidence_task_ids",
            expected_blocked_tasks_by_field,
        )
        actual_resolution_state_by_field = {
            item.get("field", ""): item.get("field_resolution_state", "")
            for item in field_statuses
            if isinstance(item, dict) and "field_resolution_state" in item
        }
        if (
            actual_resolution_state_by_field
            and actual_resolution_state_by_field != expected_resolution_state_by_field
        ):
            errors.append(
                f"{prefix}.return_field_statuses field_resolution_state "
                "must match operator_evidence_task_results"
            )
        for item in field_statuses:
            if not isinstance(item, dict):
                continue
            if item.get("field") != "target_reference_version":
                continue
            values = item.get("values")
            if (
                isinstance(values, list)
                and isinstance(target_reference_version, str)
                and target_reference_version
                and values != [target_reference_version]
            ):
                errors.append(
                    f"{prefix}.return_field_statuses target_reference_version "
                    "values must match target_reference_version"
                )
        if isinstance(payload.get("return_blocker_summary"), list):
            expected_summary = expected_operator_evidence_return_blocker_summary(payload)
            if payload.get("return_blocker_summary") != expected_summary:
                errors.append(
                    f"{prefix}.return_blocker_summary must match "
                    "return_field_statuses and operator_evidence_task_results"
                )
    if return_state == "ready_to_rerun_preflight":
        if intake_ready is not True or resume_ready is not True:
            errors.append(
                f"{prefix}.ready_to_rerun_preflight requires intake and resume ready"
            )
        if not payload.get("preflight_rerun_command"):
            errors.append(f"{prefix}.ready_to_rerun_preflight requires preflight_rerun_command")
    if return_state == "blocked_operator_evidence":
        if resume_ready is True:
            errors.append(f"{prefix}.blocked_operator_evidence requires preflight_resume_ready_to_rerun=false")
        if not payload.get("blocking_reasons"):
            errors.append(f"{prefix}.blocked_operator_evidence requires blocking_reasons")
    if return_state == "no_operator_evidence_needed":
        if payload.get("operator_evidence_intake_state") != "no_handoff_needed":
            errors.append(
                f"{prefix}.no_operator_evidence_needed requires operator_evidence_intake_state=no_handoff_needed"
            )
        if resume_ready is True:
            errors.append(f"{prefix}.no_operator_evidence_needed requires preflight_resume_ready_to_rerun=false")


def validate_official_comparison_preflight_resume_plan(payload, errors, prefix):
    require_fields(
        errors,
        payload,
        [
            "plan_state",
            "ready_to_rerun_preflight",
            "intake_report_path",
            "handoff_report_path",
            "source_workflow_report_path",
            "target_reference_version",
            "reference_manifest_path",
            "run_bundle_manifest_paths",
            "required_engine_ids",
            "min_gold_samples",
            "min_gold_duration_minutes",
            "preflight_output_root",
            "rerun_command",
            "blocking_reasons",
            "next_actions",
            "evidence_paths",
            "markdown_report_path",
            "html_report_path",
        ],
        prefix,
    )
    plan_state = payload.get("plan_state")
    if plan_state not in OFFICIAL_COMPARISON_PREFLIGHT_RESUME_PLAN_STATES:
        errors.append(f"{prefix}.plan_state is invalid: {plan_state!r}")
    require_type(
        errors,
        payload.get("ready_to_rerun_preflight"),
        bool,
        f"{prefix}.ready_to_rerun_preflight",
    )
    for name in [
        "intake_report_path",
        "handoff_report_path",
        "source_workflow_report_path",
        "target_reference_version",
        "preflight_output_root",
        "markdown_report_path",
        "html_report_path",
    ]:
        require_non_empty_string(errors, payload.get(name), f"{prefix}.{name}")
    require_type(errors, payload.get("reference_manifest_path"), str, f"{prefix}.reference_manifest_path")
    require_non_negative_int(errors, payload.get("min_gold_samples"), f"{prefix}.min_gold_samples")
    require_non_negative_number(
        errors,
        payload.get("min_gold_duration_minutes"),
        f"{prefix}.min_gold_duration_minutes",
    )
    require_type(errors, payload.get("rerun_command"), str, f"{prefix}.rerun_command")
    for name in [
        "run_bundle_manifest_paths",
        "required_engine_ids",
        "blocking_reasons",
        "next_actions",
        "evidence_paths",
    ]:
        require_string_list(errors, payload.get(name), f"{prefix}.{name}")
    enforce_official_comparison_preflight_resume_plan_invariants(payload, errors, prefix)


def enforce_official_comparison_preflight_resume_plan_invariants(payload, errors, prefix):
    plan_state = payload.get("plan_state")
    ready = payload.get("ready_to_rerun_preflight")
    if plan_state == "ready_to_rerun_preflight":
        if ready is not True:
            errors.append(f"{prefix}.ready_to_rerun_preflight state requires ready_to_rerun_preflight=true")
        if not payload.get("rerun_command"):
            errors.append(f"{prefix}.ready_to_rerun_preflight state requires rerun_command")
        if not payload.get("reference_manifest_path"):
            errors.append(f"{prefix}.ready_to_rerun_preflight state requires reference_manifest_path")
        if not payload.get("run_bundle_manifest_paths"):
            errors.append(f"{prefix}.ready_to_rerun_preflight state requires run_bundle_manifest_paths")
        if payload.get("blocking_reasons"):
            errors.append(f"{prefix}.ready_to_rerun_preflight state requires empty blocking_reasons")
    if plan_state == "blocked_operator_evidence":
        if ready is not False:
            errors.append(f"{prefix}.blocked_operator_evidence requires ready_to_rerun_preflight=false")
        if payload.get("rerun_command"):
            errors.append(f"{prefix}.blocked_operator_evidence requires empty rerun_command")
        if not payload.get("blocking_reasons"):
            errors.append(f"{prefix}.blocked_operator_evidence requires blocking_reasons")
    if plan_state == "no_resume_needed":
        if ready is not False:
            errors.append(f"{prefix}.no_resume_needed requires ready_to_rerun_preflight=false")
        if payload.get("rerun_command"):
            errors.append(f"{prefix}.no_resume_needed requires empty rerun_command")


def validate_official_comparison_release_gate_report(payload, errors, prefix):
    require_fields(
        errors,
        payload,
        [
            "release_state",
            "eligible_for_default_release",
            "preflight_workflow_report_path",
            "decision_workflow_report_path",
            "decision_manifest_path",
            "regression_report_path",
            "preflight_workflow_state",
            "preflight_eligible_for_official_comparison",
            "decision_workflow_state",
            "decision_state",
            "default_change",
            "eligible_for_default",
            "regression_state",
            "preflight_reference_version",
            "decision_reference_version",
            "regression_reference_version",
            "blocking_gates",
            "blocking_reasons",
            "next_actions",
            "evidence_paths",
            "markdown_report_path",
            "html_report_path",
        ],
        prefix,
    )
    release_state = payload.get("release_state")
    if release_state not in OFFICIAL_COMPARISON_RELEASE_GATE_STATES:
        errors.append(f"{prefix}.release_state is invalid: {release_state!r}")
    for name in [
        "eligible_for_default_release",
        "preflight_eligible_for_official_comparison",
        "eligible_for_default",
    ]:
        require_type(errors, payload.get(name), bool, f"{prefix}.{name}")
    for name in [
        "preflight_workflow_report_path",
        "decision_workflow_report_path",
        "decision_manifest_path",
        "regression_report_path",
        "preflight_workflow_state",
        "decision_workflow_state",
        "decision_state",
        "default_change",
        "regression_state",
        "preflight_reference_version",
        "decision_reference_version",
        "regression_reference_version",
        "markdown_report_path",
        "html_report_path",
    ]:
        require_non_empty_string(errors, payload.get(name), f"{prefix}.{name}")
    if payload.get("preflight_workflow_state") not in OFFICIAL_COMPARISON_PREFLIGHT_WORKFLOW_STATES:
        errors.append(
            f"{prefix}.preflight_workflow_state is invalid: "
            f"{payload.get('preflight_workflow_state')!r}"
        )
    if payload.get("decision_workflow_state") != "completed":
        errors.append(f"{prefix}.decision_workflow_state must be completed")
    if payload.get("decision_state") not in DECISION_STATES:
        errors.append(f"{prefix}.decision_state is invalid: {payload.get('decision_state')!r}")
    if payload.get("default_change") not in DEFAULT_CHANGE_VALUES:
        errors.append(f"{prefix}.default_change is invalid: {payload.get('default_change')!r}")
    if payload.get("regression_state") not in REGRESSION_STATES:
        errors.append(f"{prefix}.regression_state is invalid: {payload.get('regression_state')!r}")
    for name in [
        "blocking_gates",
        "blocking_reasons",
        "next_actions",
        "evidence_paths",
    ]:
        require_string_list(errors, payload.get(name), f"{prefix}.{name}")
    validate_official_comparison_release_gate_optional_operator_context(
        payload,
        errors,
        prefix,
    )
    enforce_official_comparison_release_gate_invariants(payload, errors, prefix)


def validate_official_comparison_release_gate_optional_operator_context(payload, errors, prefix):
    for name in [
        "operator_handoff_report_path",
        "operator_evidence_intake_report_path",
        "preflight_resume_plan_path",
    ]:
        if name in payload:
            require_non_empty_string(errors, payload.get(name), f"{prefix}.{name}")
    if "operator_handoff_state" in payload:
        if payload.get("operator_handoff_state") not in OFFICIAL_COMPARISON_OPERATOR_HANDOFF_STATES:
            errors.append(
                f"{prefix}.operator_handoff_state is invalid: "
                f"{payload.get('operator_handoff_state')!r}"
            )
    if "operator_evidence_intake_state" in payload:
        if payload.get("operator_evidence_intake_state") not in (
            OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_INTAKE_STATES
        ):
            errors.append(
                f"{prefix}.operator_evidence_intake_state is invalid: "
                f"{payload.get('operator_evidence_intake_state')!r}"
            )
    if "preflight_resume_plan_state" in payload:
        if payload.get("preflight_resume_plan_state") not in (
            OFFICIAL_COMPARISON_PREFLIGHT_RESUME_PLAN_STATES
        ):
            errors.append(
                f"{prefix}.preflight_resume_plan_state is invalid: "
                f"{payload.get('preflight_resume_plan_state')!r}"
            )
    for name in [
        "operator_handoff_item_count",
        "operator_handoff_blocked_item_count",
        "operator_evidence_accepted_item_count",
        "operator_evidence_missing_item_count",
        "operator_evidence_rejected_item_count",
    ]:
        if name in payload:
            require_non_negative_int(errors, payload.get(name), f"{prefix}.{name}")
    for name in [
        "operator_evidence_ready_to_rerun_preflight",
        "preflight_resume_ready_to_rerun",
    ]:
        if name in payload:
            require_type(errors, payload.get(name), bool, f"{prefix}.{name}")


def enforce_official_comparison_release_gate_invariants(payload, errors, prefix):
    release_state = payload.get("release_state")
    eligible = payload.get("eligible_for_default_release")
    preflight_ready = (
        payload.get("preflight_workflow_state") == "ready_for_official_comparison"
        and payload.get("preflight_eligible_for_official_comparison") is True
    )
    regression_ready = payload.get("regression_state") == "passed"
    decision_ready = (
        payload.get("decision_workflow_state") == "completed"
        and payload.get("decision_state") == "default_allowed"
        and payload.get("default_change") == "allowed"
        and payload.get("eligible_for_default") is True
    )
    versions_match = (
        payload.get("preflight_reference_version")
        == payload.get("decision_reference_version")
        == payload.get("regression_reference_version")
    )
    expected_state = "ready_for_default_release"
    if not preflight_ready:
        expected_state = "blocked_preflight"
    elif not regression_ready:
        expected_state = "blocked_regression"
    elif not decision_ready or not versions_match:
        expected_state = "blocked_decision"

    if release_state in OFFICIAL_COMPARISON_RELEASE_GATE_STATES and release_state != expected_state:
        errors.append(f"{prefix}.release_state must be {expected_state} for current gate states")
    if expected_state == "ready_for_default_release":
        if eligible is not True:
            errors.append(f"{prefix}.ready release requires eligible_for_default_release=true")
        if payload.get("blocking_gates"):
            errors.append(f"{prefix}.ready release requires empty blocking_gates")
        if payload.get("blocking_reasons"):
            errors.append(f"{prefix}.ready release requires empty blocking_reasons")
        enforce_ready_release_operator_context(payload, errors, prefix)
    else:
        if eligible is True:
            errors.append(f"{prefix}.blocked release requires eligible_for_default_release=false")
        if not payload.get("blocking_gates"):
            errors.append(f"{prefix}.blocked release requires blocking_gates")
        if not payload.get("blocking_reasons"):
            errors.append(f"{prefix}.blocked release requires blocking_reasons")


def enforce_ready_release_operator_context(payload, errors, prefix):
    expected = {
        "operator_handoff_state": "no_handoff_needed",
        "operator_evidence_intake_state": "no_handoff_needed",
        "preflight_resume_plan_state": "no_resume_needed",
    }
    for name, value in expected.items():
        if name in payload and payload.get(name) != value:
            errors.append(f"{prefix}.ready release requires {name}={value}")


def validate_official_release_workflow_report(payload, errors, prefix):
    require_fields(
        errors,
        payload,
        [
            "workflow_state",
            "release_state",
            "eligible_for_default_release",
            "target_reference_version",
            "preflight_workflow_report_path",
            "decision_workflow_report_path",
            "artifact_prep_report_path",
            "execution_status_report_path",
            "operator_handoff_report_path",
            "operator_evidence_intake_report_path",
            "preflight_resume_plan_path",
            "release_gate_report_path",
            "operator_handoff_state",
            "operator_handoff_item_count",
            "operator_handoff_ready_item_count",
            "operator_handoff_blocked_item_count",
            "operator_evidence_intake_state",
            "operator_evidence_ready_to_rerun_preflight",
            "operator_evidence_accepted_item_count",
            "operator_evidence_missing_item_count",
            "operator_evidence_rejected_item_count",
            "preflight_resume_plan_state",
            "preflight_resume_ready_to_rerun",
            "operator_tasks",
            "blocking_gates",
            "blocking_reasons",
            "next_actions",
            "evidence_paths",
            "markdown_report_path",
            "html_report_path",
        ],
        prefix,
    )
    workflow_state = payload.get("workflow_state")
    if workflow_state not in OFFICIAL_RELEASE_WORKFLOW_STATES:
        errors.append(f"{prefix}.workflow_state is invalid: {workflow_state!r}")
    if payload.get("release_state") not in OFFICIAL_COMPARISON_RELEASE_GATE_STATES:
        errors.append(f"{prefix}.release_state is invalid: {payload.get('release_state')!r}")
    require_type(
        errors,
        payload.get("eligible_for_default_release"),
        bool,
        f"{prefix}.eligible_for_default_release",
    )
    for name in [
        "preflight_workflow_report_path",
        "decision_workflow_report_path",
        "target_reference_version",
        "artifact_prep_report_path",
        "execution_status_report_path",
        "operator_handoff_report_path",
        "operator_evidence_intake_report_path",
        "preflight_resume_plan_path",
        "release_gate_report_path",
        "markdown_report_path",
        "html_report_path",
    ]:
        require_non_empty_string(errors, payload.get(name), f"{prefix}.{name}")
    if payload.get("operator_handoff_state") not in OFFICIAL_COMPARISON_OPERATOR_HANDOFF_STATES:
        errors.append(
            f"{prefix}.operator_handoff_state is invalid: "
            f"{payload.get('operator_handoff_state')!r}"
        )
    if payload.get("operator_evidence_intake_state") not in (
        OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_INTAKE_STATES
    ):
        errors.append(
            f"{prefix}.operator_evidence_intake_state is invalid: "
            f"{payload.get('operator_evidence_intake_state')!r}"
        )
    if payload.get("preflight_resume_plan_state") not in (
        OFFICIAL_COMPARISON_PREFLIGHT_RESUME_PLAN_STATES
    ):
        errors.append(
            f"{prefix}.preflight_resume_plan_state is invalid: "
            f"{payload.get('preflight_resume_plan_state')!r}"
        )
    for name in [
        "operator_handoff_item_count",
        "operator_handoff_ready_item_count",
        "operator_handoff_blocked_item_count",
        "operator_evidence_accepted_item_count",
        "operator_evidence_missing_item_count",
        "operator_evidence_rejected_item_count",
    ]:
        require_non_negative_int(errors, payload.get(name), f"{prefix}.{name}")
    for name in ["operator_evidence_ready_to_rerun_preflight", "preflight_resume_ready_to_rerun"]:
        require_type(errors, payload.get(name), bool, f"{prefix}.{name}")
    for name in ["blocking_gates", "blocking_reasons", "next_actions", "evidence_paths"]:
        require_string_list(errors, payload.get(name), f"{prefix}.{name}")
    require_type(errors, payload.get("operator_tasks"), list, f"{prefix}.operator_tasks")
    if isinstance(payload.get("operator_tasks"), list):
        for index, task in enumerate(payload["operator_tasks"]):
            validate_official_release_workflow_operator_task(
                task,
                errors,
                f"{prefix}.operator_tasks[{index}]",
            )
    enforce_official_release_gate_report_copy_invariants(payload, errors, prefix)
    enforce_official_release_artifact_prep_report_copy_invariants(
        payload,
        errors,
        prefix,
    )
    enforce_official_release_execution_status_report_copy_invariants(
        payload,
        errors,
        prefix,
    )
    enforce_official_release_operator_handoff_report_copy_invariants(
        payload,
        errors,
        prefix,
    )
    enforce_official_release_operator_evidence_intake_report_copy_invariants(
        payload,
        errors,
        prefix,
    )
    enforce_official_release_preflight_resume_plan_copy_invariants(
        payload,
        errors,
        prefix,
    )
    validate_official_release_workflow_optional_request_context(payload, errors, prefix)
    enforce_official_release_workflow_invariants(payload, errors, prefix)


def validate_official_release_workflow_optional_request_context(payload, errors, prefix):
    for name in [
        "operator_evidence_request_report_path",
        "operator_evidence_request_target_reference_version",
        "operator_evidence_return_workflow_report_path",
        "operator_evidence_return_target_reference_version",
        "operator_evidence_return_template_path",
        "operator_evidence_return_guide_markdown_path",
        "operator_evidence_return_guide_html_path",
        "operator_evidence_return_template_fill_command_template_path",
        "operator_evidence_return_workflow_command_template_path",
        "operator_evidence_intake_command_template_path",
        "operator_evidence_release_workflow_command_template_path",
        "operator_evidence_execution_plan_path",
        "operator_evidence_submission_checklist_path",
        "operator_evidence_submission_status_report_path",
        "operator_evidence_submission_values_template_path",
        "operator_evidence_submission_values_template_markdown_path",
        "operator_evidence_submission_values_template_html_path",
        "adoption_checklist_report_path",
        "adoption_remediation_plan_path",
        "adoption_remediation_target_reference_version",
    ]:
        if name in payload:
            require_non_empty_string(errors, payload.get(name), f"{prefix}.{name}")
    if "operator_evidence_request_state" in payload:
        if payload.get("operator_evidence_request_state") not in (
            OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_REQUEST_STATES
        ):
            errors.append(
                f"{prefix}.operator_evidence_request_state is invalid: "
                f"{payload.get('operator_evidence_request_state')!r}"
            )
    if "operator_evidence_requested_task_count" in payload:
        require_non_negative_int(
            errors,
            payload.get("operator_evidence_requested_task_count"),
            f"{prefix}.operator_evidence_requested_task_count",
        )
    if "operator_evidence_return_state" in payload:
        if payload.get("operator_evidence_return_state") not in (
            OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_RETURN_WORKFLOW_STATES
        ):
            errors.append(
                f"{prefix}.operator_evidence_return_state is invalid: "
                f"{payload.get('operator_evidence_return_state')!r}"
            )
    if "operator_evidence_return_intake_state" in payload:
        if payload.get("operator_evidence_return_intake_state") not in (
            OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_INTAKE_STATES
        ):
            errors.append(
                f"{prefix}.operator_evidence_return_intake_state is invalid: "
                f"{payload.get('operator_evidence_return_intake_state')!r}"
            )
    if "operator_evidence_return_preflight_resume_plan_state" in payload:
        if payload.get("operator_evidence_return_preflight_resume_plan_state") not in (
            OFFICIAL_COMPARISON_PREFLIGHT_RESUME_PLAN_STATES
        ):
            errors.append(
                f"{prefix}.operator_evidence_return_preflight_resume_plan_state "
                f"is invalid: {payload.get('operator_evidence_return_preflight_resume_plan_state')!r}"
            )
    if "operator_evidence_return_ready_to_rerun_preflight" in payload:
        require_type(
            errors,
            payload.get("operator_evidence_return_ready_to_rerun_preflight"),
            bool,
            f"{prefix}.operator_evidence_return_ready_to_rerun_preflight",
        )
    for name in [
        "operator_evidence_return_accepted_item_count",
        "operator_evidence_return_missing_item_count",
        "operator_evidence_return_rejected_item_count",
    ]:
        if name in payload:
            require_non_negative_int(errors, payload.get(name), f"{prefix}.{name}")
    if "operator_evidence_return_field_statuses" in payload:
        require_type(
            errors,
            payload.get("operator_evidence_return_field_statuses"),
            list,
            f"{prefix}.operator_evidence_return_field_statuses",
        )
        if isinstance(payload.get("operator_evidence_return_field_statuses"), list):
            for index, item in enumerate(payload["operator_evidence_return_field_statuses"]):
                validate_official_comparison_operator_evidence_return_field_status(
                    item,
                    errors,
                    f"{prefix}.operator_evidence_return_field_statuses[{index}]",
                )
    if "operator_evidence_return_blocker_summary" in payload:
        require_type(
            errors,
            payload.get("operator_evidence_return_blocker_summary"),
            list,
            f"{prefix}.operator_evidence_return_blocker_summary",
        )
        if isinstance(payload.get("operator_evidence_return_blocker_summary"), list):
            for index, item in enumerate(payload["operator_evidence_return_blocker_summary"]):
                validate_official_release_return_blocker_summary_item(
                    item,
                    errors,
                    f"{prefix}.operator_evidence_return_blocker_summary[{index}]",
                )
    if "adoption_blocker_evidence_resolution_summary" in payload:
        require_type(
            errors,
            payload.get("adoption_blocker_evidence_resolution_summary"),
            list,
            f"{prefix}.adoption_blocker_evidence_resolution_summary",
        )
        if isinstance(payload.get("adoption_blocker_evidence_resolution_summary"), list):
            for index, item in enumerate(
                payload["adoption_blocker_evidence_resolution_summary"]
            ):
                validate_official_release_adoption_blocker_evidence_resolution_summary_item(
                    item,
                    errors,
                    f"{prefix}.adoption_blocker_evidence_resolution_summary[{index}]",
                )
    if "adoption_blocker_evidence_resolution_action_summary" in payload:
        require_type(
            errors,
            payload.get("adoption_blocker_evidence_resolution_action_summary"),
            list,
            f"{prefix}.adoption_blocker_evidence_resolution_action_summary",
        )
        if isinstance(
            payload.get("adoption_blocker_evidence_resolution_action_summary"),
            list,
        ):
            for index, item in enumerate(
                payload["adoption_blocker_evidence_resolution_action_summary"]
            ):
                validate_official_release_adoption_blocker_evidence_resolution_action_summary_item(
                    item,
                    errors,
                    f"{prefix}.adoption_blocker_evidence_resolution_action_summary[{index}]",
                )
    if "command_template_paths" in payload:
        require_string_list(
            errors,
            payload.get("command_template_paths"),
            f"{prefix}.command_template_paths",
        )
        if isinstance(payload.get("command_template_paths"), list):
            for name in [
                "operator_evidence_return_template_fill_command_template_path",
                "operator_evidence_return_workflow_command_template_path",
                "operator_evidence_intake_command_template_path",
                "operator_evidence_release_workflow_command_template_path",
            ]:
                if name in payload and payload.get(name) not in payload["command_template_paths"]:
                    errors.append(f"{prefix}.command_template_paths must include {name}")
            if isinstance(payload.get("operator_evidence_submission_command_sequence"), list):
                for index, item in enumerate(
                    payload.get("operator_evidence_submission_command_sequence", [])
                ):
                    if not isinstance(item, dict):
                        continue
                    command = item.get("command_template_path")
                    if command and command not in payload["command_template_paths"]:
                        errors.append(
                            f"{prefix}.command_template_paths must include "
                            f"operator_evidence_submission_command_sequence[{index}]"
                            ".command_template_path"
                        )
    if "operator_evidence_submission_status_report_path" in payload:
        require_fields(
            errors,
            payload,
            [
                "operator_evidence_submission_status_state",
                "operator_evidence_submission_values_template_path",
                "operator_evidence_submission_values_template_markdown_path",
                "operator_evidence_submission_values_template_html_path",
                "operator_evidence_submission_slot_count",
                "operator_evidence_submission_completion_state",
                "operator_evidence_full_submission_ready",
                "operator_evidence_remaining_required_slot_count",
                "operator_evidence_remaining_required_slot_ids",
                "operator_evidence_submission_values_filled_path_count",
                "operator_evidence_submission_values_blank_path_count",
                "operator_evidence_submission_values_minimum_required_filled_path_count",
                "operator_evidence_submission_values_fill_command_readiness_state",
                "operator_evidence_submission_values_fill_command_blocking_reasons",
                "operator_evidence_submitted_submission_slot_count",
                "operator_evidence_missing_submission_slot_count",
                "operator_evidence_rejected_submission_slot_count",
                "operator_evidence_not_needed_submission_slot_count",
                "operator_evidence_expected_submission_path_exists_count",
                "operator_evidence_expected_submission_path_missing_count",
                "operator_evidence_expected_submission_path_not_applicable_count",
                "operator_evidence_expected_submission_path_missing_slot_ids",
                "operator_evidence_submission_action_group_count",
                "operator_evidence_submission_action_groups",
                "operator_evidence_submitted_submission_slot_ids",
                "operator_evidence_missing_submission_slot_ids",
                "operator_evidence_rejected_submission_slot_ids",
                "operator_evidence_not_needed_submission_slot_ids",
                "operator_evidence_submission_blocking_reasons",
                "operator_evidence_submission_blocking_slot_summary",
                "operator_evidence_blocking_submission_slots",
                "operator_evidence_next_blocking_submission_slot_id",
                "operator_evidence_next_blocking_submission_slot_type",
                "operator_evidence_next_blocking_submission_slot_status",
                "operator_evidence_next_blocking_submission_task_id",
                "operator_evidence_next_blocking_submission_title",
                "operator_evidence_next_blocking_submission_return_field",
                "operator_evidence_next_blocking_submission_expected_submission_path",
                (
                    "operator_evidence_next_blocking_submission_"
                    "expected_submission_path_file_state"
                ),
                "operator_evidence_next_blocking_submission_primary_blocker_reason",
                "operator_evidence_next_blocking_submission_first_command_template",
                "operator_evidence_next_blocking_submission_next_action",
                (
                    "operator_evidence_next_blocking_submission_"
                    "source_artifact_hint_paths"
                ),
                (
                    "operator_evidence_next_blocking_submission_"
                    "command_template_paths"
                ),
                "operator_evidence_next_blocking_submission_next_actions",
                "operator_evidence_next_blocking_submission_metadata",
                "operator_evidence_submission_command_sequence",
            ],
            prefix,
        )
    if "operator_evidence_execution_plan_path" in payload:
        validate_official_release_execution_plan_summary_context(
            payload,
            errors,
            prefix,
        )
        enforce_official_release_execution_plan_copy_invariants(
            payload,
            errors,
            prefix,
        )
    if "operator_evidence_submission_checklist_path" in payload:
        enforce_official_release_submission_checklist_copy_invariants(
            payload,
            errors,
            prefix,
        )
    validate_official_release_next_blocking_submission_context(payload, errors, prefix)
    if "operator_evidence_submission_status_state" in payload:
        if payload.get("operator_evidence_submission_status_state") not in (
            OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_SUBMISSION_STATUS_STATES
        ):
            errors.append(
                f"{prefix}.operator_evidence_submission_status_state is invalid: "
                f"{payload.get('operator_evidence_submission_status_state')!r}"
            )
    if "operator_evidence_submission_completion_state" in payload:
        if payload.get("operator_evidence_submission_completion_state") not in (
            OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_SUBMISSION_COMPLETION_STATES
        ):
            errors.append(
                f"{prefix}.operator_evidence_submission_completion_state "
                "is invalid: "
                f"{payload.get('operator_evidence_submission_completion_state')!r}"
            )
    if "operator_evidence_full_submission_ready" in payload:
        require_type(
            errors,
            payload.get("operator_evidence_full_submission_ready"),
            bool,
            f"{prefix}.operator_evidence_full_submission_ready",
        )
    if "operator_evidence_submission_values_fill_command_readiness_state" in payload:
        if payload.get(
            "operator_evidence_submission_values_fill_command_readiness_state"
        ) not in OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_SUBMISSION_VALUES_FILL_STATES:
            errors.append(
                f"{prefix}.operator_evidence_submission_values_fill_command_readiness_state "
                "is invalid: "
                f"{payload.get('operator_evidence_submission_values_fill_command_readiness_state')!r}"
            )
    for name in [
        "operator_evidence_submission_slot_count",
        "operator_evidence_remaining_required_slot_count",
        "operator_evidence_submission_values_filled_path_count",
        "operator_evidence_submission_values_blank_path_count",
        "operator_evidence_submission_values_minimum_required_filled_path_count",
        "operator_evidence_submitted_submission_slot_count",
        "operator_evidence_missing_submission_slot_count",
        "operator_evidence_rejected_submission_slot_count",
        "operator_evidence_not_needed_submission_slot_count",
        "operator_evidence_expected_submission_path_exists_count",
        "operator_evidence_expected_submission_path_missing_count",
        "operator_evidence_expected_submission_path_not_applicable_count",
        "operator_evidence_submission_action_group_count",
    ]:
        if name in payload:
            require_non_negative_int(errors, payload.get(name), f"{prefix}.{name}")
    for name in [
        "operator_evidence_remaining_required_slot_ids",
        "operator_evidence_submitted_submission_slot_ids",
        "operator_evidence_missing_submission_slot_ids",
        "operator_evidence_rejected_submission_slot_ids",
        "operator_evidence_not_needed_submission_slot_ids",
        "operator_evidence_expected_submission_path_missing_slot_ids",
        "operator_evidence_submission_blocking_reasons",
        "operator_evidence_submission_values_fill_command_blocking_reasons",
    ]:
        if name in payload:
            require_string_list(errors, payload.get(name), f"{prefix}.{name}")
    if "operator_evidence_blocking_submission_slots" in payload:
        require_type(
            errors,
            payload.get("operator_evidence_blocking_submission_slots"),
            list,
            f"{prefix}.operator_evidence_blocking_submission_slots",
        )
        if isinstance(payload.get("operator_evidence_blocking_submission_slots"), list):
            for index, item in enumerate(payload["operator_evidence_blocking_submission_slots"]):
                validate_official_comparison_operator_evidence_submission_slot_status(
                    item,
                    errors,
                    f"{prefix}.operator_evidence_blocking_submission_slots[{index}]",
                )
                if isinstance(item, dict) and item.get("slot_status") not in {
                    "missing",
                    "rejected",
                }:
                    errors.append(
                        f"{prefix}.operator_evidence_blocking_submission_slots"
                        f"[{index}].slot_status must be missing or rejected"
                    )
    if "operator_evidence_submission_blocking_slot_summary" in payload:
        require_type(
            errors,
            payload.get("operator_evidence_submission_blocking_slot_summary"),
            list,
            f"{prefix}.operator_evidence_submission_blocking_slot_summary",
        )
        if isinstance(payload.get("operator_evidence_submission_blocking_slot_summary"), list):
            for index, item in enumerate(
                payload["operator_evidence_submission_blocking_slot_summary"]
            ):
                validate_official_comparison_operator_evidence_blocking_slot_summary_item(
                    item,
                    errors,
                    f"{prefix}.operator_evidence_submission_blocking_slot_summary[{index}]",
                )
    if "operator_evidence_submission_action_groups" in payload:
        require_type(
            errors,
            payload.get("operator_evidence_submission_action_groups"),
            list,
            f"{prefix}.operator_evidence_submission_action_groups",
        )
        if isinstance(payload.get("operator_evidence_submission_action_groups"), list):
            for index, item in enumerate(
                payload["operator_evidence_submission_action_groups"]
            ):
                validate_official_comparison_operator_evidence_submission_action_group(
                    item,
                    errors,
                    f"{prefix}.operator_evidence_submission_action_groups[{index}]",
                )
    if "operator_evidence_submission_slot_count" in payload:
        count_values = [
            payload.get("operator_evidence_submitted_submission_slot_count"),
            payload.get("operator_evidence_missing_submission_slot_count"),
            payload.get("operator_evidence_rejected_submission_slot_count"),
            payload.get("operator_evidence_not_needed_submission_slot_count"),
        ]
        if all(isinstance(value, int) for value in count_values):
            if payload.get("operator_evidence_submission_slot_count") != sum(count_values):
                errors.append(
                    f"{prefix}.operator_evidence_submission_slot_count must equal "
                    "submitted+missing+rejected+not_needed counts"
                )
        id_count_pairs = [
            (
                "operator_evidence_submitted_submission_slot_count",
                "operator_evidence_submitted_submission_slot_ids",
            ),
            (
                "operator_evidence_missing_submission_slot_count",
                "operator_evidence_missing_submission_slot_ids",
            ),
            (
                "operator_evidence_rejected_submission_slot_count",
                "operator_evidence_rejected_submission_slot_ids",
            ),
            (
                "operator_evidence_not_needed_submission_slot_count",
                "operator_evidence_not_needed_submission_slot_ids",
            ),
        ]
        for count_field, ids_field in id_count_pairs:
            ids = payload.get(ids_field)
            if isinstance(payload.get(count_field), int) and isinstance(ids, list):
                if payload[count_field] != len(ids):
                    errors.append(f"{prefix}.{count_field} must equal {ids_field} length")
        enforce_official_release_submission_slot_id_partition(payload, errors, prefix)
        if isinstance(payload.get("operator_evidence_submission_action_groups"), list):
            blocking_slot_targets = {
                item.get("slot_id"): item.get("target_reference_version", "")
                for item in payload.get("operator_evidence_blocking_submission_slots", [])
                if isinstance(item, dict)
            }
            synthetic_slots = []
            for state, ids_field in [
                ("submitted", "operator_evidence_submitted_submission_slot_ids"),
                ("missing", "operator_evidence_missing_submission_slot_ids"),
                ("rejected", "operator_evidence_rejected_submission_slot_ids"),
                ("not_needed", "operator_evidence_not_needed_submission_slot_ids"),
            ]:
                for slot_id in payload.get(ids_field, []):
                    if not isinstance(slot_id, str) or not slot_id:
                        continue
                    synthetic_slots.append({
                        "slot_id": slot_id,
                        "slot_status": state,
                        "target_reference_version": blocking_slot_targets.get(
                            slot_id,
                            payload.get("target_reference_version", ""),
                        ),
                    })
            enforce_official_comparison_operator_evidence_submission_action_group_invariants(
                payload,
                synthetic_slots,
                "operator_evidence_submission_action_group_count",
                "operator_evidence_submission_action_groups",
                errors,
                prefix,
            )
        expected_submission_status = (
            expected_official_release_submission_status_state(payload)
        )
        actual_submission_status = payload.get("operator_evidence_submission_status_state")
        if (
            expected_submission_status
            and actual_submission_status in (
                OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_SUBMISSION_STATUS_STATES
            )
            and actual_submission_status != expected_submission_status
        ):
            errors.append(
                f"{prefix}.operator_evidence_submission_status_state must be "
                f"{expected_submission_status}"
            )
        filled_paths = payload.get("operator_evidence_submission_values_filled_path_count")
        blank_paths = payload.get("operator_evidence_submission_values_blank_path_count")
        minimum_required = payload.get(
            "operator_evidence_submission_values_minimum_required_filled_path_count"
        )
        fill_state = payload.get(
            "operator_evidence_submission_values_fill_command_readiness_state"
        )
        if isinstance(filled_paths, int) and isinstance(blank_paths, int):
            if payload.get("operator_evidence_submission_slot_count") != (
                filled_paths + blank_paths
            ):
                errors.append(
                    f"{prefix}.operator_evidence_submission_slot_count must equal "
                    "submission values filled+blank path counts"
                )
        if isinstance(minimum_required, int):
            expected_minimum = (
                1
                if int_or_zero(payload.get("operator_evidence_submission_slot_count")) > 0
                else 0
            )
            if minimum_required != expected_minimum:
                errors.append(
                    f"{prefix}.operator_evidence_submission_values_minimum_required_filled_path_count "
                    f"must be {expected_minimum}"
                )
        if (
            isinstance(filled_paths, int)
            and isinstance(minimum_required, int)
            and fill_state in OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_SUBMISSION_VALUES_FILL_STATES
        ):
            rejected_path_count = official_release_rejected_submission_path_count(payload)
            expected_fill_state = (
                "no_submission_values_needed"
                if int_or_zero(payload.get("operator_evidence_submission_slot_count")) == 0
                else (
                    "blocked_invalid_submission_values"
                    if rejected_path_count > 0
                    else (
                        "ready_to_fill_return_template"
                        if filled_paths >= minimum_required
                        else "blocked_empty_submission_values"
                    )
                )
            )
            if fill_state != expected_fill_state:
                errors.append(
                    f"{prefix}.operator_evidence_submission_values_fill_command_readiness_state "
                    f"must be {expected_fill_state}"
                )
        enforce_official_release_submission_status_report_copy_invariants(
            payload,
            errors,
            prefix,
        )
        enforce_official_release_submission_values_template_copy_invariants(
            payload,
            errors,
            prefix,
        )
        if fill_state in {
            "blocked_empty_submission_values",
            "blocked_invalid_submission_values",
        }:
            if not payload.get(
                "operator_evidence_submission_values_fill_command_blocking_reasons"
            ):
                errors.append(
                    f"{prefix}.blocked submission values fill command requires "
                    "operator_evidence_submission_values_fill_command_blocking_reasons"
                )
            next_actions = payload.get("next_actions")
            if isinstance(next_actions, list):
                for reason in payload.get(
                    "operator_evidence_submission_values_fill_command_blocking_reasons",
                    [],
                ):
                    if reason not in next_actions:
                        errors.append(
                            f"{prefix}.next_actions must include blocked submission "
                            "values fill command reasons"
                        )
        blocking_slots = payload.get("operator_evidence_blocking_submission_slots")
        if isinstance(blocking_slots, list):
            expected_blocking_count = (
                int_or_zero(payload.get("operator_evidence_missing_submission_slot_count"))
                + int_or_zero(payload.get("operator_evidence_rejected_submission_slot_count"))
            )
            if len(blocking_slots) != expected_blocking_count:
                errors.append(
                    f"{prefix}.operator_evidence_blocking_submission_slots length "
                    "must equal missing+rejected submission slot counts"
                )
            missing_ids = set(payload.get("operator_evidence_missing_submission_slot_ids", []))
            rejected_ids = set(payload.get("operator_evidence_rejected_submission_slot_ids", []))
            blocking_ids = {
                item.get("slot_id")
                for item in blocking_slots
                if isinstance(item, dict)
            }
            if blocking_ids != missing_ids | rejected_ids:
                errors.append(
                    f"{prefix}.operator_evidence_blocking_submission_slots slot ids "
                    "must equal missing/rejected slot ids"
                )
        if (
            payload.get("operator_evidence_missing_submission_slot_count", 0) > 0
            or payload.get("operator_evidence_rejected_submission_slot_count", 0) > 0
        ):
            if not payload.get("operator_evidence_submission_blocking_reasons"):
                errors.append(
                    f"{prefix}.operator evidence submission blockers require "
                    "operator_evidence_submission_blocking_reasons"
                )
    if "operator_evidence_submission_command_sequence" in payload:
        require_type(
            errors,
            payload.get("operator_evidence_submission_command_sequence"),
            list,
            f"{prefix}.operator_evidence_submission_command_sequence",
        )
        if isinstance(payload.get("operator_evidence_submission_command_sequence"), list):
            for index, item in enumerate(
                payload["operator_evidence_submission_command_sequence"]
            ):
                validate_official_comparison_operator_evidence_submission_command_step(
                    item,
                    errors,
                    f"{prefix}.operator_evidence_submission_command_sequence[{index}]",
                )
            expected_step_ids = [
                "fill_return_template_from_status",
                "run_return_workflow_from_status",
                "rerun_release_workflow_from_status_return",
            ]
            actual_step_ids = [
                item.get("step_id")
                for item in payload["operator_evidence_submission_command_sequence"]
                if isinstance(item, dict)
            ]
            if actual_step_ids != expected_step_ids:
                errors.append(
                    f"{prefix}.operator_evidence_submission_command_sequence "
                    "step_id order is invalid"
                )
            seen_step_ids = set()
            for index, item in enumerate(
                payload["operator_evidence_submission_command_sequence"]
            ):
                if not isinstance(item, dict):
                    continue
                expected_order = index + 1
                if item.get("step_order") != expected_order:
                    errors.append(
                        f"{prefix}.operator_evidence_submission_command_sequence"
                        f"[{index}].step_order must be {expected_order}"
                    )
                for dependency in item.get("depends_on_step_ids", []):
                    if dependency not in seen_step_ids:
                        errors.append(
                            f"{prefix}.operator_evidence_submission_command_sequence"
                            f"[{index}].depends_on_step_ids must reference earlier steps"
                        )
                seen_step_ids.add(item.get("step_id"))
            enforce_official_comparison_operator_evidence_submission_command_sequence_contract(
                payload["operator_evidence_submission_command_sequence"],
                errors,
                f"{prefix}.operator_evidence_submission_command_sequence",
                expected_step_states={
                    "fill_return_template_from_status": (
                        expected_official_operator_evidence_submission_fill_step_state(
                            payload.get(
                                "operator_evidence_submission_values_fill_command_readiness_state"
                            )
                        )
                    ),
                    "run_return_workflow_from_status": "blocked",
                    "rerun_release_workflow_from_status_return": "blocked",
                },
            )
    if "operator_evidence_return_field_requirements" in payload:
        require_type(
            errors,
            payload.get("operator_evidence_return_field_requirements"),
            list,
            f"{prefix}.operator_evidence_return_field_requirements",
        )
        if isinstance(payload.get("operator_evidence_return_field_requirements"), list):
            for index, item in enumerate(
                payload["operator_evidence_return_field_requirements"]
            ):
                validate_official_comparison_operator_evidence_request_field_requirement(
                    item,
                    errors,
                    f"{prefix}.operator_evidence_return_field_requirements[{index}]",
                )
    if "adoption_state" in payload:
        if payload.get("adoption_state") not in OFFICIAL_COMPARISON_ADOPTION_STATES:
            errors.append(
                f"{prefix}.adoption_state is invalid: {payload.get('adoption_state')!r}"
            )
    if "adoption_blockers" in payload:
        require_type(
            errors,
            payload.get("adoption_blockers"),
            list,
            f"{prefix}.adoption_blockers",
        )
        if isinstance(payload.get("adoption_blockers"), list):
            for index, item in enumerate(payload["adoption_blockers"]):
                validate_official_release_workflow_adoption_blocker(
                    item,
                    errors,
                    f"{prefix}.adoption_blockers[{index}]",
                )
    if "release_artifact_audit_report_path" in payload:
        require_type(
            errors,
            payload.get("release_artifact_audit_report_path"),
            str,
            f"{prefix}.release_artifact_audit_report_path",
        )
    if "adoption_remediation_plan_state" in payload:
        if (
            payload.get("adoption_remediation_plan_state")
            not in OFFICIAL_COMPARISON_ADOPTION_REMEDIATION_PLAN_STATES
        ):
            errors.append(
                f"{prefix}.adoption_remediation_plan_state is invalid: "
                f"{payload.get('adoption_remediation_plan_state')!r}"
            )
    for name in [
        "adoption_passed_item_count",
        "adoption_blocked_item_count",
        "adoption_unknown_item_count",
        "adoption_remediation_task_count",
        "adoption_remediation_open_task_count",
    ]:
        if name in payload:
            require_non_negative_int(errors, payload.get(name), f"{prefix}.{name}")
    if "adoption_checklist_report_path" in payload:
        enforce_official_release_adoption_checklist_report_copy_invariants(
            payload,
            errors,
            prefix,
        )
        adoption_context_fields = [
            "adoption_state",
            "adoption_passed_item_count",
            "adoption_blocked_item_count",
            "adoption_unknown_item_count",
            "adoption_blockers",
        ]
        require_fields(errors, payload, adoption_context_fields, prefix)
    if "operator_evidence_request_report_path" in payload:
        enforce_official_release_request_report_copy_invariants(
            payload,
            errors,
            prefix,
        )
        request_context_fields = [
            "operator_evidence_request_state",
            "operator_evidence_requested_task_count",
            "operator_evidence_request_target_reference_version",
            "operator_evidence_return_template_path",
            "operator_evidence_return_guide_markdown_path",
            "operator_evidence_return_guide_html_path",
            "operator_evidence_return_template_fill_command_template_path",
            "operator_evidence_return_workflow_command_template_path",
            "operator_evidence_intake_command_template_path",
            "operator_evidence_release_workflow_command_template_path",
            "command_template_paths",
            "operator_evidence_return_field_requirements",
        ]
        require_fields(errors, payload, request_context_fields, prefix)
        require_non_empty_string(
            errors,
            payload.get("operator_evidence_request_target_reference_version"),
            f"{prefix}.operator_evidence_request_target_reference_version",
        )
        for name in [
            "operator_evidence_return_template_path",
            "operator_evidence_return_guide_markdown_path",
            "operator_evidence_return_guide_html_path",
            "operator_evidence_return_template_fill_command_template_path",
            "operator_evidence_return_workflow_command_template_path",
            "operator_evidence_intake_command_template_path",
            "operator_evidence_release_workflow_command_template_path",
        ]:
            require_non_empty_string(errors, payload.get(name), f"{prefix}.{name}")
        requirements = payload.get("operator_evidence_return_field_requirements")
        if (
            isinstance(requirements, list)
            and int_or_zero(payload.get("operator_evidence_requested_task_count")) > 0
            and not requirements
        ):
            errors.append(
                f"{prefix}.operator_evidence_return_field_requirements must not be empty "
                "when operator evidence request has tasks"
            )
        if (
            isinstance(requirements, list)
            and "operator_evidence_requested_task_count" in payload
        ):
            requested_task_ids = set()
            for item in requirements:
                if isinstance(item, dict):
                    requested_task_ids.update(item.get("requested_task_ids", []))
            if payload.get("operator_evidence_requested_task_count") != len(
                requested_task_ids
            ):
                errors.append(
                    f"{prefix}.operator_evidence_requested_task_count must equal "
                    "distinct requested_task_ids"
                )
    if "operator_evidence_return_workflow_report_path" in payload:
        return_context_fields = [
            "operator_evidence_return_state",
            "operator_evidence_return_target_reference_version",
            "operator_evidence_return_intake_state",
            "operator_evidence_return_accepted_item_count",
            "operator_evidence_return_missing_item_count",
            "operator_evidence_return_rejected_item_count",
            "operator_evidence_return_preflight_resume_plan_state",
            "operator_evidence_return_ready_to_rerun_preflight",
            "operator_evidence_return_field_statuses",
            "operator_evidence_return_submission_slot_values",
        ]
        require_fields(errors, payload, return_context_fields, prefix)
        require_non_empty_string(
            errors,
            payload.get("operator_evidence_return_target_reference_version"),
            f"{prefix}.operator_evidence_return_target_reference_version",
        )
        if (
            isinstance(payload.get("operator_evidence_return_field_statuses"), list)
            and not payload.get("operator_evidence_return_field_statuses")
        ):
            errors.append(
                f"{prefix}.operator_evidence_return_field_statuses must not be empty "
                "when operator evidence return workflow report is attached"
            )
        if "adoption_blockers" in payload:
            require_fields(
                errors,
                payload,
                ["operator_evidence_return_blocker_summary"],
                prefix,
            )
    if "operator_evidence_return_submission_slot_values" in payload:
        require_type(
            errors,
            payload.get("operator_evidence_return_submission_slot_values"),
            list,
            f"{prefix}.operator_evidence_return_submission_slot_values",
        )
        if isinstance(payload.get("operator_evidence_return_submission_slot_values"), list):
            for index, item in enumerate(
                payload["operator_evidence_return_submission_slot_values"]
            ):
                validate_official_comparison_operator_evidence_return_template_slot_value(
                    item,
                    errors,
                    f"{prefix}.operator_evidence_return_submission_slot_values[{index}]",
                )
    if "adoption_remediation_plan_path" in payload:
        enforce_official_release_adoption_remediation_plan_copy_invariants(
            payload,
            errors,
            prefix,
        )
        remediation_context_fields = [
            "adoption_remediation_plan_state",
            "adoption_remediation_target_reference_version",
            "adoption_remediation_task_count",
            "adoption_remediation_open_task_count",
        ]
        require_fields(errors, payload, remediation_context_fields, prefix)
        require_non_empty_string(
            errors,
            payload.get("adoption_remediation_target_reference_version"),
            f"{prefix}.adoption_remediation_target_reference_version",
        )


def validate_official_release_workflow_operator_task(task, errors, prefix):
    if not isinstance(task, dict):
        errors.append(f"{prefix} must be an object")
        return
    require_fields(
        errors,
        task,
        [
            "task_id",
            "title",
            "execution_status",
            "evidence_state",
            "operator_action",
            "next_action",
            "reasons",
            "evidence_to_return",
            "source_paths",
            "evidence_paths",
        ],
        prefix,
    )
    if task.get("execution_status") not in OFFICIAL_COMPARISON_NEXT_ACTION_TASK_EXECUTION_STATUSES:
        errors.append(f"{prefix}.execution_status is invalid: {task.get('execution_status')!r}")
    if task.get("evidence_state") not in OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_ITEM_STATES:
        errors.append(f"{prefix}.evidence_state is invalid: {task.get('evidence_state')!r}")
    for name in ["task_id", "title", "operator_action", "next_action"]:
        require_non_empty_string(errors, task.get(name), f"{prefix}.{name}")
    for name in ["reasons", "evidence_to_return", "source_paths", "evidence_paths"]:
        require_string_list(errors, task.get(name), f"{prefix}.{name}")
    for name in [
        "adoption_item_ids",
        "return_fields",
        "acceptance_criteria",
        "command_template_paths",
        "next_actions",
    ]:
        if name in task:
            require_string_list(errors, task.get(name), f"{prefix}.{name}")
    if "request_state" in task:
        if task.get("request_state") not in (
            OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_REQUEST_ITEM_STATES
        ):
            errors.append(f"{prefix}.request_state is invalid: {task.get('request_state')!r}")
    if "task_state" in task:
        require_non_empty_string(errors, task.get("task_state"), f"{prefix}.task_state")


def validate_official_release_workflow_adoption_blocker(item, errors, prefix):
    if not isinstance(item, dict):
        errors.append(f"{prefix} must be an object")
        return
    require_fields(
        errors,
        item,
        [
            "item_id",
            "title",
            "state",
            "remediation_task_ids",
            "return_fields",
            "evidence_to_return",
            "acceptance_criteria",
            "command_template_paths",
            "reasons",
            "next_actions",
        ],
        prefix,
    )
    if item.get("state") not in {"blocked", "unknown"}:
        errors.append(f"{prefix}.state is invalid: {item.get('state')!r}")
    for name in ["item_id", "title", "state"]:
        require_non_empty_string(errors, item.get(name), f"{prefix}.{name}")
    for name in [
        "remediation_task_ids",
        "return_fields",
        "evidence_to_return",
        "acceptance_criteria",
        "command_template_paths",
        "reasons",
        "next_actions",
    ]:
        require_string_list(errors, item.get(name), f"{prefix}.{name}")


def validate_official_release_return_blocker_summary_item(item, errors, prefix):
    if not isinstance(item, dict):
        errors.append(f"{prefix} must be an object")
        return
    require_fields(
        errors,
        item,
        [
            "field",
            "summary_state",
            "provided",
            "value_contract_state",
            "field_resolution_state",
            "related_adoption_item_ids",
            "blocked_adoption_item_ids",
            "blocked_adoption_item_titles",
            "remediation_task_ids",
            "accepted_evidence_task_ids",
            "missing_evidence_task_ids",
            "rejected_evidence_task_ids",
            "blocked_evidence_task_ids",
            "value_contract_errors",
            "evidence_to_return",
            "acceptance_criteria",
            "command_template_paths",
            "next_actions",
        ],
        prefix,
    )
    require_non_empty_string(errors, item.get("field"), f"{prefix}.field")
    if item.get("summary_state") not in OFFICIAL_RELEASE_RETURN_BLOCKER_SUMMARY_STATES:
        errors.append(
            f"{prefix}.summary_state is invalid: {item.get('summary_state')!r}"
        )
    require_type(errors, item.get("provided"), bool, f"{prefix}.provided")
    if item.get("value_contract_state") not in (
        OFFICIAL_COMPARISON_RETURN_FIELD_VALUE_CONTRACT_STATES
    ):
        errors.append(
            f"{prefix}.value_contract_state is invalid: "
            f"{item.get('value_contract_state')!r}"
        )
    if item.get("field_resolution_state") not in (
        OFFICIAL_COMPARISON_RETURN_FIELD_RESOLUTION_STATES
    ):
        errors.append(
            f"{prefix}.field_resolution_state is invalid: "
            f"{item.get('field_resolution_state')!r}"
        )
    for name in [
        "related_adoption_item_ids",
        "blocked_adoption_item_ids",
        "blocked_adoption_item_titles",
        "remediation_task_ids",
        "accepted_evidence_task_ids",
        "missing_evidence_task_ids",
        "rejected_evidence_task_ids",
        "blocked_evidence_task_ids",
        "value_contract_errors",
        "evidence_to_return",
        "acceptance_criteria",
        "command_template_paths",
        "next_actions",
    ]:
        require_string_list(errors, item.get(name), f"{prefix}.{name}")
    if item.get("summary_state") == "blocking_adoption":
        if not item.get("blocked_adoption_item_ids"):
            errors.append(
                f"{prefix}.blocking_adoption requires blocked_adoption_item_ids"
            )
        if not item.get("remediation_task_ids"):
            errors.append(f"{prefix}.blocking_adoption requires remediation_task_ids")


def validate_official_release_adoption_blocker_evidence_resolution_summary_item(
    item,
    errors,
    prefix,
):
    if not isinstance(item, dict):
        errors.append(f"{prefix} must be an object")
        return
    require_fields(
        errors,
        item,
        [
            "item_id",
            "title",
            "adoption_state",
            "evidence_resolution_state",
            "related_return_fields",
            "blocking_return_fields",
            "accepted_return_fields",
            "remediation_task_ids",
            "accepted_evidence_task_ids",
            "missing_evidence_task_ids",
            "rejected_evidence_task_ids",
            "blocked_evidence_task_ids",
            "value_contract_states",
            "field_resolution_states",
            "next_actions",
        ],
        prefix,
    )
    require_non_empty_string(errors, item.get("item_id"), f"{prefix}.item_id")
    require_non_empty_string(errors, item.get("title"), f"{prefix}.title")
    require_non_empty_string(
        errors,
        item.get("adoption_state"),
        f"{prefix}.adoption_state",
    )
    if (
        item.get("evidence_resolution_state")
        not in OFFICIAL_RELEASE_ADOPTION_BLOCKER_EVIDENCE_RESOLUTION_STATES
    ):
        errors.append(
            f"{prefix}.evidence_resolution_state is invalid: "
            f"{item.get('evidence_resolution_state')!r}"
        )
    for name in [
        "related_return_fields",
        "blocking_return_fields",
        "accepted_return_fields",
        "remediation_task_ids",
        "accepted_evidence_task_ids",
        "missing_evidence_task_ids",
        "rejected_evidence_task_ids",
        "blocked_evidence_task_ids",
        "value_contract_states",
        "field_resolution_states",
        "next_actions",
    ]:
        require_string_list(errors, item.get(name), f"{prefix}.{name}")
    if item.get("evidence_resolution_state") == "blocked_by_operator_evidence":
        if not item.get("blocking_return_fields"):
            errors.append(
                f"{prefix}.blocked_by_operator_evidence requires blocking_return_fields"
            )
        if not item.get("blocked_evidence_task_ids"):
            errors.append(
                f"{prefix}.blocked_by_operator_evidence requires blocked_evidence_task_ids"
            )
    if (
        item.get("evidence_resolution_state")
        == "operator_evidence_accepted_pending_preflight"
    ):
        if not item.get("accepted_return_fields"):
            errors.append(
                f"{prefix}.operator_evidence_accepted_pending_preflight "
                "requires accepted_return_fields"
            )


def validate_official_release_adoption_blocker_evidence_resolution_action_summary_item(
    item,
    errors,
    prefix,
):
    if not isinstance(item, dict):
        errors.append(f"{prefix} must be an object")
        return
    require_fields(
        errors,
        item,
        [
            "evidence_resolution_state",
            "item_count",
            "item_ids",
            "related_return_fields",
            "blocking_return_fields",
            "accepted_return_fields",
            "blocked_evidence_task_ids",
            "next_actions",
        ],
        prefix,
    )
    if (
        item.get("evidence_resolution_state")
        not in OFFICIAL_RELEASE_ADOPTION_BLOCKER_EVIDENCE_RESOLUTION_STATES
    ):
        errors.append(
            f"{prefix}.evidence_resolution_state is invalid: "
            f"{item.get('evidence_resolution_state')!r}"
        )
    require_non_negative_int(errors, item.get("item_count"), f"{prefix}.item_count")
    for name in [
        "item_ids",
        "related_return_fields",
        "blocking_return_fields",
        "accepted_return_fields",
        "blocked_evidence_task_ids",
        "next_actions",
    ]:
        require_string_list(errors, item.get(name), f"{prefix}.{name}")
    if isinstance(item.get("item_ids"), list) and item.get("item_count") != len(
        item.get("item_ids", [])
    ):
        errors.append(f"{prefix}.item_count must equal item_ids length")
    if item.get("evidence_resolution_state") == "blocked_by_operator_evidence":
        if not item.get("blocking_return_fields"):
            errors.append(
                f"{prefix}.blocked_by_operator_evidence requires blocking_return_fields"
            )
    if (
        item.get("evidence_resolution_state")
        == "operator_evidence_accepted_pending_preflight"
    ):
        if not item.get("accepted_return_fields"):
            errors.append(
                f"{prefix}.operator_evidence_accepted_pending_preflight "
                "requires accepted_return_fields"
            )


def release_stable_string_unique(values):
    result = []
    seen = set()
    for value in values:
        if not isinstance(value, str) or not value or value in seen:
            continue
        result.append(value)
        seen.add(value)
    return result


def release_string_list_or_empty(value):
    if isinstance(value, list):
        return value
    return []


def release_return_blocker_summary_state_for(field_status, blocked_item_ids):
    return return_blocker_summary_state_for(field_status, blocked_item_ids)


def release_return_field_status_blocks_adoption(field_status):
    return return_field_status_blocks_adoption(field_status)


def expected_release_return_blocker_summary(payload):
    adoption_blockers = payload.get("adoption_blockers", [])
    blockers_by_field = {}
    if isinstance(adoption_blockers, list):
        for blocker in adoption_blockers:
            if not isinstance(blocker, dict):
                continue
            for field in release_string_list_or_empty(blocker.get("return_fields", [])):
                blockers_by_field.setdefault(field, []).append(blocker)

    result = []
    field_statuses = payload.get("operator_evidence_return_field_statuses", [])
    if not isinstance(field_statuses, list):
        return result
    for status in field_statuses:
        if not isinstance(status, dict):
            continue
        field = status.get("field", "")
        related_blockers = blockers_by_field.get(field, [])
        blocking_blockers = (
            related_blockers
            if release_return_field_status_blocks_adoption(status)
            else []
        )
        related_item_ids = release_stable_string_unique(
            blocker.get("item_id", "") for blocker in related_blockers
        )
        blocked_item_ids = release_stable_string_unique(
            blocker.get("item_id", "") for blocker in blocking_blockers
        )
        result.append({
            "field": field,
            "summary_state": release_return_blocker_summary_state_for(
                status,
                blocked_item_ids,
            ),
            "provided": status.get("provided") is True,
            "value_contract_state": status.get("value_contract_state", ""),
            "field_resolution_state": status.get("field_resolution_state", ""),
            "related_adoption_item_ids": related_item_ids,
            "blocked_adoption_item_ids": blocked_item_ids,
            "blocked_adoption_item_titles": release_stable_string_unique(
                blocker.get("title", "") for blocker in blocking_blockers
            ),
            "remediation_task_ids": release_stable_string_unique(
                task_id
                for blocker in blocking_blockers
                for task_id in release_string_list_or_empty(
                    blocker.get("remediation_task_ids", [])
                )
            ),
            "accepted_evidence_task_ids": release_stable_string_unique(
                release_string_list_or_empty(status.get("accepted_evidence_task_ids", []))
            ),
            "missing_evidence_task_ids": release_stable_string_unique(
                release_string_list_or_empty(status.get("missing_evidence_task_ids", []))
            ),
            "rejected_evidence_task_ids": release_stable_string_unique(
                release_string_list_or_empty(status.get("rejected_evidence_task_ids", []))
            ),
            "blocked_evidence_task_ids": release_stable_string_unique(
                release_string_list_or_empty(status.get("blocked_evidence_task_ids", []))
            ),
            "value_contract_errors": release_stable_string_unique(
                release_string_list_or_empty(status.get("value_contract_errors", []))
            ),
            "evidence_to_return": release_stable_string_unique(
                release_string_list_or_empty(status.get("evidence_to_return", []))
                + [
                    value
                    for blocker in blocking_blockers
                    for value in release_string_list_or_empty(
                        blocker.get("evidence_to_return", [])
                    )
                ]
            ),
            "acceptance_criteria": release_stable_string_unique(
                release_string_list_or_empty(status.get("acceptance_criteria", []))
                + [
                    value
                    for blocker in blocking_blockers
                    for value in release_string_list_or_empty(
                        blocker.get("acceptance_criteria", [])
                    )
                ]
            ),
            "command_template_paths": release_stable_string_unique(
                release_string_list_or_empty(status.get("command_template_paths", []))
                + [
                    value
                    for blocker in blocking_blockers
                    for value in release_string_list_or_empty(
                        blocker.get("command_template_paths", [])
                    )
                ]
            ),
            "next_actions": release_stable_string_unique(
                release_string_list_or_empty(status.get("next_actions", []))
                + [
                    value
                    for blocker in blocking_blockers
                    for value in release_string_list_or_empty(
                        blocker.get("next_actions", [])
                    )
                ]
            ),
        })
    return result


def adoption_blocker_evidence_resolution_state_for(related_summaries, blocking_summaries):
    if blocking_summaries:
        return "blocked_by_operator_evidence"
    if related_summaries:
        return "operator_evidence_accepted_pending_preflight"
    return "not_mapped_to_operator_evidence"


def expected_release_adoption_blocker_evidence_resolution_summary(payload):
    adoption_blockers = payload.get("adoption_blockers", [])
    return_blocker_summary = payload.get("operator_evidence_return_blocker_summary", [])
    summaries_by_related_item = {}
    summaries_by_blocked_item = {}
    if isinstance(return_blocker_summary, list):
        for summary in return_blocker_summary:
            if not isinstance(summary, dict):
                continue
            for item_id in release_string_list_or_empty(
                summary.get("related_adoption_item_ids", [])
            ):
                summaries_by_related_item.setdefault(item_id, []).append(summary)
            for item_id in release_string_list_or_empty(
                summary.get("blocked_adoption_item_ids", [])
            ):
                summaries_by_blocked_item.setdefault(item_id, []).append(summary)

    result = []
    if not isinstance(adoption_blockers, list):
        return result
    for blocker in adoption_blockers:
        if not isinstance(blocker, dict):
            continue
        item_id = blocker.get("item_id", "")
        related = summaries_by_related_item.get(item_id, [])
        blocking = summaries_by_blocked_item.get(item_id, [])
        result.append({
            "item_id": item_id,
            "title": blocker.get("title", ""),
            "adoption_state": blocker.get("state", ""),
            "evidence_resolution_state": (
                adoption_blocker_evidence_resolution_state_for(
                    related,
                    blocking,
                )
            ),
            "related_return_fields": release_stable_string_unique(
                summary.get("field", "") for summary in related
            ),
            "blocking_return_fields": release_stable_string_unique(
                summary.get("field", "") for summary in blocking
            ),
            "accepted_return_fields": release_stable_string_unique(
                summary.get("field", "")
                for summary in related
                if summary.get("summary_state") == "not_blocking"
            ),
            "remediation_task_ids": release_stable_string_unique(
                release_string_list_or_empty(blocker.get("remediation_task_ids", []))
            ),
            "accepted_evidence_task_ids": release_stable_string_unique(
                task_id
                for summary in related
                for task_id in release_string_list_or_empty(
                    summary.get("accepted_evidence_task_ids", [])
                )
            ),
            "missing_evidence_task_ids": release_stable_string_unique(
                task_id
                for summary in related
                for task_id in release_string_list_or_empty(
                    summary.get("missing_evidence_task_ids", [])
                )
            ),
            "rejected_evidence_task_ids": release_stable_string_unique(
                task_id
                for summary in related
                for task_id in release_string_list_or_empty(
                    summary.get("rejected_evidence_task_ids", [])
                )
            ),
            "blocked_evidence_task_ids": release_stable_string_unique(
                task_id
                for summary in blocking
                for task_id in release_string_list_or_empty(
                    summary.get("blocked_evidence_task_ids", [])
                )
            ),
            "value_contract_states": release_stable_string_unique(
                summary.get("value_contract_state", "") for summary in related
            ),
            "field_resolution_states": release_stable_string_unique(
                summary.get("field_resolution_state", "") for summary in related
            ),
            "next_actions": release_stable_string_unique(
                action
                for summary in (blocking or related)
                for action in release_string_list_or_empty(summary.get("next_actions", []))
            ) or release_stable_string_unique(
                release_string_list_or_empty(blocker.get("next_actions", []))
            ),
        })
    return result


def expected_release_adoption_blocker_evidence_resolution_action_summary(payload):
    resolution_summary = payload.get("adoption_blocker_evidence_resolution_summary", [])
    if not isinstance(resolution_summary, list):
        return []
    state_order = [
        "blocked_by_operator_evidence",
        "operator_evidence_accepted_pending_preflight",
        "not_mapped_to_operator_evidence",
    ]
    items_by_state = {}
    extra_states = []
    for item in resolution_summary:
        if not isinstance(item, dict):
            continue
        state = item.get("evidence_resolution_state", "")
        if state not in items_by_state and state not in state_order:
            extra_states.append(state)
        items_by_state.setdefault(state, []).append(item)

    result = []
    for state in state_order + extra_states:
        items = items_by_state.get(state, [])
        if not items:
            continue
        result.append({
            "evidence_resolution_state": state,
            "item_count": len(items),
            "item_ids": release_stable_string_unique(
                item.get("item_id", "") for item in items
            ),
            "related_return_fields": release_stable_string_unique(
                field
                for item in items
                for field in release_string_list_or_empty(
                    item.get("related_return_fields", [])
                )
            ),
            "blocking_return_fields": release_stable_string_unique(
                field
                for item in items
                for field in release_string_list_or_empty(
                    item.get("blocking_return_fields", [])
                )
            ),
            "accepted_return_fields": release_stable_string_unique(
                field
                for item in items
                for field in release_string_list_or_empty(
                    item.get("accepted_return_fields", [])
                )
            ),
            "blocked_evidence_task_ids": release_stable_string_unique(
                task_id
                for item in items
                for task_id in release_string_list_or_empty(
                    item.get("blocked_evidence_task_ids", [])
                )
            ),
            "next_actions": release_stable_string_unique(
                action
                for item in items
                for action in release_string_list_or_empty(item.get("next_actions", []))
            ),
        })
    return result


def enforce_official_release_workflow_invariants(payload, errors, prefix):
    eligible = payload.get("eligible_for_default_release")
    resume_ready = payload.get("preflight_resume_ready_to_rerun")
    intake_ready = payload.get("operator_evidence_ready_to_rerun_preflight")
    expected_state = "blocked_release"
    if eligible is True:
        expected_state = "ready_for_default_release"
    elif resume_ready is True:
        expected_state = "ready_to_rerun_preflight"
    elif intake_ready is not True:
        expected_state = "blocked_operator_evidence"
    if payload.get("workflow_state") in OFFICIAL_RELEASE_WORKFLOW_STATES:
        if payload.get("workflow_state") != expected_state:
            errors.append(f"{prefix}.workflow_state must be {expected_state} for current gate states")
    operator_tasks = payload.get("operator_tasks") or []
    if isinstance(operator_tasks, list):
        if payload.get("operator_handoff_item_count") != len(operator_tasks):
            errors.append(f"{prefix}.operator_handoff_item_count must equal operator_tasks length")
    if "adoption_blockers" in payload:
        adoption_blocker_count = (
            int_or_zero(payload.get("adoption_blocked_item_count"))
            + int_or_zero(payload.get("adoption_unknown_item_count"))
        )
        blockers = payload.get("adoption_blockers")
        if isinstance(blockers, list) and len(blockers) != adoption_blocker_count:
            errors.append(
                f"{prefix}.adoption_blockers must equal blocked plus unknown adoption items"
            )
        if isinstance(blockers, list) and isinstance(payload.get("next_actions"), list):
            for blocker in blockers:
                if not isinstance(blocker, dict):
                    continue
                for action in blocker.get("next_actions", []):
                    if action not in payload["next_actions"]:
                        errors.append(
                            f"{prefix}.next_actions must include adoption_blockers next_actions"
                        )
                        break
    if "adoption_remediation_plan_path" in payload:
        if (
            isinstance(payload.get("adoption_blockers"), list)
            and "adoption_remediation_task_count" in payload
        ):
            remediation_task_ids = set()
            for blocker in payload["adoption_blockers"]:
                if isinstance(blocker, dict):
                    remediation_task_ids.update(blocker.get("remediation_task_ids", []))
            if payload.get("adoption_remediation_task_count") != len(remediation_task_ids):
                errors.append(
                    f"{prefix}.adoption_remediation_task_count must equal "
                    "distinct adoption blocker remediation_task_ids"
                )
        if (
            isinstance(payload.get("adoption_remediation_task_count"), int)
            and not isinstance(payload.get("adoption_remediation_task_count"), bool)
            and isinstance(payload.get("adoption_remediation_open_task_count"), int)
            and not isinstance(payload.get("adoption_remediation_open_task_count"), bool)
            and payload.get("adoption_remediation_open_task_count")
            > payload.get("adoption_remediation_task_count")
        ):
            errors.append(
                f"{prefix}.adoption_remediation_open_task_count must be <= "
                "adoption_remediation_task_count"
            )
    if (
        isinstance(payload.get("adoption_blockers"), list)
        and isinstance(payload.get("operator_evidence_return_field_requirements"), list)
    ):
        expected_tasks = {}
        expected_items = {}
        for blocker in payload["adoption_blockers"]:
            if not isinstance(blocker, dict):
                continue
            item_id = blocker.get("item_id", "")
            for field in blocker.get("return_fields", []):
                expected_tasks.setdefault(field, set()).update(
                    blocker.get("remediation_task_ids", [])
                )
                expected_items.setdefault(field, set()).add(item_id)
        actual_tasks = {}
        actual_items = {}
        for requirement in payload["operator_evidence_return_field_requirements"]:
            if not isinstance(requirement, dict):
                continue
            field = requirement.get("field", "")
            actual_tasks[field] = set(requirement.get("requested_task_ids", []))
            actual_items[field] = set(requirement.get("adoption_item_ids", []))
        if actual_tasks != expected_tasks:
            errors.append(
                f"{prefix}.operator_evidence_return_field_requirements must match "
                "adoption blocker return_fields"
            )
        if actual_items != expected_items:
            errors.append(
                f"{prefix}.operator_evidence_return_field_requirements adoption_item_ids "
                "must match adoption blockers"
            )
    if "operator_evidence_request_target_reference_version" in payload:
        if (
            payload.get("operator_evidence_request_target_reference_version")
            != payload.get("target_reference_version")
        ):
            errors.append(
                f"{prefix}.operator_evidence_request_target_reference_version "
                "must match target_reference_version"
            )
    if "adoption_remediation_target_reference_version" in payload:
        if (
            payload.get("adoption_remediation_target_reference_version")
            != payload.get("target_reference_version")
        ):
            errors.append(
                f"{prefix}.adoption_remediation_target_reference_version "
                "must match target_reference_version"
            )
    if "operator_evidence_return_target_reference_version" in payload:
        if (
            payload.get("operator_evidence_return_target_reference_version")
            != payload.get("target_reference_version")
        ):
            errors.append(
                f"{prefix}.operator_evidence_return_target_reference_version "
                "must match target_reference_version"
            )
    if "operator_evidence_return_workflow_report_path" in payload:
        enforce_official_release_return_workflow_report_copy_invariants(
            payload,
            errors,
            prefix,
        )
        return_state = payload.get("operator_evidence_return_state")
        return_ready = payload.get("operator_evidence_return_ready_to_rerun_preflight")
        if return_state == "ready_to_rerun_preflight" and return_ready is not True:
            errors.append(
                f"{prefix}.operator_evidence_return_ready_to_rerun_preflight "
                "must be true when operator_evidence_return_state is ready_to_rerun_preflight"
            )
        if return_state == "blocked_operator_evidence" and return_ready is not False:
            errors.append(
                f"{prefix}.operator_evidence_return_ready_to_rerun_preflight "
                "must be false when operator_evidence_return_state is blocked_operator_evidence"
            )
        field_statuses = payload.get("operator_evidence_return_field_statuses")
        if isinstance(field_statuses, list):
            for index, item in enumerate(field_statuses):
                if not isinstance(item, dict):
                    continue
                if item.get("field") != "target_reference_version":
                    continue
                values = item.get("values")
                if isinstance(values, list) and values != [payload.get("target_reference_version")]:
                    errors.append(
                        f"{prefix}.operator_evidence_return_field_statuses[{index}].values "
                        "must match target_reference_version"
                    )
        slot_values = payload.get("operator_evidence_return_submission_slot_values")
        if isinstance(slot_values, list):
            enforce_official_comparison_operator_evidence_submission_slot_value_uniqueness(
                slot_values,
                errors,
                f"{prefix}.operator_evidence_return_submission_slot_values",
            )
            submitted_slot_ids = set(
                payload.get("operator_evidence_submitted_submission_slot_ids", [])
            )
            rejected_slot_ids = set(
                payload.get("operator_evidence_rejected_submission_slot_ids", [])
            )
            missing_slot_ids = set(
                payload.get("operator_evidence_missing_submission_slot_ids", [])
            )
            not_needed_slot_ids = set(
                payload.get("operator_evidence_not_needed_submission_slot_ids", [])
            )
            known_slot_ids = (
                submitted_slot_ids
                | rejected_slot_ids
                | missing_slot_ids
                | not_needed_slot_ids
            )
            returned_slot_ids = submitted_slot_ids | rejected_slot_ids
            for item in slot_values:
                if not isinstance(item, dict):
                    continue
                slot_id = item.get("slot_id")
                if not isinstance(slot_id, str) or not slot_id:
                    continue
                if known_slot_ids and slot_id not in known_slot_ids:
                    errors.append(
                        f"{prefix}.operator_evidence_return_submission_slot_values "
                        f"slot_id must exist in submission slot ids: {slot_id}"
                    )
                    continue
                if known_slot_ids and slot_id not in returned_slot_ids:
                    errors.append(
                        f"{prefix}.operator_evidence_return_submission_slot_values "
                        f"slot_id must be submitted or rejected: {slot_id}"
                    )
            field_values = {}
            for item in field_statuses if isinstance(field_statuses, list) else []:
                if not isinstance(item, dict):
                    continue
                field_values[item.get("field", "")] = set(item.get("values", []))
            reference_slot_paths = [
                item.get("path")
                for item in slot_values
                if isinstance(item, dict)
                and item.get("return_field") == "reference_review_workflow_report_path"
            ]
            reference_paths = field_values.get("reference_review_workflow_report_path", set())
            for path in reference_slot_paths:
                if path not in reference_paths:
                    errors.append(
                        f"{prefix}.operator_evidence_return_submission_slot_values "
                        "reference path must match returned reference_review_workflow_report_path"
                    )
            run_bundle_paths = field_values.get("run_bundle_manifest_paths", set())
            for item in slot_values:
                if not isinstance(item, dict):
                    continue
                if item.get("return_field") != "run_bundle_manifest_paths":
                    continue
                if item.get("path") not in run_bundle_paths:
                    errors.append(
                        f"{prefix}.operator_evidence_return_submission_slot_values "
                        "run bundle path must match returned run_bundle_manifest_paths"
                    )
        if (
            isinstance(payload.get("adoption_blockers"), list)
            and isinstance(payload.get("operator_evidence_return_blocker_summary"), list)
        ):
            expected_summary = expected_release_return_blocker_summary(payload)
            if payload.get("operator_evidence_return_blocker_summary") != expected_summary:
                errors.append(
                    f"{prefix}.operator_evidence_return_blocker_summary must match "
                    "operator_evidence_return_field_statuses and adoption_blockers"
                )
        if (
            isinstance(payload.get("adoption_blockers"), list)
            and isinstance(payload.get("operator_evidence_return_blocker_summary"), list)
            and isinstance(
                payload.get("adoption_blocker_evidence_resolution_summary"),
                list,
            )
        ):
            expected_resolution_summary = (
                expected_release_adoption_blocker_evidence_resolution_summary(payload)
            )
            if (
                payload.get("adoption_blocker_evidence_resolution_summary")
                != expected_resolution_summary
            ):
                errors.append(
                    f"{prefix}.adoption_blocker_evidence_resolution_summary must match "
                    "operator_evidence_return_blocker_summary and adoption_blockers"
                )
        if (
            isinstance(payload.get("adoption_blocker_evidence_resolution_summary"), list)
            and isinstance(
                payload.get("adoption_blocker_evidence_resolution_action_summary"),
                list,
            )
        ):
            expected_action_summary = (
                expected_release_adoption_blocker_evidence_resolution_action_summary(
                    payload
                )
            )
            if (
                payload.get("adoption_blocker_evidence_resolution_action_summary")
                != expected_action_summary
            ):
                errors.append(
                    f"{prefix}.adoption_blocker_evidence_resolution_action_summary "
                    "must match adoption_blocker_evidence_resolution_summary"
                )
    if eligible is True and payload.get("release_state") != "ready_for_default_release":
        errors.append(f"{prefix}.eligible workflow requires release_state=ready_for_default_release")
    if eligible is not True:
        if not payload.get("blocking_gates") and payload.get("workflow_state") != "ready_to_rerun_preflight":
            errors.append(f"{prefix}.blocked workflow requires blocking_gates")
        if not payload.get("next_actions"):
            errors.append(f"{prefix}.blocked workflow requires next_actions")


def validate_official_release_artifact_audit_report(payload, errors, prefix):
    require_fields(
        errors,
        payload,
        [
            "audit_state",
            "release_workflow_report_path",
            "release_workflow_state",
            "release_state",
            "eligible_for_default_release",
            "operator_evidence_intake_state",
            "operator_evidence_ready_to_rerun_preflight",
            "operator_evidence_accepted_item_count",
            "operator_evidence_missing_item_count",
            "operator_evidence_rejected_item_count",
            "preflight_resume_plan_state",
            "preflight_resume_ready_to_rerun",
            "adoption_state",
            "adoption_passed_item_count",
            "adoption_blocked_item_count",
            "adoption_unknown_item_count",
            "adoption_remediation_plan_state",
            "adoption_remediation_open_task_count",
            "artifact_count",
            "valid_artifact_count",
            "missing_artifact_count",
            "invalid_artifact_count",
            "artifacts",
            "blocking_reasons",
            "next_actions",
            "evidence_paths",
            "markdown_report_path",
            "html_report_path",
        ],
        prefix,
    )
    audit_state = payload.get("audit_state")
    if audit_state not in OFFICIAL_RELEASE_ARTIFACT_AUDIT_STATES:
        errors.append(f"{prefix}.audit_state is invalid: {audit_state!r}")
    if payload.get("release_workflow_state") not in OFFICIAL_RELEASE_WORKFLOW_STATES:
        errors.append(
            f"{prefix}.release_workflow_state is invalid: "
            f"{payload.get('release_workflow_state')!r}"
        )
    if payload.get("release_state") not in OFFICIAL_COMPARISON_RELEASE_GATE_STATES:
        errors.append(f"{prefix}.release_state is invalid: {payload.get('release_state')!r}")
    if payload.get("operator_evidence_intake_state") not in (
        OFFICIAL_COMPARISON_OPERATOR_EVIDENCE_INTAKE_STATES
    ):
        errors.append(
            f"{prefix}.operator_evidence_intake_state is invalid: "
            f"{payload.get('operator_evidence_intake_state')!r}"
        )
    if payload.get("preflight_resume_plan_state") not in (
        OFFICIAL_COMPARISON_PREFLIGHT_RESUME_PLAN_STATES
    ):
        errors.append(
            f"{prefix}.preflight_resume_plan_state is invalid: "
            f"{payload.get('preflight_resume_plan_state')!r}"
        )
    require_type(
        errors,
        payload.get("eligible_for_default_release"),
        bool,
        f"{prefix}.eligible_for_default_release",
    )
    require_type(
        errors,
        payload.get("operator_evidence_ready_to_rerun_preflight"),
        bool,
        f"{prefix}.operator_evidence_ready_to_rerun_preflight",
    )
    require_type(
        errors,
        payload.get("preflight_resume_ready_to_rerun"),
        bool,
        f"{prefix}.preflight_resume_ready_to_rerun",
    )
    if payload.get("adoption_state"):
        if payload.get("adoption_state") not in OFFICIAL_COMPARISON_ADOPTION_STATES:
            errors.append(
                f"{prefix}.adoption_state is invalid: {payload.get('adoption_state')!r}"
            )
    if payload.get("adoption_remediation_plan_state"):
        if (
            payload.get("adoption_remediation_plan_state")
            not in OFFICIAL_COMPARISON_ADOPTION_REMEDIATION_PLAN_STATES
        ):
            errors.append(
                f"{prefix}.adoption_remediation_plan_state is invalid: "
                f"{payload.get('adoption_remediation_plan_state')!r}"
            )
    for name in [
        "release_workflow_report_path",
        "markdown_report_path",
        "html_report_path",
    ]:
        require_non_empty_string(errors, payload.get(name), f"{prefix}.{name}")
    for name in [
        "artifact_count",
        "valid_artifact_count",
        "missing_artifact_count",
        "invalid_artifact_count",
        "operator_evidence_accepted_item_count",
        "operator_evidence_missing_item_count",
        "operator_evidence_rejected_item_count",
        "adoption_passed_item_count",
        "adoption_blocked_item_count",
        "adoption_unknown_item_count",
        "adoption_remediation_open_task_count",
    ]:
        require_non_negative_int(errors, payload.get(name), f"{prefix}.{name}")
    for name in ["blocking_reasons", "next_actions", "evidence_paths"]:
        require_string_list(errors, payload.get(name), f"{prefix}.{name}")
    require_type(errors, payload.get("artifacts"), list, f"{prefix}.artifacts")
    if isinstance(payload.get("artifacts"), list):
        for index, artifact in enumerate(payload["artifacts"]):
            validate_official_release_artifact_entry(
                artifact,
                errors,
                f"{prefix}.artifacts[{index}]",
            )
    enforce_official_release_artifact_audit_invariants(payload, errors, prefix)


def validate_official_release_artifact_entry(artifact, errors, prefix):
    if not isinstance(artifact, dict):
        errors.append(f"{prefix} must be an object")
        return
    require_fields(
        errors,
        artifact,
        [
            "field",
            "path",
            "artifact_kind",
            "expected_manifest_type",
            "state",
            "errors",
        ],
        prefix,
    )
    for name in ["field", "artifact_kind", "expected_manifest_type", "state"]:
        require_non_empty_string(errors, artifact.get(name), f"{prefix}.{name}")
    if artifact.get("artifact_kind") not in OFFICIAL_RELEASE_ARTIFACT_KINDS:
        errors.append(
            f"{prefix}.artifact_kind is invalid: {artifact.get('artifact_kind')!r}"
        )
    require_type(errors, artifact.get("path"), str, f"{prefix}.path")
    if artifact.get("state") not in OFFICIAL_RELEASE_ARTIFACT_STATES:
        errors.append(f"{prefix}.state is invalid: {artifact.get('state')!r}")
    require_string_list(errors, artifact.get("errors"), f"{prefix}.errors")
    if artifact.get("artifact_kind") == "file" and artifact.get("expected_manifest_type") != "file":
        errors.append(f"{prefix}.file artifact requires expected_manifest_type=file")
    if (
        artifact.get("artifact_kind") == "json_manifest"
        and artifact.get("expected_manifest_type") == "file"
    ):
        errors.append(f"{prefix}.json_manifest artifact requires a manifest type")
    if artifact.get("state") == "not_applicable" and artifact.get("path"):
        errors.append(f"{prefix}.not_applicable artifact requires empty path")
    if artifact.get("state") in {"valid", "missing", "invalid"}:
        require_non_empty_string(errors, artifact.get("path"), f"{prefix}.path")
    if artifact.get("state") in {"missing", "invalid"} and not artifact.get("errors"):
        errors.append(f"{prefix}.{artifact.get('state')} artifact requires errors")


def enforce_official_release_artifact_audit_invariants(payload, errors, prefix):
    artifacts = payload.get("artifacts")
    if not isinstance(artifacts, list):
        return
    countable = [
        artifact
        for artifact in artifacts
        if isinstance(artifact, dict) and artifact.get("state") != "not_applicable"
    ]
    state_counts = {
        "valid": 0,
        "missing": 0,
        "invalid": 0,
    }
    for artifact in countable:
        state = artifact.get("state")
        if state in state_counts:
            state_counts[state] += 1
    if payload.get("artifact_count") != len(countable):
        errors.append(f"{prefix}.artifact_count must equal applicable artifacts")
    if payload.get("valid_artifact_count") != state_counts["valid"]:
        errors.append(f"{prefix}.valid_artifact_count must equal valid artifacts")
    if payload.get("missing_artifact_count") != state_counts["missing"]:
        errors.append(f"{prefix}.missing_artifact_count must equal missing artifacts")
    if payload.get("invalid_artifact_count") != state_counts["invalid"]:
        errors.append(f"{prefix}.invalid_artifact_count must equal invalid artifacts")

    invalid_count = int_or_zero(payload.get("invalid_artifact_count"))
    missing_count = int_or_zero(payload.get("missing_artifact_count"))
    audit_state = payload.get("audit_state")
    if invalid_count > 0:
        if audit_state != "blocked_invalid_artifact":
            errors.append(
                f"{prefix}.audit_state must be blocked_invalid_artifact "
                "when invalid artifacts exist"
            )
    elif missing_count > 0:
        if audit_state != "blocked_missing_artifact":
            errors.append(
                f"{prefix}.audit_state must be blocked_missing_artifact "
                "when missing artifacts exist"
            )
    elif audit_state != "ready_for_artifact_review":
        errors.append(
            f"{prefix}.audit_state must be ready_for_artifact_review "
            "when all applicable artifacts are valid"
        )
    if audit_state == "ready_for_artifact_review" and payload.get("blocking_reasons"):
        errors.append(f"{prefix}.ready artifact audit requires empty blocking_reasons")
    if audit_state != "ready_for_artifact_review":
        if not payload.get("blocking_reasons"):
            errors.append(f"{prefix}.blocked artifact audit requires blocking_reasons")
        if not payload.get("next_actions"):
            errors.append(f"{prefix}.blocked artifact audit requires next_actions")


def validate_official_comparison_adoption_checklist_report(payload, errors, prefix):
    require_fields(
        errors,
        payload,
        [
            "adoption_state",
            "release_workflow_report_path",
            "preflight_workflow_report_path",
            "decision_workflow_report_path",
            "release_state",
            "workflow_state",
            "eligible_for_default_release",
            "checklist_item_count",
            "passed_item_count",
            "blocked_item_count",
            "unknown_item_count",
            "checklist_items",
            "blocking_gates",
            "blocking_reasons",
            "next_actions",
            "evidence_paths",
            "markdown_report_path",
            "html_report_path",
        ],
        prefix,
    )
    if payload.get("adoption_state") not in OFFICIAL_COMPARISON_ADOPTION_STATES:
        errors.append(f"{prefix}.adoption_state is invalid: {payload.get('adoption_state')!r}")
    if payload.get("release_state") not in OFFICIAL_COMPARISON_RELEASE_GATE_STATES:
        errors.append(f"{prefix}.release_state is invalid: {payload.get('release_state')!r}")
    if payload.get("workflow_state") not in OFFICIAL_RELEASE_WORKFLOW_STATES:
        errors.append(f"{prefix}.workflow_state is invalid: {payload.get('workflow_state')!r}")
    require_type(
        errors,
        payload.get("eligible_for_default_release"),
        bool,
        f"{prefix}.eligible_for_default_release",
    )
    for name in [
        "release_workflow_report_path",
        "preflight_workflow_report_path",
        "decision_workflow_report_path",
        "markdown_report_path",
        "html_report_path",
    ]:
        require_non_empty_string(errors, payload.get(name), f"{prefix}.{name}")
    if "release_artifact_audit_report_path" in payload:
        require_type(
            errors,
            payload.get("release_artifact_audit_report_path"),
            str,
            f"{prefix}.release_artifact_audit_report_path",
        )
    for name in [
        "checklist_item_count",
        "passed_item_count",
        "blocked_item_count",
        "unknown_item_count",
    ]:
        require_non_negative_int(errors, payload.get(name), f"{prefix}.{name}")
    for name in ["blocking_gates", "blocking_reasons", "next_actions", "evidence_paths"]:
        require_string_list(errors, payload.get(name), f"{prefix}.{name}")
    require_type(errors, payload.get("checklist_items"), list, f"{prefix}.checklist_items")
    if isinstance(payload.get("checklist_items"), list):
        for index, item in enumerate(payload["checklist_items"]):
            validate_official_comparison_adoption_checklist_item(
                item,
                errors,
                f"{prefix}.checklist_items[{index}]",
            )
    enforce_official_comparison_adoption_checklist_invariants(payload, errors, prefix)


def validate_official_comparison_adoption_checklist_item(item, errors, prefix):
    if not isinstance(item, dict):
        errors.append(f"{prefix} must be an object")
        return
    require_fields(
        errors,
        item,
        [
            "item_id",
            "title",
            "state",
            "evidence_paths",
            "reasons",
            "next_actions",
        ],
        prefix,
    )
    if item.get("state") not in OFFICIAL_COMPARISON_ADOPTION_CHECKLIST_ITEM_STATES:
        errors.append(f"{prefix}.state is invalid: {item.get('state')!r}")
    for name in ["item_id", "title"]:
        require_non_empty_string(errors, item.get(name), f"{prefix}.{name}")
    for name in ["evidence_paths", "reasons", "next_actions"]:
        require_string_list(errors, item.get(name), f"{prefix}.{name}")


def enforce_official_comparison_adoption_checklist_invariants(payload, errors, prefix):
    items = payload.get("checklist_items") or []
    if isinstance(items, list):
        passed_count = sum(
            1 for item in items if isinstance(item, dict) and item.get("state") == "passed"
        )
        blocked_count = sum(
            1 for item in items if isinstance(item, dict) and item.get("state") == "blocked"
        )
        unknown_count = sum(
            1 for item in items if isinstance(item, dict) and item.get("state") == "unknown"
        )
        if payload.get("checklist_item_count") != len(items):
            errors.append(f"{prefix}.checklist_item_count must equal checklist_items length")
        if payload.get("passed_item_count") != passed_count:
            errors.append(f"{prefix}.passed_item_count must equal passed checklist items")
        if payload.get("blocked_item_count") != blocked_count:
            errors.append(f"{prefix}.blocked_item_count must equal blocked checklist items")
        if payload.get("unknown_item_count") != unknown_count:
            errors.append(f"{prefix}.unknown_item_count must equal unknown checklist items")
    if payload.get("adoption_state") == "ready_for_official_adoption":
        if payload.get("eligible_for_default_release") is not True:
            errors.append(
                f"{prefix}.ready_for_official_adoption requires eligible_for_default_release=true"
            )
        if int_or_zero(payload.get("blocked_item_count")) or int_or_zero(
            payload.get("unknown_item_count")
        ):
            errors.append(
                f"{prefix}.ready_for_official_adoption requires no blocked or unknown items"
            )
        if payload.get("blocking_gates") or payload.get("blocking_reasons"):
            errors.append(
                f"{prefix}.ready_for_official_adoption requires no blocking gates or reasons"
            )
    if payload.get("adoption_state") == "blocked_official_adoption":
        if not payload.get("blocking_gates") and not payload.get("blocking_reasons"):
            errors.append(
                f"{prefix}.blocked_official_adoption requires blocking gates or reasons"
            )


def validate_official_comparison_adoption_remediation_plan(payload, errors, prefix):
    require_fields(
        errors,
        payload,
        [
            "plan_state",
            "adoption_state",
            "target_reference_version",
            "adoption_checklist_report_path",
            "release_workflow_report_path",
            "operator_evidence_request_report_path",
            "operator_evidence_return_template_path",
            "operator_evidence_return_guide_markdown_path",
            "operator_evidence_return_guide_html_path",
            "operator_evidence_return_workflow_command_template_path",
            "operator_evidence_intake_command_template_path",
            "operator_evidence_release_workflow_command_template_path",
            "command_template_paths",
            "task_count",
            "open_task_count",
            "not_needed_task_count",
            "return_field_requirements",
            "tasks",
            "blocking_gates",
            "blocking_reasons",
            "next_actions",
            "evidence_paths",
            "markdown_report_path",
            "html_report_path",
        ],
        prefix,
    )
    if payload.get("plan_state") not in OFFICIAL_COMPARISON_ADOPTION_REMEDIATION_PLAN_STATES:
        errors.append(f"{prefix}.plan_state is invalid: {payload.get('plan_state')!r}")
    if payload.get("adoption_state") not in OFFICIAL_COMPARISON_ADOPTION_STATES:
        errors.append(f"{prefix}.adoption_state is invalid: {payload.get('adoption_state')!r}")
    for name in [
        "target_reference_version",
        "adoption_checklist_report_path",
        "release_workflow_report_path",
        "markdown_report_path",
        "html_report_path",
    ]:
        require_non_empty_string(errors, payload.get(name), f"{prefix}.{name}")
    for name in [
        "operator_evidence_request_report_path",
        "operator_evidence_return_template_path",
        "operator_evidence_return_guide_markdown_path",
        "operator_evidence_return_guide_html_path",
        "operator_evidence_return_workflow_command_template_path",
        "operator_evidence_intake_command_template_path",
        "operator_evidence_release_workflow_command_template_path",
    ]:
        require_type(errors, payload.get(name), str, f"{prefix}.{name}")
    require_string_list(
        errors,
        payload.get("command_template_paths"),
        f"{prefix}.command_template_paths",
    )
    if isinstance(payload.get("command_template_paths"), list):
        for name in [
            "operator_evidence_return_workflow_command_template_path",
            "operator_evidence_intake_command_template_path",
            "operator_evidence_release_workflow_command_template_path",
        ]:
            if payload.get(name) and payload.get(name) not in payload["command_template_paths"]:
                errors.append(f"{prefix}.command_template_paths must include {name}")
    for name in ["task_count", "open_task_count", "not_needed_task_count"]:
        require_non_negative_int(errors, payload.get(name), f"{prefix}.{name}")
    require_type(errors, payload.get("tasks"), list, f"{prefix}.tasks")
    if isinstance(payload.get("tasks"), list):
        for index, task in enumerate(payload["tasks"]):
            validate_official_comparison_adoption_remediation_task(
                task,
                errors,
                f"{prefix}.tasks[{index}]",
            )
    require_type(
        errors,
        payload.get("return_field_requirements"),
        list,
        f"{prefix}.return_field_requirements",
    )
    if isinstance(payload.get("return_field_requirements"), list):
        for index, item in enumerate(payload["return_field_requirements"]):
            validate_official_comparison_operator_evidence_request_field_requirement(
                item,
                errors,
                f"{prefix}.return_field_requirements[{index}]",
            )
    for name in ["blocking_gates", "blocking_reasons", "next_actions", "evidence_paths"]:
        require_string_list(errors, payload.get(name), f"{prefix}.{name}")
    enforce_official_comparison_adoption_remediation_invariants(payload, errors, prefix)


def validate_official_comparison_adoption_remediation_task(task, errors, prefix):
    if not isinstance(task, dict):
        errors.append(f"{prefix} must be an object")
        return
    require_fields(
        errors,
        task,
        [
            "task_id",
            "title",
            "task_state",
            "request_state",
            "execution_status",
            "evidence_state",
            "adoption_item_ids",
            "operator_action",
            "evidence_to_return",
            "return_fields",
            "acceptance_criteria",
            "reasons",
            "next_actions",
            "source_paths",
            "evidence_paths",
            "command_template_paths",
        ],
        prefix,
    )
    for name in ["task_id", "title", "task_state"]:
        require_non_empty_string(errors, task.get(name), f"{prefix}.{name}")
    if task.get("task_state") not in OFFICIAL_COMPARISON_ADOPTION_REMEDIATION_TASK_STATES:
        errors.append(f"{prefix}.task_state is invalid: {task.get('task_state')!r}")
    for name in [
        "request_state",
        "execution_status",
        "evidence_state",
        "operator_action",
    ]:
        require_type(errors, task.get(name), str, f"{prefix}.{name}")
    for name in [
        "adoption_item_ids",
        "evidence_to_return",
        "return_fields",
        "acceptance_criteria",
        "reasons",
        "next_actions",
        "source_paths",
        "evidence_paths",
        "command_template_paths",
    ]:
        require_string_list(errors, task.get(name), f"{prefix}.{name}")
    if task.get("task_state") == "open":
        if not task.get("adoption_item_ids"):
            errors.append(f"{prefix}.open task requires adoption_item_ids")
        if not task.get("evidence_to_return"):
            errors.append(f"{prefix}.open task requires evidence_to_return")
        if not task.get("acceptance_criteria"):
            errors.append(f"{prefix}.open task requires acceptance_criteria")


def enforce_official_comparison_adoption_remediation_invariants(payload, errors, prefix):
    tasks = payload.get("tasks") or []
    if isinstance(tasks, list):
        open_count = sum(
            1 for task in tasks if isinstance(task, dict) and task.get("task_state") == "open"
        )
        not_needed_count = sum(
            1
            for task in tasks
            if isinstance(task, dict) and task.get("task_state") == "not_needed"
        )
        if payload.get("task_count") != len(tasks):
            errors.append(f"{prefix}.task_count must equal tasks length")
        if payload.get("open_task_count") != open_count:
            errors.append(f"{prefix}.open_task_count must equal open tasks")
        if payload.get("not_needed_task_count") != not_needed_count:
            errors.append(f"{prefix}.not_needed_task_count must equal not_needed tasks")
    field_requirements = payload.get("return_field_requirements") or []
    if isinstance(tasks, list) and isinstance(field_requirements, list):
        expected_tasks = {}
        expected_requested_tasks = {}
        expected_adoption_items = {}
        for task in tasks:
            if not isinstance(task, dict):
                continue
            task_id = task.get("task_id", "")
            for field in task.get("return_fields", []):
                expected_tasks.setdefault(field, set()).add(task_id)
                if task.get("request_state") == "requested":
                    expected_requested_tasks.setdefault(field, set()).add(task_id)
                expected_adoption_items.setdefault(field, set()).update(
                    task.get("adoption_item_ids", [])
                )
        actual_tasks = {
            item.get("field", ""): set(item.get("task_ids", []))
            for item in field_requirements
            if isinstance(item, dict)
        }
        actual_requested_tasks = {
            item.get("field", ""): set(item.get("requested_task_ids", []))
            for item in field_requirements
            if isinstance(item, dict)
        }
        actual_adoption_items = {
            item.get("field", ""): set(item.get("adoption_item_ids", []))
            for item in field_requirements
            if isinstance(item, dict)
        }
        if actual_tasks != expected_tasks:
            errors.append(
                f"{prefix}.return_field_requirements must match task return_fields"
            )
        if actual_requested_tasks != expected_requested_tasks:
            errors.append(
                f"{prefix}.return_field_requirements requested_task_ids must match tasks"
            )
        if actual_adoption_items != expected_adoption_items:
            errors.append(
                f"{prefix}.return_field_requirements adoption_item_ids must match tasks"
            )
    if payload.get("plan_state") == "ready_for_official_adoption":
        if payload.get("adoption_state") != "ready_for_official_adoption":
            errors.append(
                f"{prefix}.ready_for_official_adoption requires adoption_state=ready_for_official_adoption"
            )
        if int_or_zero(payload.get("open_task_count")):
            errors.append(
                f"{prefix}.ready_for_official_adoption requires open_task_count=0"
            )
    if payload.get("plan_state") == "ready_to_collect_evidence":
        if payload.get("adoption_state") != "blocked_official_adoption":
            errors.append(
                f"{prefix}.ready_to_collect_evidence requires adoption_state=blocked_official_adoption"
            )
        if int_or_zero(payload.get("open_task_count")) <= 0:
            errors.append(
                f"{prefix}.ready_to_collect_evidence requires open_task_count > 0"
            )
    if payload.get("plan_state") == "blocked_no_remediation_path":
        if int_or_zero(payload.get("open_task_count")):
            errors.append(
                f"{prefix}.blocked_no_remediation_path requires open_task_count=0"
            )
        if not payload.get("blocking_reasons"):
            errors.append(
                f"{prefix}.blocked_no_remediation_path requires blocking_reasons"
            )


def validate_official_comparison_engine_evidence_audit_report(payload, errors, prefix):
    require_fields(
        errors,
        payload,
        [
            "audit_state",
            "workflow_report_path",
            "workflow_state",
            "reference_version",
            "conversion_reference_version",
            "required_engine_ids",
            "missing_engine_ids",
            "candidate_count",
            "usable_candidate_count",
            "blocked_candidate_count",
            "target_statuses",
            "candidates",
            "conversion_commands",
            "blocking_gates",
            "next_actions",
            "evidence_paths",
            "markdown_report_path",
            "html_report_path",
        ],
        prefix,
    )
    audit_state = payload.get("audit_state")
    if audit_state not in OFFICIAL_COMPARISON_ENGINE_EVIDENCE_AUDIT_STATES:
        errors.append(f"{prefix}.audit_state is invalid: {audit_state!r}")
    if payload.get("workflow_state") not in OFFICIAL_COMPARISON_PREFLIGHT_WORKFLOW_STATES:
        errors.append(f"{prefix}.workflow_state is invalid: {payload.get('workflow_state')!r}")
    for name in [
        "workflow_report_path",
        "reference_version",
        "conversion_reference_version",
        "markdown_report_path",
        "html_report_path",
    ]:
        require_non_empty_string(errors, payload.get(name), f"{prefix}.{name}")
    for name in [
        "required_engine_ids",
        "missing_engine_ids",
        "conversion_commands",
        "blocking_gates",
        "next_actions",
        "evidence_paths",
    ]:
        require_string_list(errors, payload.get(name), f"{prefix}.{name}")
    for name in ["candidate_count", "usable_candidate_count", "blocked_candidate_count"]:
        require_non_negative_int(errors, payload.get(name), f"{prefix}.{name}")
    require_type(errors, payload.get("target_statuses"), list, f"{prefix}.target_statuses")
    if isinstance(payload.get("target_statuses"), list):
        for index, status in enumerate(payload["target_statuses"]):
            validate_official_comparison_engine_evidence_target_status(
                status,
                errors,
                f"{prefix}.target_statuses[{index}]",
            )
    require_type(errors, payload.get("candidates"), list, f"{prefix}.candidates")
    if isinstance(payload.get("candidates"), list):
        for index, candidate in enumerate(payload["candidates"]):
            validate_official_comparison_engine_evidence_candidate(
                candidate,
                errors,
                f"{prefix}.candidates[{index}]",
            )
    enforce_official_comparison_engine_evidence_audit_invariants(payload, errors, prefix)


def validate_official_comparison_engine_evidence_target_status(status, errors, prefix):
    if not isinstance(status, dict):
        errors.append(f"{prefix} must be an object")
        return
    require_fields(
        errors,
        status,
        [
            "engine_id",
            "state",
            "candidate_count",
            "best_candidate_id",
            "next_action",
        ],
        prefix,
    )
    require_non_empty_string(errors, status.get("engine_id"), f"{prefix}.engine_id")
    if status.get("state") not in OFFICIAL_COMPARISON_ENGINE_EVIDENCE_TARGET_STATES:
        errors.append(f"{prefix}.state is invalid: {status.get('state')!r}")
    require_non_negative_int(errors, status.get("candidate_count"), f"{prefix}.candidate_count")
    require_type(errors, status.get("best_candidate_id"), str, f"{prefix}.best_candidate_id")
    require_non_empty_string(errors, status.get("next_action"), f"{prefix}.next_action")


def validate_official_comparison_engine_evidence_candidate(candidate, errors, prefix):
    if not isinstance(candidate, dict):
        errors.append(f"{prefix} must be an object")
        return
    require_fields(
        errors,
        candidate,
        [
            "candidate_id",
            "path",
            "artifact_type",
            "target_engine_id",
            "observed_engine_ids",
            "canonical_engine_ids",
            "classification",
            "official_bundle_input_ready",
            "health_status",
            "sample_count",
            "dry_run",
            "summary_row_count",
            "run_status_counts",
            "conversion_command",
            "reasons",
            "next_actions",
            "evidence_paths",
        ],
        prefix,
    )
    for name in [
        "candidate_id",
        "path",
        "artifact_type",
        "target_engine_id",
        "classification",
        "health_status",
    ]:
        require_non_empty_string(errors, candidate.get(name), f"{prefix}.{name}")
    require_type(
        errors,
        candidate.get("official_bundle_input_ready"),
        bool,
        f"{prefix}.official_bundle_input_ready",
    )
    require_non_negative_int(errors, candidate.get("sample_count"), f"{prefix}.sample_count")
    require_type(errors, candidate.get("dry_run"), bool, f"{prefix}.dry_run")
    require_non_negative_int(errors, candidate.get("summary_row_count"), f"{prefix}.summary_row_count")
    require_type(errors, candidate.get("run_status_counts"), dict, f"{prefix}.run_status_counts")
    require_type(errors, candidate.get("conversion_command"), str, f"{prefix}.conversion_command")
    for name in ["observed_engine_ids", "canonical_engine_ids", "reasons", "next_actions", "evidence_paths"]:
        require_string_list(errors, candidate.get(name), f"{prefix}.{name}")


def enforce_official_comparison_engine_evidence_audit_invariants(payload, errors, prefix):
    candidates = payload.get("candidates") if isinstance(payload.get("candidates"), list) else []
    target_statuses = (
        payload.get("target_statuses") if isinstance(payload.get("target_statuses"), list) else []
    )
    candidate_count = payload.get("candidate_count")
    usable_candidate_count = payload.get("usable_candidate_count")
    blocked_candidate_count = payload.get("blocked_candidate_count")
    if isinstance(candidate_count, int) and candidate_count != len(candidates):
        errors.append(f"{prefix}.candidate_count must equal candidates length")
    if isinstance(usable_candidate_count, int):
        actual_usable = sum(
            1
            for candidate in candidates
            if isinstance(candidate, dict) and candidate.get("official_bundle_input_ready") is True
        )
        if usable_candidate_count != actual_usable:
            errors.append(f"{prefix}.usable_candidate_count must equal ready candidate count")
    if isinstance(blocked_candidate_count, int):
        actual_blocked = sum(
            1
            for candidate in candidates
            if isinstance(candidate, dict) and candidate.get("official_bundle_input_ready") is not True
        )
        if blocked_candidate_count != actual_blocked:
            errors.append(f"{prefix}.blocked_candidate_count must equal blocked candidate count")
    target_engine_ids = [
        status.get("engine_id")
        for status in target_statuses
        if isinstance(status, dict) and isinstance(status.get("engine_id"), str)
    ]
    required_engine_ids = payload.get("required_engine_ids")
    if isinstance(required_engine_ids, list) and target_engine_ids != required_engine_ids:
        errors.append(f"{prefix}.target_statuses must follow required_engine_ids order")
    audit_state = payload.get("audit_state")
    if audit_state == "no_candidates" and candidates:
        errors.append(f"{prefix}.no_candidates state requires empty candidates")
    if audit_state == "ready_to_convert":
        not_ready = [
            status.get("engine_id")
            for status in target_statuses
            if isinstance(status, dict) and status.get("state") != "ready_to_convert"
        ]
        if not_ready:
            errors.append(f"{prefix}.ready_to_convert state requires all target statuses ready")
    if audit_state == "blocked_evidence_gaps":
        has_gap = any(
            isinstance(status, dict) and status.get("state") != "ready_to_convert"
            for status in target_statuses
        )
        if not has_gap:
            errors.append(f"{prefix}.blocked_evidence_gaps state requires at least one target gap")


def validate_product_path_official_run_plan(payload, errors, prefix):
    require_fields(
        errors,
        payload,
        [
            "plan_state",
            "workflow_report_path",
            "product_path_readiness_report_path",
            "engine_lane_matrix_path",
            "reference_version",
            "target_sample_set",
            "product_path_readiness_state",
            "candidate_engine_ids",
            "action_count",
            "dry_run_contract_valid_count",
            "dry_run_contract_missing_count",
            "dry_run_contract_invalid_count",
            "actions",
            "commands",
            "command_template_paths",
            "manual_evidence_needed",
            "next_actions",
            "evidence_paths",
            "markdown_report_path",
            "html_report_path",
        ],
        prefix,
    )
    plan_state = payload.get("plan_state")
    if plan_state not in PRODUCT_PATH_OFFICIAL_RUN_PLAN_STATES:
        errors.append(f"{prefix}.plan_state is invalid: {plan_state!r}")
    if payload.get("product_path_readiness_state") not in PRODUCT_PATH_READINESS_STATES:
        errors.append(
            f"{prefix}.product_path_readiness_state is invalid: "
            f"{payload.get('product_path_readiness_state')!r}"
        )
    for name in [
        "workflow_report_path",
        "product_path_readiness_report_path",
        "engine_lane_matrix_path",
        "reference_version",
        "target_sample_set",
        "markdown_report_path",
        "html_report_path",
    ]:
        require_non_empty_string(errors, payload.get(name), f"{prefix}.{name}")
    for name in [
        "candidate_engine_ids",
        "commands",
        "command_template_paths",
        "manual_evidence_needed",
        "next_actions",
        "evidence_paths",
    ]:
        require_string_list(errors, payload.get(name), f"{prefix}.{name}")
    require_non_negative_int(errors, payload.get("action_count"), f"{prefix}.action_count")
    for name in [
        "dry_run_contract_valid_count",
        "dry_run_contract_missing_count",
        "dry_run_contract_invalid_count",
    ]:
        require_non_negative_int(errors, payload.get(name), f"{prefix}.{name}")
    require_type(errors, payload.get("actions"), list, f"{prefix}.actions")
    if isinstance(payload.get("actions"), list):
        for index, action in enumerate(payload["actions"]):
            validate_product_path_official_run_action(action, errors, f"{prefix}.actions[{index}]")
        if payload.get("action_count") != len(payload["actions"]):
            errors.append(f"{prefix}.action_count must equal actions length")
    enforce_product_path_official_run_plan_invariants(payload, errors, prefix)


def validate_product_path_official_run_action(action, errors, prefix):
    if not isinstance(action, dict):
        errors.append(f"{prefix} must be an object")
        return
    require_fields(
        errors,
        action,
        [
            "engine_id",
            "role",
            "product_path_supported",
            "real_run_required",
            "user_impact_metric_required",
            "dry_run_contract_manifest_path",
            "dry_run_contract_state",
            "dry_run_contract_errors",
            "dry_run_contract_command",
            "conversion_command_template",
            "evidence_needed",
            "next_action",
        ],
        prefix,
    )
    for name in [
        "engine_id",
        "role",
        "dry_run_contract_manifest_path",
        "dry_run_contract_state",
        "dry_run_contract_command",
        "conversion_command_template",
        "next_action",
    ]:
        require_non_empty_string(errors, action.get(name), f"{prefix}.{name}")
    for name in ["product_path_supported", "real_run_required", "user_impact_metric_required"]:
        require_type(errors, action.get(name), bool, f"{prefix}.{name}")
    if action.get("dry_run_contract_state") not in PRODUCT_PATH_DRY_RUN_CONTRACT_STATES:
        errors.append(
            f"{prefix}.dry_run_contract_state is invalid: "
            f"{action.get('dry_run_contract_state')!r}"
        )
    require_string_list(
        errors,
        action.get("dry_run_contract_errors"),
        f"{prefix}.dry_run_contract_errors",
    )
    if (
        action.get("dry_run_contract_state") == "valid"
        and action.get("dry_run_contract_errors")
    ):
        errors.append(f"{prefix}.valid dry-run contract must not have errors")
    if (
        action.get("dry_run_contract_state") == "invalid"
        and not action.get("dry_run_contract_errors")
    ):
        errors.append(f"{prefix}.invalid dry-run contract requires errors")
    require_string_list(errors, action.get("evidence_needed"), f"{prefix}.evidence_needed")


def enforce_product_path_official_run_plan_invariants(payload, errors, prefix):
    plan_state = payload.get("plan_state")
    readiness_state = payload.get("product_path_readiness_state")
    actions = payload.get("actions") if isinstance(payload.get("actions"), list) else []
    commands = payload.get("commands") if isinstance(payload.get("commands"), list) else []
    manual_evidence = (
        payload.get("manual_evidence_needed")
        if isinstance(payload.get("manual_evidence_needed"), list)
        else []
    )
    if readiness_state == "ready_for_product_path_default_gate":
        expected_state = "no_product_path_run_needed"
    else:
        expected_state = "ready_to_prepare_product_path_run"
    command_template_paths = (
        payload.get("command_template_paths")
        if isinstance(payload.get("command_template_paths"), list)
        else []
    )
    if plan_state in PRODUCT_PATH_OFFICIAL_RUN_PLAN_STATES and plan_state != expected_state:
        errors.append(f"{prefix}.plan_state must be {expected_state} for product_path_readiness_state")
    expected_dry_run_counts = {
        "dry_run_contract_valid_count": sum(
            1 for action in actions if action.get("dry_run_contract_state") == "valid"
        ),
        "dry_run_contract_missing_count": sum(
            1 for action in actions if action.get("dry_run_contract_state") == "missing"
        ),
        "dry_run_contract_invalid_count": sum(
            1 for action in actions if action.get("dry_run_contract_state") == "invalid"
        ),
    }
    for field, expected_count in expected_dry_run_counts.items():
        if payload.get(field) != expected_count:
            errors.append(f"{prefix}.{field} must match actions")
    if expected_state == "no_product_path_run_needed":
        if actions:
            errors.append(f"{prefix}.no_product_path_run_needed requires empty actions")
        if commands:
            errors.append(f"{prefix}.no_product_path_run_needed requires empty commands")
        if command_template_paths:
            errors.append(f"{prefix}.no_product_path_run_needed requires empty command_template_paths")
    else:
        if not actions:
            errors.append(f"{prefix}.ready_to_prepare_product_path_run requires actions")
        if not commands:
            errors.append(f"{prefix}.ready_to_prepare_product_path_run requires runnable dry-run commands")
        if not command_template_paths:
            errors.append(f"{prefix}.ready_to_prepare_product_path_run requires command_template_paths")
        elif len(command_template_paths) < 2:
            errors.append(
                f"{prefix}.ready_to_prepare_product_path_run requires dry-run and conversion command templates"
            )
        if not manual_evidence:
            errors.append(f"{prefix}.ready_to_prepare_product_path_run requires manual_evidence_needed")


def validate_product_path_readiness_report(payload, errors, prefix):
    require_fields(
        errors,
        payload,
        [
            "readiness_state",
            "eligible_for_default_gate",
            "engine_lane_matrix_path",
            "reference_versions",
            "product_path_engine_ids",
            "candidate_engine_ids",
            "product_path_lane_count",
            "product_path_default_gate_input_count",
            "dry_run_product_path_lane_count",
            "user_impact_incomplete_lane_count",
            "health_not_ready_lane_count",
            "sidecar_required_lane_count",
            "blocking_gates",
            "reasons",
            "next_actions",
            "evidence_paths",
        ],
        prefix,
    )
    readiness_state = payload.get("readiness_state")
    if readiness_state not in PRODUCT_PATH_READINESS_STATES:
        errors.append(f"{prefix}.readiness_state is invalid: {readiness_state!r}")
    require_type(
        errors,
        payload.get("eligible_for_default_gate"),
        bool,
        f"{prefix}.eligible_for_default_gate",
    )
    require_non_empty_string(errors, payload.get("engine_lane_matrix_path"), f"{prefix}.engine_lane_matrix_path")
    for name in [
        "reference_versions",
        "product_path_engine_ids",
        "candidate_engine_ids",
        "blocking_gates",
        "reasons",
        "next_actions",
        "evidence_paths",
    ]:
        require_string_list(errors, payload.get(name), f"{prefix}.{name}")
    for name in [
        "product_path_lane_count",
        "product_path_default_gate_input_count",
        "dry_run_product_path_lane_count",
        "user_impact_incomplete_lane_count",
        "health_not_ready_lane_count",
        "sidecar_required_lane_count",
    ]:
        require_non_negative_int(errors, payload.get(name), f"{prefix}.{name}")
    for name in [
        "product_path_default_gate_input_count",
        "dry_run_product_path_lane_count",
        "user_impact_incomplete_lane_count",
        "health_not_ready_lane_count",
        "sidecar_required_lane_count",
    ]:
        if (
            isinstance(payload.get(name), int)
            and isinstance(payload.get("product_path_lane_count"), int)
            and payload[name] > payload["product_path_lane_count"]
        ):
            errors.append(f"{prefix}.{name} cannot exceed product_path_lane_count")
    enforce_product_path_readiness_invariants(payload, errors, prefix)


def enforce_product_path_readiness_invariants(payload, errors, prefix):
    readiness_state = payload.get("readiness_state")
    eligible = payload.get("eligible_for_default_gate")
    blocking_gates = payload.get("blocking_gates") or []
    default_count = int_or_zero(payload.get("product_path_default_gate_input_count"))
    lane_count = int_or_zero(payload.get("product_path_lane_count"))
    dry_run_count = int_or_zero(payload.get("dry_run_product_path_lane_count"))
    sidecar_count = int_or_zero(payload.get("sidecar_required_lane_count"))
    health_not_ready_count = int_or_zero(payload.get("health_not_ready_lane_count"))

    expected_state = "ready_for_product_path_default_gate"
    if default_count == 0:
        if lane_count == 0:
            expected_state = "blocked_no_product_path_runs"
        elif dry_run_count or sidecar_count:
            expected_state = "blocked_product_path_contract"
        elif health_not_ready_count:
            expected_state = "blocked_product_path_health"
        else:
            expected_state = "blocked_user_impact_metrics"

    if readiness_state in PRODUCT_PATH_READINESS_STATES and readiness_state != expected_state:
        errors.append(
            f"{prefix}.readiness_state must be {expected_state} for current product-path counts"
        )
    if expected_state == "ready_for_product_path_default_gate":
        if eligible is not True:
            errors.append(f"{prefix}.ready state requires eligible_for_default_gate=true")
        if blocking_gates:
            errors.append(f"{prefix}.ready state requires empty blocking_gates")
        if not payload.get("candidate_engine_ids"):
            errors.append(f"{prefix}.ready state requires candidate_engine_ids")
    else:
        if eligible is True:
            errors.append(f"{prefix}.blocked state requires eligible_for_default_gate=false")
        if not blocking_gates:
            errors.append(f"{prefix}.blocked state requires blocking_gates")


def validate_user_impact_metrics(payload, errors, prefix):
    if not isinstance(payload, dict):
        errors.append(f"{prefix} must be dict")
        return
    require_fields(errors, payload, USER_IMPACT_METRIC_FIELDS, prefix)
    for name in [
        "time_to_first_visible_text_seconds",
        "final_transcript_delay_seconds",
        "peak_memory_mb",
        "cold_start_seconds",
    ]:
        require_non_negative_number(errors, payload.get(name), f"{prefix}.{name}")
    require_ratio(errors, payload.get("unstable_partial_ratio"), f"{prefix}.unstable_partial_ratio")
    for name in [
        "preview_revision_count",
        "empty_visible_transcript_count",
        "permission_asset_failure_count",
        "sidecar_startup_failure_count",
        "user_visible_fallback_event_count",
    ]:
        require_non_negative_int(errors, payload.get(name), f"{prefix}.{name}")


def validate_reference_manifest(payload, errors, prefix):
    require_fields(
        errors,
        payload,
        [
            "reference_version",
            "split",
            "review_status",
            "source_smi_sha256",
            "reference_text_sha256",
            "reference_quality_issue_count",
        ],
        prefix,
    )
    if payload.get("split") not in REFERENCE_SPLITS:
        errors.append(f"{prefix}.split is invalid: {payload.get('split')!r}")
    if payload.get("review_status") not in REFERENCE_REVIEW_STATUSES:
        errors.append(f"{prefix}.review_status is invalid: {payload.get('review_status')!r}")
    require_non_negative_int(
        errors,
        payload.get("reference_quality_issue_count"),
        f"{prefix}.reference_quality_issue_count",
    )
    validate_reference_set_if_present(payload, errors, prefix)


def validate_reference_manifest_raw_dir_report(payload, errors, prefix):
    require_fields(
        errors,
        payload,
        [
            "prep_state",
            "reference_manifest_path",
            "reference_version",
            "output_root",
            "raw_dir",
            "sample_count",
            "included_sample_ids",
            "excluded_sample_ids",
            "reference_window_mode",
            "audio_link_modes",
            "prepared_samples",
            "next_actions",
        ],
        prefix,
    )
    if payload.get("prep_state") != "prepared_reference_manifest_raw_dir":
        errors.append(f"{prefix}.prep_state is invalid: {payload.get('prep_state')!r}")
    for name in [
        "reference_manifest_path",
        "reference_version",
        "output_root",
        "raw_dir",
        "reference_window_mode",
    ]:
        require_non_empty_string(errors, payload.get(name), f"{prefix}.{name}")
    if payload.get("reference_window_mode") != "single_full_sample_caption":
        errors.append(
            f"{prefix}.reference_window_mode is invalid: "
            f"{payload.get('reference_window_mode')!r}"
        )
    require_non_negative_int(errors, payload.get("sample_count"), f"{prefix}.sample_count")
    for name in [
        "included_sample_ids",
        "excluded_sample_ids",
        "audio_link_modes",
        "next_actions",
    ]:
        require_string_list(errors, payload.get(name), f"{prefix}.{name}")
    for mode in payload.get("audio_link_modes", []):
        if mode not in {"symlink", "copy", "copy_fallback"}:
            errors.append(f"{prefix}.audio_link_modes contains invalid mode: {mode!r}")
    require_type(errors, payload.get("prepared_samples"), list, f"{prefix}.prepared_samples")
    if isinstance(payload.get("prepared_samples"), list):
        if payload.get("sample_count") != len(payload["prepared_samples"]):
            errors.append(f"{prefix}.sample_count must equal prepared_samples length")
        sample_ids = []
        for index, sample in enumerate(payload["prepared_samples"]):
            validate_reference_manifest_raw_dir_sample(
                sample,
                errors,
                f"{prefix}.prepared_samples[{index}]",
            )
            if isinstance(sample, dict) and isinstance(sample.get("sample_id"), str):
                sample_ids.append(sample["sample_id"])
        if isinstance(payload.get("included_sample_ids"), list):
            if payload["included_sample_ids"] != sample_ids:
                errors.append(
                    f"{prefix}.included_sample_ids must match prepared_samples sample_id order"
                )


def validate_reference_manifest_raw_dir_sample(sample, errors, prefix):
    if not isinstance(sample, dict):
        errors.append(f"{prefix} must be an object")
        return
    require_fields(
        errors,
        sample,
        [
            "sample_id",
            "audio_source_path",
            "audio_raw_path",
            "audio_link_mode",
            "source_reference_text_path",
            "source_reference_text_sha256",
            "smi_raw_path",
            "smi_sha256",
            "duration_seconds",
            "reference_text_whitespace",
            "reference_window_mode",
        ],
        prefix,
    )
    for name in [
        "sample_id",
        "audio_source_path",
        "audio_raw_path",
        "audio_link_mode",
        "source_reference_text_path",
        "source_reference_text_sha256",
        "smi_raw_path",
        "smi_sha256",
        "reference_text_whitespace",
        "reference_window_mode",
    ]:
        require_non_empty_string(errors, sample.get(name), f"{prefix}.{name}")
    if sample.get("audio_link_mode") not in {"symlink", "copy", "copy_fallback"}:
        errors.append(f"{prefix}.audio_link_mode is invalid: {sample.get('audio_link_mode')!r}")
    if sample.get("reference_text_whitespace") != "collapsed":
        errors.append(
            f"{prefix}.reference_text_whitespace is invalid: "
            f"{sample.get('reference_text_whitespace')!r}"
        )
    if sample.get("reference_window_mode") != "single_full_sample_caption":
        errors.append(
            f"{prefix}.reference_window_mode is invalid: "
            f"{sample.get('reference_window_mode')!r}"
        )
    require_non_negative_number(
        errors,
        sample.get("duration_seconds"),
        f"{prefix}.duration_seconds",
    )


def validate_reference_readiness_report(payload, errors, prefix):
    require_fields(
        errors,
        payload,
        [
            "reference_version",
            "reference_manifest_path",
            "readiness_state",
            "eligible_for_default_gate",
            "blocking_gates",
            "reasons",
            "next_actions",
            "min_gold_samples",
            "min_gold_duration_minutes",
            "counts",
            "duration_minutes",
        ],
        prefix,
    )
    require_non_empty_string(errors, payload.get("reference_version"), f"{prefix}.reference_version")
    require_non_empty_string(
        errors,
        payload.get("reference_manifest_path"),
        f"{prefix}.reference_manifest_path",
    )
    readiness_state = payload.get("readiness_state")
    if readiness_state not in REFERENCE_READINESS_STATES:
        errors.append(f"{prefix}.readiness_state is invalid: {readiness_state!r}")
    require_type(errors, payload.get("eligible_for_default_gate"), bool, f"{prefix}.eligible_for_default_gate")
    require_type(errors, payload.get("blocking_gates"), list, f"{prefix}.blocking_gates")
    require_type(errors, payload.get("reasons"), list, f"{prefix}.reasons")
    require_type(errors, payload.get("next_actions"), list, f"{prefix}.next_actions")
    require_non_negative_int(errors, payload.get("min_gold_samples"), f"{prefix}.min_gold_samples")
    require_non_negative_number(
        errors,
        payload.get("min_gold_duration_minutes"),
        f"{prefix}.min_gold_duration_minutes",
    )
    validate_reference_readiness_counts(payload.get("counts"), errors, f"{prefix}.counts")
    validate_reference_readiness_durations(
        payload.get("duration_minutes"),
        errors,
        f"{prefix}.duration_minutes",
    )
    enforce_reference_readiness_invariants(payload, errors, prefix)


def validate_reference_readiness_counts(counts, errors, prefix):
    if not isinstance(counts, dict):
        errors.append(f"{prefix} must be dict")
        return
    fields = [
        "sample_count",
        "gold_count",
        "dev_count",
        "stress_count",
        "reviewed_count",
        "unreviewed_count",
        "excluded_count",
        "reference_quality_issue_count",
    ]
    require_fields(errors, counts, fields, prefix)
    for field in fields:
        require_non_negative_int(errors, counts.get(field), f"{prefix}.{field}")


def validate_reference_readiness_durations(durations, errors, prefix):
    if not isinstance(durations, dict):
        errors.append(f"{prefix} must be dict")
        return
    fields = [
        "total",
        "gold",
        "dev",
        "stress",
        "reviewed",
        "unreviewed",
        "excluded",
    ]
    require_fields(errors, durations, fields, prefix)
    for field in fields:
        require_non_negative_number(errors, durations.get(field), f"{prefix}.{field}")


def enforce_reference_readiness_invariants(payload, errors, prefix):
    readiness_state = payload.get("readiness_state")
    eligible = payload.get("eligible_for_default_gate")
    blocking_gates = payload.get("blocking_gates") or []
    counts = payload.get("counts") or {}
    durations = payload.get("duration_minutes") or {}
    min_gold_samples = int_or_zero(payload.get("min_gold_samples"))
    min_gold_duration_minutes = number_or_zero(payload.get("min_gold_duration_minutes"))

    if readiness_state == "ready_for_default_gate":
        if eligible is not True:
            errors.append(f"{prefix}.ready_for_default_gate requires eligible_for_default_gate=true")
        if blocking_gates:
            errors.append(f"{prefix}.ready_for_default_gate requires empty blocking_gates")
        if int_or_zero(counts.get("unreviewed_count")):
            errors.append(f"{prefix}.ready_for_default_gate cannot have unreviewed references")
        if int_or_zero(counts.get("reference_quality_issue_count")):
            errors.append(f"{prefix}.ready_for_default_gate cannot have reference quality issues")
        if int_or_zero(counts.get("gold_count")) < min_gold_samples:
            errors.append(f"{prefix}.ready_for_default_gate requires min_gold_samples")
        if number_or_zero(durations.get("gold")) < min_gold_duration_minutes:
            errors.append(f"{prefix}.ready_for_default_gate requires min_gold_duration_minutes")
    else:
        if eligible is True:
            errors.append(f"{prefix}.non-ready state requires eligible_for_default_gate=false")
        if not blocking_gates:
            errors.append(f"{prefix}.non-ready state requires blocking_gates")


def validate_reference_review_preflight_report(payload, errors, prefix):
    require_fields(
        errors,
        payload,
        [
            "reference_version",
            "reference_manifest_path",
            "review_decisions_path",
            "preflight_state",
            "ready_to_apply",
            "blocking_gates",
            "errors",
            "warnings",
            "counts",
        ],
        prefix,
    )
    require_non_empty_string(errors, payload.get("reference_version"), f"{prefix}.reference_version")
    require_non_empty_string(
        errors,
        payload.get("reference_manifest_path"),
        f"{prefix}.reference_manifest_path",
    )
    require_non_empty_string(
        errors,
        payload.get("review_decisions_path"),
        f"{prefix}.review_decisions_path",
    )
    preflight_state = payload.get("preflight_state")
    if preflight_state not in REFERENCE_REVIEW_PREFLIGHT_STATES:
        errors.append(f"{prefix}.preflight_state is invalid: {preflight_state!r}")
    require_type(errors, payload.get("ready_to_apply"), bool, f"{prefix}.ready_to_apply")
    require_type(errors, payload.get("blocking_gates"), list, f"{prefix}.blocking_gates")
    require_type(errors, payload.get("errors"), list, f"{prefix}.errors")
    require_type(errors, payload.get("warnings"), list, f"{prefix}.warnings")
    validate_reference_review_preflight_counts(payload.get("counts"), errors, f"{prefix}.counts")
    enforce_reference_review_preflight_invariants(payload, errors, prefix)


def validate_reference_review_preflight_counts(counts, errors, prefix):
    if not isinstance(counts, dict):
        errors.append(f"{prefix} must be dict")
        return
    fields = [
        "decision_count",
        "unknown_sample_count",
        "duplicate_sample_count",
        "incomplete_decision_count",
        "invalid_decision_count",
        "reviewed_decision_count",
        "excluded_decision_count",
        "reference_quality_issue_count",
        "corrected_reference_count",
    ]
    require_fields(errors, counts, fields, prefix)
    for field in fields:
        require_non_negative_int(errors, counts.get(field), f"{prefix}.{field}")


def enforce_reference_review_preflight_invariants(payload, errors, prefix):
    preflight_state = payload.get("preflight_state")
    ready_to_apply = payload.get("ready_to_apply")
    blocking_gates = payload.get("blocking_gates") or []
    report_errors = payload.get("errors") or []

    if preflight_state == "ready_to_apply":
        if ready_to_apply is not True:
            errors.append(f"{prefix}.ready_to_apply state requires ready_to_apply=true")
        if blocking_gates:
            errors.append(f"{prefix}.ready_to_apply state requires empty blocking_gates")
        if report_errors:
            errors.append(f"{prefix}.ready_to_apply state requires empty errors")
    else:
        if ready_to_apply is True:
            errors.append(f"{prefix}.non-ready state requires ready_to_apply=false")
        if not blocking_gates:
            errors.append(f"{prefix}.non-ready state requires blocking_gates")
        if not report_errors:
            errors.append(f"{prefix}.non-ready state requires errors")


def validate_reference_review_submission_readiness_report(payload, errors, prefix):
    require_fields(
        errors,
        payload,
        [
            "review_pack_manifest_path",
            "source_reference_manifest_path",
            "review_decisions_path",
            "source_reference_version",
            "submission_readiness_state",
            "ready_for_reference_workflow",
            "preflight_state",
            "ready_to_apply",
            "preflight_report_path",
            "readiness_state",
            "eligible_for_default_gate",
            "min_gold_samples",
            "min_gold_duration_minutes",
            "review_decision_item_count",
            "blocked_review_decision_item_count",
            "blocked_review_decision_sample_ids",
            "blocked_review_decision_missing_fields",
            "blocked_review_decision_items",
            "review_decision_fill_task_count",
            "review_decision_fill_tasks",
            "review_decision_fill_tasks_csv_path",
            "next_blocked_review_decision_row_number",
            "next_blocked_review_decision_sample_id",
            "next_blocked_review_decision_recommended_action",
            "review_decision_items",
            "gold_requirement_state",
            "gold_requirement",
            "gold_candidate_items",
            "preflight_counts",
            "readiness_counts",
            "readiness_duration_minutes",
            "blocking_gates",
            "errors",
            "reasons",
            "next_actions",
            "workflow_command_template",
            "workflow_command_template_path",
            "command_template_paths",
            "expected_workflow_report_path",
            "submission_handoff_steps",
            "simulated_reference_manifest_path",
            "readiness_report_path",
            "evidence_paths",
            "markdown_report_path",
            "html_report_path",
        ],
        prefix,
    )
    for name in [
        "review_pack_manifest_path",
        "source_reference_manifest_path",
        "review_decisions_path",
        "source_reference_version",
        "preflight_report_path",
        "review_decision_fill_tasks_csv_path",
        "workflow_command_template",
        "workflow_command_template_path",
        "expected_workflow_report_path",
        "markdown_report_path",
        "html_report_path",
    ]:
        require_non_empty_string(errors, payload.get(name), f"{prefix}.{name}")
    submission_state = payload.get("submission_readiness_state")
    if submission_state not in REFERENCE_REVIEW_SUBMISSION_READINESS_STATES:
        errors.append(f"{prefix}.submission_readiness_state is invalid: {submission_state!r}")
    preflight_state = payload.get("preflight_state")
    if preflight_state not in REFERENCE_REVIEW_PREFLIGHT_STATES:
        errors.append(f"{prefix}.preflight_state is invalid: {preflight_state!r}")
    readiness_state = payload.get("readiness_state")
    if readiness_state and readiness_state not in REFERENCE_READINESS_STATES:
        errors.append(f"{prefix}.readiness_state is invalid: {readiness_state!r}")
    require_type(
        errors,
        payload.get("ready_for_reference_workflow"),
        bool,
        f"{prefix}.ready_for_reference_workflow",
    )
    require_type(errors, payload.get("ready_to_apply"), bool, f"{prefix}.ready_to_apply")
    require_type(
        errors,
        payload.get("eligible_for_default_gate"),
        bool,
        f"{prefix}.eligible_for_default_gate",
    )
    require_type(
        errors,
        payload.get("submission_handoff_steps"),
        list,
        f"{prefix}.submission_handoff_steps",
    )
    if isinstance(payload.get("submission_handoff_steps"), list):
        for index, item in enumerate(payload["submission_handoff_steps"]):
            validate_reference_review_handoff_step(
                item,
                errors,
                f"{prefix}.submission_handoff_steps[{index}]",
            )
    require_non_negative_int(errors, payload.get("min_gold_samples"), f"{prefix}.min_gold_samples")
    require_non_negative_number(
        errors,
        payload.get("min_gold_duration_minutes"),
        f"{prefix}.min_gold_duration_minutes",
    )
    require_non_negative_int(
        errors,
        payload.get("review_decision_item_count"),
        f"{prefix}.review_decision_item_count",
    )
    require_non_negative_int(
        errors,
        payload.get("blocked_review_decision_item_count"),
        f"{prefix}.blocked_review_decision_item_count",
    )
    require_string_list(
        errors,
        payload.get("blocked_review_decision_sample_ids"),
        f"{prefix}.blocked_review_decision_sample_ids",
    )
    require_string_list(
        errors,
        payload.get("blocked_review_decision_missing_fields"),
        f"{prefix}.blocked_review_decision_missing_fields",
    )
    require_type(
        errors,
        payload.get("blocked_review_decision_items"),
        list,
        f"{prefix}.blocked_review_decision_items",
    )
    if isinstance(payload.get("blocked_review_decision_items"), list):
        for index, item in enumerate(payload["blocked_review_decision_items"]):
            validate_reference_review_submission_blocked_decision_item(
                item,
                errors,
                f"{prefix}.blocked_review_decision_items[{index}]",
            )
    require_non_negative_int(
        errors,
        payload.get("review_decision_fill_task_count"),
        f"{prefix}.review_decision_fill_task_count",
    )
    require_type(
        errors,
        payload.get("review_decision_fill_tasks"),
        list,
        f"{prefix}.review_decision_fill_tasks",
    )
    if isinstance(payload.get("review_decision_fill_tasks"), list):
        for index, item in enumerate(payload["review_decision_fill_tasks"]):
            validate_reference_review_submission_fill_task(
                item,
                errors,
                f"{prefix}.review_decision_fill_tasks[{index}]",
            )
    require_non_negative_int(
        errors,
        payload.get("next_blocked_review_decision_row_number"),
        f"{prefix}.next_blocked_review_decision_row_number",
    )
    for name in [
        "next_blocked_review_decision_sample_id",
        "next_blocked_review_decision_recommended_action",
    ]:
        require_type(errors, payload.get(name), str, f"{prefix}.{name}")
    require_type(errors, payload.get("review_decision_items"), list, f"{prefix}.review_decision_items")
    if isinstance(payload.get("review_decision_items"), list):
        for index, item in enumerate(payload["review_decision_items"]):
            validate_reference_review_submission_decision_item(
                item,
                errors,
                f"{prefix}.review_decision_items[{index}]",
            )
    if payload.get("gold_requirement_state") not in REFERENCE_REVIEW_GOLD_REQUIREMENT_STATES:
        errors.append(
            f"{prefix}.gold_requirement_state is invalid: "
            f"{payload.get('gold_requirement_state')!r}"
        )
    validate_reference_review_gold_requirement(
        payload.get("gold_requirement"),
        errors,
        f"{prefix}.gold_requirement",
    )
    require_type(errors, payload.get("gold_candidate_items"), list, f"{prefix}.gold_candidate_items")
    if isinstance(payload.get("gold_candidate_items"), list):
        for index, item in enumerate(payload["gold_candidate_items"]):
            validate_reference_review_gold_candidate_item(
                item,
                errors,
                f"{prefix}.gold_candidate_items[{index}]",
            )
    validate_reference_review_preflight_counts(
        payload.get("preflight_counts"),
        errors,
        f"{prefix}.preflight_counts",
    )
    if payload.get("readiness_counts"):
        validate_reference_readiness_counts(
            payload.get("readiness_counts"),
            errors,
            f"{prefix}.readiness_counts",
        )
    else:
        require_type(errors, payload.get("readiness_counts"), dict, f"{prefix}.readiness_counts")
    if payload.get("readiness_duration_minutes"):
        validate_reference_readiness_durations(
            payload.get("readiness_duration_minutes"),
            errors,
            f"{prefix}.readiness_duration_minutes",
        )
    else:
        require_type(
            errors,
            payload.get("readiness_duration_minutes"),
            dict,
            f"{prefix}.readiness_duration_minutes",
        )
    for name in [
        "blocking_gates",
        "errors",
        "reasons",
        "next_actions",
        "command_template_paths",
        "evidence_paths",
    ]:
        require_string_list(errors, payload.get(name), f"{prefix}.{name}")
    for name in ["simulated_reference_manifest_path", "readiness_report_path"]:
        require_type(errors, payload.get(name), str, f"{prefix}.{name}")
    enforce_reference_review_submission_readiness_invariants(payload, errors, prefix)


def validate_reference_review_gold_requirement(payload, errors, prefix):
    if not isinstance(payload, dict):
        errors.append(f"{prefix} must be dict")
        return
    fields = [
        "min_gold_samples",
        "min_gold_duration_minutes",
        "planned_gold_sample_count",
        "planned_gold_duration_minutes",
        "ready_gold_sample_count",
        "ready_gold_duration_minutes",
        "remaining_gold_sample_count",
        "remaining_gold_duration_minutes",
    ]
    require_fields(errors, payload, fields, prefix)
    for field in [
        "min_gold_samples",
        "planned_gold_sample_count",
        "ready_gold_sample_count",
        "remaining_gold_sample_count",
    ]:
        require_non_negative_int(errors, payload.get(field), f"{prefix}.{field}")
    for field in [
        "min_gold_duration_minutes",
        "planned_gold_duration_minutes",
        "ready_gold_duration_minutes",
        "remaining_gold_duration_minutes",
    ]:
        require_non_negative_number(errors, payload.get(field), f"{prefix}.{field}")


def validate_reference_review_gold_candidate_item(item, errors, prefix):
    if not isinstance(item, dict):
        errors.append(f"{prefix} must be an object")
        return
    require_fields(
        errors,
        item,
        [
            "sample_id",
            "duration_minutes",
            "current_target_split",
            "review_status",
            "meets_duration_threshold_alone",
            "recommended_action",
        ],
        prefix,
    )
    require_non_empty_string(errors, item.get("sample_id"), f"{prefix}.sample_id")
    require_non_negative_number(errors, item.get("duration_minutes"), f"{prefix}.duration_minutes")
    for name in ["current_target_split", "review_status", "recommended_action"]:
        require_type(errors, item.get(name), str, f"{prefix}.{name}")
    require_type(
        errors,
        item.get("meets_duration_threshold_alone"),
        bool,
        f"{prefix}.meets_duration_threshold_alone",
    )


def validate_reference_review_submission_decision_item(item, errors, prefix):
    if not isinstance(item, dict):
        errors.append(f"{prefix} must be an object")
        return
    require_fields(
        errors,
        item,
        [
            "row_number",
            "sample_id",
            "duration_minutes",
            "current_split",
            "target_split",
            "review_status",
            "item_state",
            "missing_fields",
            "recommended_action",
            "audio_path",
            "current_reference_text_path",
            "corrected_reference_text_path",
        ],
        prefix,
    )
    require_non_negative_int(errors, item.get("row_number"), f"{prefix}.row_number")
    require_type(errors, item.get("sample_id"), str, f"{prefix}.sample_id")
    require_non_negative_number(errors, item.get("duration_minutes"), f"{prefix}.duration_minutes")
    for name in [
        "current_split",
        "target_split",
        "review_status",
        "item_state",
        "recommended_action",
        "audio_path",
        "current_reference_text_path",
        "corrected_reference_text_path",
    ]:
        require_type(errors, item.get(name), str, f"{prefix}.{name}")
    if item.get("item_state") not in {"preflight_blocking", "readiness_blocking", "ready"}:
        errors.append(f"{prefix}.item_state is invalid: {item.get('item_state')!r}")
    require_string_list(errors, item.get("missing_fields"), f"{prefix}.missing_fields")


def reference_review_submission_blocked_decision_item_summary(item):
    return {
        "row_number": int_or_zero(item.get("row_number")),
        "sample_id": item.get("sample_id", ""),
        "item_state": item.get("item_state", ""),
        "duration_minutes": item.get("duration_minutes", 0),
        "target_split": item.get("target_split", ""),
        "review_status": item.get("review_status", ""),
        "missing_fields": unique_non_empty_strings(item.get("missing_fields", [])),
        "recommended_action": item.get("recommended_action", ""),
    }


def reference_review_submission_fill_task_summary(item):
    return {
        "row_number": int_or_zero(item.get("row_number")),
        "sample_id": item.get("sample_id", ""),
        "item_state": item.get("item_state", ""),
        "duration_minutes": item.get("duration_minutes", 0),
        "target_split": item.get("target_split", ""),
        "review_status": item.get("review_status", ""),
        "missing_fields": unique_non_empty_strings(item.get("missing_fields", [])),
        "recommended_action": item.get("recommended_action", ""),
        "audio_path": item.get("audio_path", ""),
        "current_reference_text_path": item.get("current_reference_text_path", ""),
        "corrected_reference_text_path": item.get("corrected_reference_text_path", ""),
    }


def validate_reference_review_submission_fill_task(item, errors, prefix):
    if not isinstance(item, dict):
        errors.append(f"{prefix} must be an object")
        return
    require_fields(
        errors,
        item,
        [
            "row_number",
            "sample_id",
            "item_state",
            "duration_minutes",
            "target_split",
            "review_status",
            "missing_fields",
            "recommended_action",
            "audio_path",
            "current_reference_text_path",
            "corrected_reference_text_path",
        ],
        prefix,
    )
    require_non_negative_int(errors, item.get("row_number"), f"{prefix}.row_number")
    require_non_negative_number(
        errors,
        item.get("duration_minutes"),
        f"{prefix}.duration_minutes",
    )
    for name in [
        "sample_id",
        "item_state",
        "target_split",
        "review_status",
        "recommended_action",
        "audio_path",
        "current_reference_text_path",
        "corrected_reference_text_path",
    ]:
        require_type(errors, item.get(name), str, f"{prefix}.{name}")
    if item.get("item_state") not in {"preflight_blocking", "readiness_blocking"}:
        errors.append(f"{prefix}.item_state must be a non-ready state")
    require_string_list(errors, item.get("missing_fields"), f"{prefix}.missing_fields")


def validate_reference_review_submission_blocked_decision_item(item, errors, prefix):
    if not isinstance(item, dict):
        errors.append(f"{prefix} must be an object")
        return
    require_fields(
        errors,
        item,
        [
            "row_number",
            "sample_id",
            "item_state",
            "duration_minutes",
            "target_split",
            "review_status",
            "missing_fields",
            "recommended_action",
        ],
        prefix,
    )
    require_non_negative_int(errors, item.get("row_number"), f"{prefix}.row_number")
    require_non_negative_number(
        errors,
        item.get("duration_minutes"),
        f"{prefix}.duration_minutes",
    )
    for name in [
        "sample_id",
        "item_state",
        "target_split",
        "review_status",
        "recommended_action",
    ]:
        require_type(errors, item.get(name), str, f"{prefix}.{name}")
    if item.get("item_state") not in {"preflight_blocking", "readiness_blocking"}:
        errors.append(f"{prefix}.item_state must be a non-ready state")
    require_string_list(errors, item.get("missing_fields"), f"{prefix}.missing_fields")


def validate_reference_review_decision_scaffold_report(payload, errors, prefix):
    require_fields(
        errors,
        payload,
        [
            "scaffold_state",
            "review_pack_manifest_path",
            "template_csv_path",
            "scaffold_csv_path",
            "worklist_csv_path",
            "review_decisions_output_path_hint",
            "submission_readiness_command_template",
            "expected_submission_readiness_report_path",
            "workflow_command_template",
            "expected_workflow_report_path",
            "handoff_steps",
            "selected_gold_sample_ids",
            "selected_gold_duration_minutes",
            "selected_stress_sample_ids",
            "selected_stress_duration_minutes",
            "selected_dev_sample_ids",
            "target_split_counts",
            "worklist_items",
            "min_dev_samples",
            "min_gold_samples",
            "min_gold_duration_minutes",
            "min_stress_samples",
            "row_count",
            "next_actions",
            "markdown_report_path",
            "html_report_path",
        ],
        prefix,
    )
    scaffold_state = payload.get("scaffold_state")
    if scaffold_state not in REFERENCE_REVIEW_DECISION_SCAFFOLD_STATES:
        errors.append(f"{prefix}.scaffold_state is invalid: {scaffold_state!r}")
    for name in [
        "review_pack_manifest_path",
        "template_csv_path",
        "scaffold_csv_path",
        "worklist_csv_path",
        "review_decisions_output_path_hint",
        "submission_readiness_command_template",
        "expected_submission_readiness_report_path",
        "workflow_command_template",
        "expected_workflow_report_path",
        "markdown_report_path",
        "html_report_path",
    ]:
        require_non_empty_string(errors, payload.get(name), f"{prefix}.{name}")
    require_type(
        errors,
        payload.get("selected_gold_sample_ids"),
        list,
        f"{prefix}.selected_gold_sample_ids",
    )
    if isinstance(payload.get("selected_gold_sample_ids"), list):
        for index, sample_id in enumerate(payload["selected_gold_sample_ids"]):
            require_non_empty_string(
                errors,
                sample_id,
                f"{prefix}.selected_gold_sample_ids[{index}]",
            )
    for name in ["selected_stress_sample_ids", "selected_dev_sample_ids"]:
        require_type(errors, payload.get(name), list, f"{prefix}.{name}")
        if isinstance(payload.get(name), list):
            for index, sample_id in enumerate(payload[name]):
                require_non_empty_string(errors, sample_id, f"{prefix}.{name}[{index}]")
    require_non_negative_number(
        errors,
        payload.get("selected_gold_duration_minutes"),
        f"{prefix}.selected_gold_duration_minutes",
    )
    require_non_negative_number(
        errors,
        payload.get("selected_stress_duration_minutes"),
        f"{prefix}.selected_stress_duration_minutes",
    )
    validate_reference_review_decision_scaffold_counts(
        payload.get("target_split_counts"),
        errors,
        f"{prefix}.target_split_counts",
    )
    require_type(errors, payload.get("worklist_items"), list, f"{prefix}.worklist_items")
    if isinstance(payload.get("worklist_items"), list):
        for index, item in enumerate(payload["worklist_items"]):
            validate_reference_review_decision_scaffold_worklist_item(
                item,
                errors,
                f"{prefix}.worklist_items[{index}]",
            )
    require_type(errors, payload.get("handoff_steps"), list, f"{prefix}.handoff_steps")
    if isinstance(payload.get("handoff_steps"), list):
        for index, item in enumerate(payload["handoff_steps"]):
            validate_reference_review_handoff_step(
                item,
                errors,
                f"{prefix}.handoff_steps[{index}]",
            )
    require_non_negative_int(errors, payload.get("min_dev_samples"), f"{prefix}.min_dev_samples")
    require_non_negative_int(errors, payload.get("min_gold_samples"), f"{prefix}.min_gold_samples")
    require_non_negative_number(
        errors,
        payload.get("min_gold_duration_minutes"),
        f"{prefix}.min_gold_duration_minutes",
    )
    require_non_negative_int(
        errors,
        payload.get("min_stress_samples"),
        f"{prefix}.min_stress_samples",
    )
    require_non_negative_int(errors, payload.get("row_count"), f"{prefix}.row_count")
    require_string_list(errors, payload.get("next_actions"), f"{prefix}.next_actions")
    enforce_reference_review_decision_scaffold_invariants(payload, errors, prefix)


def validate_reference_review_handoff_step(item, errors, prefix):
    if not isinstance(item, dict):
        errors.append(f"{prefix} must be an object")
        return
    require_fields(
        errors,
        item,
        [
            "step_id",
            "step_order",
            "title",
            "operator_action",
            "input_paths",
            "output_paths",
            "command_template",
            "completion_criteria",
        ],
        prefix,
    )
    for name in ["step_id", "title", "operator_action", "command_template"]:
        require_type(errors, item.get(name), str, f"{prefix}.{name}")
    require_non_negative_int(errors, item.get("step_order"), f"{prefix}.step_order")
    if isinstance(item.get("step_order"), int) and item.get("step_order") <= 0:
        errors.append(f"{prefix}.step_order must be greater than zero")
    for name in ["input_paths", "output_paths", "completion_criteria"]:
        require_string_list(errors, item.get(name), f"{prefix}.{name}")
    if not item.get("output_paths"):
        errors.append(f"{prefix}.output_paths must not be empty")
    if not item.get("completion_criteria"):
        errors.append(f"{prefix}.completion_criteria must not be empty")


def validate_reference_review_decision_scaffold_counts(payload, errors, prefix):
    if not isinstance(payload, dict):
        errors.append(f"{prefix} must be dict")
        return
    for split in ["gold", "dev", "stress"]:
        require_non_negative_int(errors, payload.get(split), f"{prefix}.{split}")


def validate_reference_review_decision_scaffold_worklist_item(item, errors, prefix):
    if not isinstance(item, dict):
        errors.append(f"{prefix} must be an object")
        return
    require_fields(
        errors,
        item,
        [
            "sample_id",
            "target_split",
            "review_priority",
            "duration_minutes",
            "expected_accept_status",
            "accepted_required_fields",
            "reject_instruction",
            "audio_path",
            "source_smi_path",
            "current_reference_text_path",
            "corrected_reference_text_path",
            "note",
        ],
        prefix,
    )
    require_non_empty_string(errors, item.get("sample_id"), f"{prefix}.sample_id")
    if item.get("target_split") not in REFERENCE_SPLITS:
        errors.append(f"{prefix}.target_split is invalid: {item.get('target_split')!r}")
    if item.get("review_priority") not in REFERENCE_SPLITS:
        errors.append(f"{prefix}.review_priority is invalid: {item.get('review_priority')!r}")
    require_non_negative_number(errors, item.get("duration_minutes"), f"{prefix}.duration_minutes")
    for name in [
        "expected_accept_status",
        "accepted_required_fields",
        "reject_instruction",
        "audio_path",
        "source_smi_path",
        "current_reference_text_path",
        "corrected_reference_text_path",
        "note",
    ]:
        require_type(errors, item.get(name), str, f"{prefix}.{name}")


def enforce_reference_review_decision_scaffold_invariants(payload, errors, prefix):
    scaffold_state = payload.get("scaffold_state")
    selected_gold_sample_ids = payload.get("selected_gold_sample_ids") or []
    selected_stress_sample_ids = payload.get("selected_stress_sample_ids") or []
    selected_dev_sample_ids = payload.get("selected_dev_sample_ids") or []
    selected_gold_sample_count = (
        len(selected_gold_sample_ids) if isinstance(selected_gold_sample_ids, list) else 0
    )
    selected_stress_sample_count = (
        len(selected_stress_sample_ids) if isinstance(selected_stress_sample_ids, list) else 0
    )
    selected_dev_sample_count = (
        len(selected_dev_sample_ids) if isinstance(selected_dev_sample_ids, list) else 0
    )
    selected_gold_duration = number_or_zero(payload.get("selected_gold_duration_minutes"))
    min_gold_samples = int_or_zero(payload.get("min_gold_samples"))
    min_gold_duration = number_or_zero(payload.get("min_gold_duration_minutes"))
    counts = payload.get("target_split_counts") or {}
    gold_minimums_met = (
        selected_gold_sample_count >= min_gold_samples
        and selected_gold_duration >= min_gold_duration
    )
    target_split_minimums_met = (
        int_or_zero(counts.get("stress")) >= int_or_zero(payload.get("min_stress_samples"))
        and int_or_zero(counts.get("dev")) >= int_or_zero(payload.get("min_dev_samples"))
    )
    if payload.get("template_csv_path") == payload.get("scaffold_csv_path"):
        errors.append(f"{prefix}.scaffold_csv_path must not overwrite template_csv_path")
    if not payload.get("next_actions"):
        errors.append(f"{prefix}.next_actions must not be empty")
    if isinstance(payload.get("row_count"), int) and isinstance(counts, dict):
        count_sum = sum(int_or_zero(counts.get(split)) for split in ["gold", "dev", "stress"])
        if payload.get("row_count") != count_sum:
            errors.append(f"{prefix}.row_count must equal target_split_counts sum")
        if int_or_zero(counts.get("gold")) != selected_gold_sample_count:
            errors.append(f"{prefix}.target_split_counts.gold must equal selected_gold_sample_ids length")
        if int_or_zero(counts.get("stress")) != selected_stress_sample_count:
            errors.append(
                f"{prefix}.target_split_counts.stress must equal selected_stress_sample_ids length"
            )
        if int_or_zero(counts.get("dev")) != selected_dev_sample_count:
            errors.append(f"{prefix}.target_split_counts.dev must equal selected_dev_sample_ids length")
        if isinstance(payload.get("worklist_items"), list) and payload.get("row_count") != len(
            payload.get("worklist_items")
        ):
            errors.append(f"{prefix}.row_count must equal worklist_items length")
    if all(
        isinstance(value, list)
        for value in [selected_gold_sample_ids, selected_stress_sample_ids, selected_dev_sample_ids]
    ):
        combined_ids = selected_gold_sample_ids + selected_stress_sample_ids + selected_dev_sample_ids
        if len(set(combined_ids)) != len(combined_ids):
            errors.append(f"{prefix}.selected split sample ids must not overlap")
    if scaffold_state == "prepared" and not (gold_minimums_met and target_split_minimums_met):
        errors.append(f"{prefix}.prepared state requires gold/dev/stress minimums")
    if scaffold_state == "blocked_insufficient_gold_candidates" and gold_minimums_met:
        errors.append(
            f"{prefix}.blocked_insufficient_gold_candidates state cannot meet selected gold minimums"
        )
    if (
        scaffold_state == "blocked_insufficient_target_split_candidates"
        and gold_minimums_met
        and target_split_minimums_met
    ):
        errors.append(
            f"{prefix}.blocked_insufficient_target_split_candidates state cannot meet "
            "target split minimums"
        )


def enforce_reference_review_submission_readiness_invariants(payload, errors, prefix):
    submission_state = payload.get("submission_readiness_state")
    ready = payload.get("ready_for_reference_workflow")
    ready_to_apply = payload.get("ready_to_apply")
    eligible = payload.get("eligible_for_default_gate")
    blocking_gates = payload.get("blocking_gates") or []
    report_errors = payload.get("errors") or []
    reasons = payload.get("reasons") or []
    items = payload.get("review_decision_items") or []
    blocked_items = [
        item
        for item in items
        if isinstance(item, dict) and item.get("item_state") != "ready"
    ]
    if payload.get("review_decision_item_count") != len(items):
        errors.append(f"{prefix}.review_decision_item_count must equal review_decision_items length")
    if payload.get("blocked_review_decision_item_count") != len(blocked_items):
        errors.append(
            f"{prefix}.blocked_review_decision_item_count must equal non-ready item count"
        )
    blocked_sample_ids = unique_non_empty_strings(
        item.get("sample_id", "")
        for item in blocked_items
        if isinstance(item, dict)
    )
    if payload.get("blocked_review_decision_sample_ids") != blocked_sample_ids:
        errors.append(
            f"{prefix}.blocked_review_decision_sample_ids must equal non-ready sample ids"
        )
    blocked_missing_fields = []
    for item in blocked_items:
        if isinstance(item, dict):
            blocked_missing_fields.extend(item.get("missing_fields", []))
    blocked_missing_fields = unique_non_empty_strings(blocked_missing_fields)
    if payload.get("blocked_review_decision_missing_fields") != blocked_missing_fields:
        errors.append(
            f"{prefix}.blocked_review_decision_missing_fields must equal non-ready missing fields"
        )
    blocked_item_summaries = [
        reference_review_submission_blocked_decision_item_summary(item)
        for item in blocked_items
        if isinstance(item, dict)
    ]
    if payload.get("blocked_review_decision_items") != blocked_item_summaries:
        errors.append(
            f"{prefix}.blocked_review_decision_items must equal non-ready item summaries"
        )
    fill_task_summaries = [
        reference_review_submission_fill_task_summary(item)
        for item in blocked_items
        if isinstance(item, dict)
    ]
    if payload.get("review_decision_fill_task_count") != len(fill_task_summaries):
        errors.append(
            f"{prefix}.review_decision_fill_task_count must equal non-ready item count"
        )
    if payload.get("review_decision_fill_tasks") != fill_task_summaries:
        errors.append(
            f"{prefix}.review_decision_fill_tasks must equal non-ready fill task summaries"
        )
    next_blocked_item = blocked_items[0] if blocked_items else {}
    actual_next_blocked_row = int_or_zero(
        next_blocked_item.get("row_number") if isinstance(next_blocked_item, dict) else 0
    )
    if (
        int_or_zero(payload.get("next_blocked_review_decision_row_number"))
        != actual_next_blocked_row
    ):
        errors.append(
            f"{prefix}.next_blocked_review_decision_row_number must match first non-ready item"
        )
    actual_next_blocked_sample = (
        next_blocked_item.get("sample_id", "")
        if isinstance(next_blocked_item, dict)
        else ""
    )
    if payload.get("next_blocked_review_decision_sample_id") != actual_next_blocked_sample:
        errors.append(
            f"{prefix}.next_blocked_review_decision_sample_id must match first non-ready item"
        )
    actual_next_blocked_action = (
        next_blocked_item.get("recommended_action", "")
        if isinstance(next_blocked_item, dict)
        else ""
    )
    if (
        payload.get("next_blocked_review_decision_recommended_action")
        != actual_next_blocked_action
    ):
        errors.append(
            f"{prefix}.next_blocked_review_decision_recommended_action must match first non-ready item"
        )
    command_template_path = payload.get("workflow_command_template_path", "")
    command_template_paths = payload.get("command_template_paths") or []
    evidence_paths = payload.get("evidence_paths") or []
    if command_template_path and isinstance(command_template_paths, list):
        if command_template_path not in command_template_paths:
            errors.append(
                f"{prefix}.command_template_paths must include workflow_command_template_path"
            )
    if command_template_path and isinstance(evidence_paths, list):
        if command_template_path not in evidence_paths:
            errors.append(f"{prefix}.evidence_paths must include workflow_command_template_path")
    fill_tasks_csv_path = payload.get("review_decision_fill_tasks_csv_path", "")
    if fill_tasks_csv_path and isinstance(evidence_paths, list):
        if fill_tasks_csv_path not in evidence_paths:
            errors.append(
                f"{prefix}.evidence_paths must include review_decision_fill_tasks_csv_path"
            )
    handoff_steps = payload.get("submission_handoff_steps") or []
    if isinstance(handoff_steps, list):
        step_ids = [
            item.get("step_id")
            for item in handoff_steps
            if isinstance(item, dict)
        ]
        if step_ids != [
            "run_reference_review_workflow",
            "return_reference_review_workflow_report",
        ]:
            errors.append(
                f"{prefix}.submission_handoff_steps step_id sequence is invalid"
            )
        if len(handoff_steps) >= 1 and isinstance(handoff_steps[0], dict):
            workflow_step = handoff_steps[0]
            if workflow_step.get("output_paths") != [
                payload.get("expected_workflow_report_path")
            ]:
                errors.append(
                    f"{prefix}.submission_handoff_steps[0].output_paths must equal "
                    "expected_workflow_report_path"
                )
            if submission_state == "ready_for_workflow":
                if workflow_step.get("command_template") != payload.get(
                    "workflow_command_template"
                ):
                    errors.append(
                        f"{prefix}.submission_handoff_steps[0].command_template "
                        "must equal workflow_command_template when ready"
                    )
            elif workflow_step.get("command_template"):
                errors.append(
                    f"{prefix}.submission_handoff_steps[0].command_template "
                    "must be empty until ready_for_workflow"
                )
            if (
                command_template_path
                and isinstance(workflow_step.get("input_paths"), list)
                and command_template_path not in workflow_step.get("input_paths", [])
            ):
                errors.append(
                    f"{prefix}.submission_handoff_steps[0].input_paths must include "
                    "workflow_command_template_path"
                )
        if len(handoff_steps) >= 2 and isinstance(handoff_steps[1], dict):
            return_step = handoff_steps[1]
            if return_step.get("input_paths") != [
                payload.get("expected_workflow_report_path")
            ]:
                errors.append(
                    f"{prefix}.submission_handoff_steps[1].input_paths must equal "
                    "expected_workflow_report_path"
                )
            if return_step.get("output_paths") != [
                "reference_review_workflow_report_path"
            ]:
                errors.append(
                    f"{prefix}.submission_handoff_steps[1].output_paths must equal "
                    "reference_review_workflow_report_path"
                )
    if payload.get("gold_requirement_state") == "satisfied":
        gold = payload.get("gold_requirement") or {}
        if int_or_zero(gold.get("ready_gold_sample_count")) < int_or_zero(gold.get("min_gold_samples")):
            errors.append(f"{prefix}.satisfied gold requires min_gold_samples")
        if number_or_zero(gold.get("ready_gold_duration_minutes")) < number_or_zero(
            gold.get("min_gold_duration_minutes")
        ):
            errors.append(f"{prefix}.satisfied gold requires min_gold_duration_minutes")

    if submission_state == "ready_for_workflow":
        if ready is not True:
            errors.append(f"{prefix}.ready_for_workflow requires ready_for_reference_workflow=true")
        if ready_to_apply is not True:
            errors.append(f"{prefix}.ready_for_workflow requires ready_to_apply=true")
        if eligible is not True:
            errors.append(f"{prefix}.ready_for_workflow requires eligible_for_default_gate=true")
        if payload.get("readiness_state") != "ready_for_default_gate":
            errors.append(f"{prefix}.ready_for_workflow requires readiness_state=ready_for_default_gate")
        if blocking_gates:
            errors.append(f"{prefix}.ready_for_workflow requires empty blocking_gates")
        if report_errors:
            errors.append(f"{prefix}.ready_for_workflow requires empty errors")
        if blocked_items:
            errors.append(f"{prefix}.ready_for_workflow requires all review_decision_items ready")
        if payload.get("gold_requirement_state") != "satisfied":
            errors.append(f"{prefix}.ready_for_workflow requires satisfied gold_requirement_state")
        for name in ["simulated_reference_manifest_path", "readiness_report_path"]:
            if not payload.get(name):
                errors.append(f"{prefix}.ready_for_workflow requires {name}")
    elif submission_state == "blocked_preflight":
        if ready is True:
            errors.append(f"{prefix}.blocked_preflight requires ready_for_reference_workflow=false")
        if ready_to_apply is True:
            errors.append(f"{prefix}.blocked_preflight requires ready_to_apply=false")
        if eligible is True:
            errors.append(f"{prefix}.blocked_preflight requires eligible_for_default_gate=false")
        if not blocking_gates:
            errors.append(f"{prefix}.blocked_preflight requires blocking_gates")
        if not report_errors:
            errors.append(f"{prefix}.blocked_preflight requires errors")
    elif submission_state == "blocked_readiness":
        if ready is True:
            errors.append(f"{prefix}.blocked_readiness requires ready_for_reference_workflow=false")
        if ready_to_apply is not True:
            errors.append(f"{prefix}.blocked_readiness requires ready_to_apply=true")
        if eligible is True:
            errors.append(f"{prefix}.blocked_readiness requires eligible_for_default_gate=false")
        if not blocking_gates:
            errors.append(f"{prefix}.blocked_readiness requires blocking_gates")
        if not reasons:
            errors.append(f"{prefix}.blocked_readiness requires reasons")
        for name in ["simulated_reference_manifest_path", "readiness_report_path"]:
            if not payload.get(name):
                errors.append(f"{prefix}.blocked_readiness requires {name}")


def validate_regression_report(payload, errors, prefix):
    require_fields(
        errors,
        payload,
        [
            "reference_version",
            "candidate_run_id",
            "baseline_run_id",
            "regression_state",
            "eligible_for_default_gate",
            "blocking_gates",
            "reasons",
            "next_actions",
            "thresholds",
            "deltas",
            "evidence_paths",
        ],
        prefix,
    )
    require_non_empty_string(errors, payload.get("reference_version"), f"{prefix}.reference_version")
    require_non_empty_string(errors, payload.get("candidate_run_id"), f"{prefix}.candidate_run_id")
    if payload.get("baseline_run_id") is not None:
        require_type(errors, payload.get("baseline_run_id"), str, f"{prefix}.baseline_run_id")
    regression_state = payload.get("regression_state")
    if regression_state not in REGRESSION_STATES:
        errors.append(f"{prefix}.regression_state is invalid: {regression_state!r}")
    require_type(errors, payload.get("eligible_for_default_gate"), bool, f"{prefix}.eligible_for_default_gate")
    require_type(errors, payload.get("blocking_gates"), list, f"{prefix}.blocking_gates")
    require_type(errors, payload.get("reasons"), list, f"{prefix}.reasons")
    require_type(errors, payload.get("next_actions"), list, f"{prefix}.next_actions")
    validate_regression_thresholds(payload.get("thresholds"), errors, f"{prefix}.thresholds")
    validate_regression_deltas(payload.get("deltas"), errors, f"{prefix}.deltas")
    evidence_paths = payload.get("evidence_paths")
    require_type(errors, evidence_paths, list, f"{prefix}.evidence_paths")
    if isinstance(evidence_paths, list):
        for index, evidence_path in enumerate(evidence_paths):
            require_non_empty_string(errors, evidence_path, f"{prefix}.evidence_paths[{index}]")
    enforce_regression_invariants(payload, errors, prefix)


def validate_regression_thresholds(payload, errors, prefix):
    if not isinstance(payload, dict):
        errors.append(f"{prefix} must be dict")
        return
    fields = [
        "weighted_cer_regression_pp",
        "empty_final_count_delta",
        "timeout_count_delta",
        "crash_count_delta",
        "sidecar_unavailable_count_delta",
        "permission_asset_failure_count_delta",
    ]
    require_fields(errors, payload, fields, prefix)
    for field in fields:
        require_non_negative_number(errors, payload.get(field), f"{prefix}.{field}")


def validate_regression_deltas(payload, errors, prefix):
    if not isinstance(payload, dict):
        errors.append(f"{prefix} must be dict")
        return
    for name, value in payload.items():
        require_number(errors, value, f"{prefix}.{name}")


def enforce_regression_invariants(payload, errors, prefix):
    regression_state = payload.get("regression_state")
    eligible = payload.get("eligible_for_default_gate")
    blocking_gates = payload.get("blocking_gates") or []

    if regression_state == "passed":
        if eligible is not True:
            errors.append(f"{prefix}.passed requires eligible_for_default_gate=true")
        if blocking_gates:
            errors.append(f"{prefix}.passed requires empty blocking_gates")
    elif regression_state in REGRESSION_STATES:
        if eligible is True:
            errors.append(f"{prefix}.non-passed state requires eligible_for_default_gate=false")
        if not blocking_gates:
            errors.append(f"{prefix}.non-passed state requires blocking_gates")


def validate_reference_review_progress_report(payload, errors, prefix):
    require_fields(
        errors,
        payload,
        [
            "reference_version",
            "reference_manifest_path",
            "progress_state",
            "counts",
            "duration_minutes",
            "next_batch_max_duration_minutes",
            "next_batch_sample_ids",
            "next_batch_review_pack_command",
            "next_actions",
        ],
        prefix,
    )
    require_non_empty_string(errors, payload.get("reference_version"), f"{prefix}.reference_version")
    require_non_empty_string(
        errors,
        payload.get("reference_manifest_path"),
        f"{prefix}.reference_manifest_path",
    )
    progress_state = payload.get("progress_state")
    if progress_state not in REFERENCE_REVIEW_PROGRESS_STATES:
        errors.append(f"{prefix}.progress_state is invalid: {progress_state!r}")
    validate_reference_review_progress_counts(payload.get("counts"), errors, f"{prefix}.counts")
    validate_reference_review_progress_durations(
        payload.get("duration_minutes"),
        errors,
        f"{prefix}.duration_minutes",
    )
    require_non_negative_number(
        errors,
        payload.get("next_batch_max_duration_minutes"),
        f"{prefix}.next_batch_max_duration_minutes",
    )
    require_type(errors, payload.get("next_batch_sample_ids"), list, f"{prefix}.next_batch_sample_ids")
    if isinstance(payload.get("next_batch_sample_ids"), list):
        for index, sample_id in enumerate(payload["next_batch_sample_ids"]):
            require_non_empty_string(errors, sample_id, f"{prefix}.next_batch_sample_ids[{index}]")
    require_type(
        errors,
        payload.get("next_batch_review_pack_command"),
        str,
        f"{prefix}.next_batch_review_pack_command",
    )
    require_type(errors, payload.get("next_actions"), list, f"{prefix}.next_actions")
    enforce_reference_review_progress_invariants(payload, errors, prefix)


def validate_reference_review_progress_counts(counts, errors, prefix):
    if not isinstance(counts, dict):
        errors.append(f"{prefix} must be dict")
        return
    fields = [
        "sample_count",
        "gold_count",
        "dev_count",
        "stress_count",
        "reviewed_count",
        "unreviewed_count",
        "excluded_count",
        "reference_quality_issue_count",
    ]
    require_fields(errors, counts, fields, prefix)
    for field in fields:
        require_non_negative_int(errors, counts.get(field), f"{prefix}.{field}")


def validate_reference_review_progress_durations(durations, errors, prefix):
    if not isinstance(durations, dict):
        errors.append(f"{prefix} must be dict")
        return
    fields = [
        "total",
        "reviewed",
        "unreviewed",
        "excluded",
        "next_batch",
    ]
    require_fields(errors, durations, fields, prefix)
    for field in fields:
        require_non_negative_number(errors, durations.get(field), f"{prefix}.{field}")


def enforce_reference_review_progress_invariants(payload, errors, prefix):
    progress_state = payload.get("progress_state")
    counts = payload.get("counts") or {}
    next_batch_sample_ids = payload.get("next_batch_sample_ids") or []
    next_actions = payload.get("next_actions") or []
    if progress_state == "review_complete":
        if int_or_zero(counts.get("unreviewed_count")):
            errors.append(f"{prefix}.review_complete cannot have unreviewed references")
        if next_batch_sample_ids:
            errors.append(f"{prefix}.review_complete requires empty next_batch_sample_ids")
    else:
        if not next_actions:
            errors.append(f"{prefix}.non-complete progress requires next_actions")
        if int_or_zero(counts.get("unreviewed_count")) and not next_batch_sample_ids:
            errors.append(f"{prefix}.unreviewed references require next_batch_sample_ids")


def validate_reference_review_batch_workflow_report(payload, errors, prefix):
    require_fields(
        errors,
        payload,
        [
            "reference_version",
            "source_reference_manifest_path",
            "review_decisions_path",
            "workflow_state",
            "applied",
            "preflight_state",
            "ready_to_apply",
            "preflight_report_path",
            "applied_reference_manifest_path",
            "progress_state",
            "progress_report_path",
            "readiness_state",
            "readiness_report_path",
            "next_actions",
        ],
        prefix,
    )
    require_non_empty_string(errors, payload.get("reference_version"), f"{prefix}.reference_version")
    require_non_empty_string(
        errors,
        payload.get("source_reference_manifest_path"),
        f"{prefix}.source_reference_manifest_path",
    )
    require_non_empty_string(
        errors,
        payload.get("review_decisions_path"),
        f"{prefix}.review_decisions_path",
    )
    workflow_state = payload.get("workflow_state")
    if workflow_state not in REFERENCE_REVIEW_BATCH_WORKFLOW_STATES:
        errors.append(f"{prefix}.workflow_state is invalid: {workflow_state!r}")
    if payload.get("preflight_state") not in REFERENCE_REVIEW_PREFLIGHT_STATES:
        errors.append(f"{prefix}.preflight_state is invalid: {payload.get('preflight_state')!r}")
    progress_state = payload.get("progress_state")
    if progress_state and progress_state not in REFERENCE_REVIEW_PROGRESS_STATES:
        errors.append(f"{prefix}.progress_state is invalid: {progress_state!r}")
    readiness_state = payload.get("readiness_state")
    if readiness_state and readiness_state not in REFERENCE_READINESS_STATES:
        errors.append(f"{prefix}.readiness_state is invalid: {readiness_state!r}")
    require_type(errors, payload.get("applied"), bool, f"{prefix}.applied")
    require_type(errors, payload.get("ready_to_apply"), bool, f"{prefix}.ready_to_apply")
    for name in [
        "preflight_report_path",
        "applied_reference_manifest_path",
        "progress_report_path",
        "readiness_report_path",
    ]:
        require_type(errors, payload.get(name), str, f"{prefix}.{name}")
    require_type(errors, payload.get("next_actions"), list, f"{prefix}.next_actions")
    enforce_reference_review_batch_workflow_invariants(payload, errors, prefix)


def enforce_reference_review_batch_workflow_invariants(payload, errors, prefix):
    workflow_state = payload.get("workflow_state")
    if workflow_state == "blocked_preflight":
        if payload.get("applied") is not False:
            errors.append(f"{prefix}.blocked_preflight requires applied=false")
        if payload.get("ready_to_apply") is not False:
            errors.append(f"{prefix}.blocked_preflight requires ready_to_apply=false")
        if not payload.get("next_actions"):
            errors.append(f"{prefix}.blocked_preflight requires next_actions")
    if workflow_state == "applied":
        if payload.get("applied") is not True:
            errors.append(f"{prefix}.applied state requires applied=true")
        if payload.get("ready_to_apply") is not True:
            errors.append(f"{prefix}.applied state requires ready_to_apply=true")
        for name in [
            "applied_reference_manifest_path",
            "progress_report_path",
            "readiness_report_path",
        ]:
            if not payload.get(name):
                errors.append(f"{prefix}.applied state requires {name}")


def validate_reference_set_if_present(payload, errors, prefix):
    if "references" not in payload:
        return

    require_fields(errors, payload, ["sample_count", "split_counts"], prefix)
    references = payload.get("references")
    if not isinstance(references, list):
        errors.append(f"{prefix}.references must be list")
        return
    if not references:
        errors.append(f"{prefix}.references must not be empty")

    require_non_negative_int(errors, payload.get("sample_count"), f"{prefix}.sample_count")
    split_counts = payload.get("split_counts")
    require_type(errors, split_counts, dict, f"{prefix}.split_counts")

    actual_split_counts = {split: 0 for split in REFERENCE_SPLITS}
    reference_quality_issue_count = 0
    for index, row in enumerate(references):
        if not isinstance(row, dict):
            errors.append(f"{prefix}.references[{index}] must be an object")
            continue
        validate_reference_row(row, errors, f"{prefix}.references[{index}]")
        split = row.get("split")
        if split in actual_split_counts:
            actual_split_counts[split] += 1
        if row.get("reference_quality_issue") is True:
            reference_quality_issue_count += 1

    if isinstance(payload.get("sample_count"), int) and payload.get("sample_count") != len(references):
        errors.append(f"{prefix}.sample_count must equal references length")
    if isinstance(split_counts, dict):
        for split, count in split_counts.items():
            if split not in REFERENCE_SPLITS:
                errors.append(f"{prefix}.split_counts has invalid split: {split!r}")
                continue
            require_non_negative_int(errors, count, f"{prefix}.split_counts.{split}")
        for split in sorted(REFERENCE_SPLITS):
            if split_counts.get(split, 0) != actual_split_counts[split]:
                errors.append(
                    f"{prefix}.split_counts.{split} must equal references split count"
                )
    if payload.get("reference_quality_issue_count") != reference_quality_issue_count:
        errors.append(
            f"{prefix}.reference_quality_issue_count must equal audited issue rows"
        )


def validate_reference_row(row, errors, prefix):
    require_fields(
        errors,
        row,
        [
            "sample_id",
            "audio_path",
            "source_smi_path",
            "source_smi_sha256",
            "reference_text_path",
            "reference_text_sha256",
            "split",
            "review_status",
            "reviewer",
            "reviewed_at",
            "duration_seconds",
            "domain",
            "speaker_density",
            "noise_level",
            "difficulty_tags",
            "known_issue_ranges",
            "exclusion_reason",
            "reference_quality_issue",
        ],
        prefix,
    )

    for name in [
        "sample_id",
        "audio_path",
        "source_smi_path",
        "source_smi_sha256",
        "reference_text_path",
        "reference_text_sha256",
        "domain",
        "speaker_density",
        "noise_level",
    ]:
        require_non_empty_string(errors, row.get(name), f"{prefix}.{name}")

    split = row.get("split")
    review_status = row.get("review_status")
    if split not in REFERENCE_SPLITS:
        errors.append(f"{prefix}.split is invalid: {split!r}")
    if review_status not in REFERENCE_REVIEW_STATUSES:
        errors.append(f"{prefix}.review_status is invalid: {review_status!r}")
    require_number(errors, row.get("duration_seconds"), f"{prefix}.duration_seconds")
    if isinstance(row.get("duration_seconds"), (int, float)) and row.get("duration_seconds") < 0:
        errors.append(f"{prefix}.duration_seconds must be non-negative")
    require_type(errors, row.get("difficulty_tags"), list, f"{prefix}.difficulty_tags")
    require_type(errors, row.get("known_issue_ranges"), list, f"{prefix}.known_issue_ranges")
    require_type(errors, row.get("reference_quality_issue"), bool, f"{prefix}.reference_quality_issue")

    if isinstance(row.get("difficulty_tags"), list):
        for index, tag in enumerate(row["difficulty_tags"]):
            require_non_empty_string(errors, tag, f"{prefix}.difficulty_tags[{index}]")
    if isinstance(row.get("known_issue_ranges"), list):
        for index, issue_range in enumerate(row["known_issue_ranges"]):
            validate_known_issue_range(issue_range, errors, f"{prefix}.known_issue_ranges[{index}]")

    if split == "gold" and review_status != "reviewed":
        errors.append(f"{prefix}.gold split requires review_status=reviewed")
    if review_status == "reviewed":
        require_non_empty_string(errors, row.get("reviewer"), f"{prefix}.reviewer")
        require_non_empty_string(errors, row.get("reviewed_at"), f"{prefix}.reviewed_at")
    if review_status == "excluded":
        require_non_empty_string(errors, row.get("exclusion_reason"), f"{prefix}.exclusion_reason")


def validate_known_issue_range(issue_range, errors, prefix):
    if not isinstance(issue_range, dict):
        errors.append(f"{prefix} must be an object")
        return
    require_fields(
        errors,
        issue_range,
        ["start_seconds", "end_seconds", "issue_type", "note"],
        prefix,
    )
    require_number(errors, issue_range.get("start_seconds"), f"{prefix}.start_seconds")
    require_number(errors, issue_range.get("end_seconds"), f"{prefix}.end_seconds")
    require_non_empty_string(errors, issue_range.get("issue_type"), f"{prefix}.issue_type")
    require_non_empty_string(errors, issue_range.get("note"), f"{prefix}.note")
    start = issue_range.get("start_seconds")
    end = issue_range.get("end_seconds")
    if (
        isinstance(start, (int, float))
        and not isinstance(start, bool)
        and isinstance(end, (int, float))
        and not isinstance(end, bool)
        and end < start
    ):
        errors.append(f"{prefix}.end_seconds must be greater than or equal to start_seconds")


def enforce_decision_invariants(payload, errors, prefix):
    decision_state = payload.get("decision_state")
    default_change = payload.get("default_change")
    benchmark = payload.get("benchmark_run_manifest") or {}
    manual = payload.get("manual_review_manifest") or {}
    reference = payload.get("reference_manifest") or {}
    metric = payload.get("metric_summary") or {}
    readiness = payload.get("reference_readiness_report")
    regression = payload.get("regression_report")

    manual_complete = manual.get("complete")
    manual_followup_count = int_or_zero(manual.get("manual_followup_count"))
    next_buckets = manual.get("next_bucket_counts") or {}
    boundary_count = int_or_zero(next_buckets.get("boundary_slicing_issue"))
    reference_bucket_count = int_or_zero(next_buckets.get("reference_quality_issue"))
    reference_issue_count = int_or_zero(reference.get("reference_quality_issue_count"))
    benchmark_reference_version = benchmark.get("reference_version")
    reference_version = reference.get("reference_version")
    reference_version_mismatch = benchmark_reference_version != reference_version
    readiness_state = readiness.get("readiness_state") if isinstance(readiness, dict) else None
    readiness_reference_version = readiness.get("reference_version") if isinstance(readiness, dict) else None
    regression_state = regression.get("regression_state") if isinstance(regression, dict) else None
    regression_reference_version = regression.get("reference_version") if isinstance(regression, dict) else None

    if decision_state == "default_allowed":
        if default_change != "allowed":
            errors.append(f"{prefix}.default_allowed requires default_change=allowed")
        if benchmark.get("product_path") is not True:
            errors.append(f"{prefix}.default_allowed requires product_path=true")
        if (benchmark.get("runner_contract") or {}).get("dry_run") is True:
            errors.append(f"{prefix}.default_allowed cannot use dry_run product path")
        if manual_complete is not True:
            errors.append(f"{prefix}.default_allowed requires manual_review_manifest.complete=true")
        if manual_followup_count:
            errors.append(f"{prefix}.default_allowed requires manual_followup_count=0")
        if reference.get("review_status") != "reviewed":
            errors.append(f"{prefix}.default_allowed requires reviewed reference_manifest")
        if reference_issue_count or reference_bucket_count:
            errors.append(f"{prefix}.default_allowed cannot have reference quality issues")
        if boundary_count:
            errors.append(f"{prefix}.default_allowed cannot have boundary_slicing_issue rows")
        if int_or_zero(metric.get("timeout_count")):
            errors.append(f"{prefix}.default_allowed cannot have timeouts")
        if int_or_zero(metric.get("crash_count")):
            errors.append(f"{prefix}.default_allowed cannot have crashes")
        if metric.get("user_impact_metric_complete") is not True:
            errors.append(f"{prefix}.default_allowed requires user_impact_metric_complete=true")
        if not isinstance(readiness, dict):
            errors.append(f"{prefix}.default_allowed requires reference_readiness_report")
        elif readiness_state != "ready_for_default_gate":
            errors.append(f"{prefix}.default_allowed requires ready_for_default_gate reference readiness")
        if not isinstance(regression, dict):
            errors.append(f"{prefix}.default_allowed requires regression_report")
        elif regression_state != "passed":
            errors.append(f"{prefix}.default_allowed requires passed regression_report")
        elif regression_reference_version != benchmark_reference_version:
            errors.append(f"{prefix}.default_allowed requires current regression_report")

    if isinstance(readiness, dict) and readiness_reference_version != reference_version:
        if decision_state != "blocked_reference_quality":
            errors.append(
                f"{prefix}.reference_readiness_report version mismatch requires "
                "decision_state=blocked_reference_quality"
            )
        if "stale_reference_readiness_report" not in (payload.get("blocking_gates") or []):
            errors.append(
                f"{prefix}.reference_readiness_report version mismatch requires "
                "stale_reference_readiness_report blocking gate"
            )

    if reference_version_mismatch:
        if decision_state != "blocked_reference_quality":
            errors.append(
                f"{prefix}.reference_version mismatch requires decision_state=blocked_reference_quality"
            )
        if "stale_reference_version" not in (payload.get("blocking_gates") or []):
            errors.append(
                f"{prefix}.reference_version mismatch requires stale_reference_version blocking gate"
            )

    if manual_complete is False and decision_state != "blocked_manual_review":
        errors.append(
            f"{prefix}.manual_review_manifest.complete=false requires decision_state=blocked_manual_review"
        )

    if manual_followup_count and decision_state != "blocked_manual_review":
        errors.append(
            f"{prefix}.manual_followup_count>0 requires decision_state=blocked_manual_review"
        )

    if (reference_issue_count or reference_bucket_count) and decision_state in {
        "default_allowed",
        "experimental_flag_only",
        "fallback_only",
        "sidecar_candidate",
    }:
        errors.append(
            f"{prefix}.reference quality issues block default/fallback/sidecar candidate states"
        )

    if boundary_count and decision_state == "default_allowed":
        errors.append(f"{prefix}.boundary_slicing_issue requires a non-default state")


def require_fields(errors, payload, fields, prefix):
    for field in fields:
        if field not in payload:
            errors.append(f"{prefix}.{field} is required")


def require_type(errors, value, expected_type, name):
    if value is None:
        return
    if not isinstance(value, expected_type):
        errors.append(f"{name} must be {expected_type.__name__}")


def require_string_list(errors, value, name):
    require_type(errors, value, list, name)
    if isinstance(value, list):
        for index, item in enumerate(value):
            require_non_empty_string(errors, item, f"{name}[{index}]")


def require_number(errors, value, name):
    if not isinstance(value, (int, float)) or isinstance(value, bool):
        errors.append(f"{name} must be a number")


def require_non_negative_number(errors, value, name):
    if not isinstance(value, (int, float)) or isinstance(value, bool) or value < 0:
        errors.append(f"{name} must be a non-negative number")


def require_ratio(errors, value, name):
    if not isinstance(value, (int, float)) or isinstance(value, bool) or value < 0 or value > 1:
        errors.append(f"{name} must be a number between 0 and 1")


def require_non_negative_int(errors, value, name):
    if not isinstance(value, int) or isinstance(value, bool) or value < 0:
        errors.append(f"{name} must be a non-negative integer")


def require_non_empty_string(errors, value, name):
    if not isinstance(value, str) or not value.strip():
        errors.append(f"{name} must be a non-empty string")


def int_or_zero(value):
    return value if isinstance(value, int) and not isinstance(value, bool) else 0


def number_or_zero(value):
    return value if isinstance(value, (int, float)) and not isinstance(value, bool) else 0


def main_for_tests(manifest_paths):
    has_errors = False
    for path in manifest_paths:
        payload = read_json(path)
        errors = validate_manifest(payload)
        if errors:
            has_errors = True
            print(f"{path}: invalid")
            for error in errors:
                print(f"  - {error}")
        else:
            print(f"{path}: ok")
    return 1 if has_errors else 0


def main(argv=None):
    args = parse_args(argv)
    return main_for_tests(args.manifest)


if __name__ == "__main__":
    raise SystemExit(main())
