import copy
import importlib
import io
import json
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "lib"
sys.path.insert(0, str(SCRIPTS))

validator = importlib.import_module("validate_stt_benchmark_manifest")


class STTBenchmarkManifestTests(unittest.TestCase):

    def valid_decision_manifest(self):
        path = ROOT / "fixtures/minimal_decision_manifest.json"
        return json.loads(path.read_text(encoding="utf-8"))

    def reference_audit_manifest(self):
        path = ROOT / "fixtures/reference_audit_manifest.json"
        return json.loads(path.read_text(encoding="utf-8"))

    def complete_user_impact_metric_summary(self):
        path = ROOT / "fixtures/complete_user_impact_metric_summary.json"
        return json.loads(path.read_text(encoding="utf-8"))

    def regression_report(self):
        path = ROOT / "fixtures/minimal_regression_report.json"
        return json.loads(path.read_text(encoding="utf-8"))

    def release_gate_report(self):
        return {
            "manifest_type": "official_comparison_release_gate_report",
            "schema_version": 1,
            "release_state": "ready_for_default_release",
            "eligible_for_default_release": True,
            "preflight_workflow_report_path": "/tmp/official_comparison_preflight_workflow_report.json",
            "decision_workflow_report_path": "/tmp/official_decision_workflow_report.json",
            "decision_manifest_path": "/tmp/official_stt_decision_manifest.json",
            "regression_report_path": "/tmp/regression_report.json",
            "preflight_workflow_state": "ready_for_official_comparison",
            "preflight_eligible_for_official_comparison": True,
            "decision_workflow_state": "completed",
            "decision_state": "default_allowed",
            "default_change": "allowed",
            "eligible_for_default": True,
            "regression_state": "passed",
            "preflight_reference_version": "fixture-reference-v1",
            "decision_reference_version": "fixture-reference-v1",
            "regression_reference_version": "fixture-reference-v1",
            "blocking_gates": [],
            "blocking_reasons": [],
            "next_actions": ["Use this release gate report as default-change release evidence."],
            "evidence_paths": ["/tmp/official_comparison_release_gate_report.json"],
            "markdown_report_path": "/tmp/official_comparison_release_gate_report.md",
            "html_report_path": "/tmp/official_comparison_release_gate_report.html",
        }

    def release_next_open_execution_summary(self):
        return {
            "operator_evidence_next_open_execution_step_id": "collect_reference_review",
            "operator_evidence_next_open_execution_step_title": (
                "Complete reference review and gold split promotion"
            ),
            "operator_evidence_next_open_execution_step_task_ids": [
                "reference_review"
            ],
            "operator_evidence_next_open_execution_step_return_fields": [
                "reference_review_workflow_report_path"
            ],
            "operator_evidence_next_open_execution_step_blocking_submission_slot_ids": [
                "reference_review_workflow_report"
            ],
            "operator_evidence_next_open_execution_step_blocking_submission_slot_details": [
                {
                    "slot_id": "reference_review_workflow_report",
                    "slot_type": "reference_review_workflow_report",
                    "slot_status": "missing",
                    "task_id": "reference_review",
                    "title": "Return applied reference review workflow report",
                    "return_field": "reference_review_workflow_report_path",
                    "expected_manifest_types": [
                        "reference_review_batch_workflow_report"
                    ],
                    "expected_submission_path": (
                        "/tmp/reference_review_workflow/"
                        "reference_review_batch_workflow_report.json"
                    ),
                    "expected_submission_path_state": "known_from_command_template",
                    "expected_submission_path_file_state": "missing",
                    "primary_blocker_reason": (
                        "reference_review_workflow_report_path is missing"
                    ),
                    "first_command_template": (
                        "python3 scripts/run_stt_reference_review_batch_workflow.py "
                        "--review-decisions /tmp/reference_review_decisions.csv "
                        "--output-root /tmp/reference_review_workflow"
                    ),
                    "command_template_paths": [
                        "/tmp/reference_review_workflow_command_template.txt"
                    ],
                    "source_artifact_hint_paths": [
                        "/tmp/reference_review_pack.html"
                    ],
                    "metadata": {},
                    "next_action": "Run reference review workflow.",
                    "next_actions": ["Run reference review workflow."],
                }
            ],
            "operator_evidence_next_open_execution_step_source_artifact_hint_paths": [
                "/tmp/reference_review_pack.html"
            ],
            "operator_evidence_next_open_execution_step_command_template_paths": [
                "/tmp/reference_review_workflow_command_template.txt"
            ],
            "operator_evidence_next_open_execution_step_next_actions": [
                "Run reference review workflow."
            ],
        }

    def execution_plan_next_open_summary(self):
        prefix = "operator_evidence_"
        return {
            key[len(prefix):]: copy.deepcopy(value)
            for key, value in self.release_next_open_execution_summary().items()
        }

    def release_workflow_report(self):
        return {
            "manifest_type": "official_release_workflow_report",
            "schema_version": 1,
            "workflow_state": "blocked_operator_evidence",
            "release_state": "blocked_preflight",
            "eligible_for_default_release": False,
            "target_reference_version": "fixture-reference-v1",
            "preflight_workflow_report_path": "/tmp/official_comparison_preflight_workflow_report.json",
            "decision_workflow_report_path": "/tmp/official_decision_workflow_report.json",
            "artifact_prep_report_path": (
                "/tmp/official_comparison_next_action_artifact_prep_report.json"
            ),
            "execution_status_report_path": (
                "/tmp/official_comparison_next_action_execution_status_report.json"
            ),
            "operator_handoff_report_path": "/tmp/official_comparison_operator_handoff_report.json",
            "operator_evidence_intake_report_path": (
                "/tmp/official_comparison_operator_evidence_intake_report.json"
            ),
            "preflight_resume_plan_path": "/tmp/official_comparison_preflight_resume_plan.json",
            "release_gate_report_path": "/tmp/official_comparison_release_gate_report.json",
            "operator_handoff_state": "blocked_waiting_for_operator_evidence",
            "operator_handoff_item_count": 4,
            "operator_handoff_ready_item_count": 0,
            "operator_handoff_blocked_item_count": 4,
            "operator_evidence_intake_state": "blocked_missing_operator_evidence",
            "operator_evidence_ready_to_rerun_preflight": False,
            "operator_evidence_accepted_item_count": 0,
            "operator_evidence_missing_item_count": 4,
            "operator_evidence_rejected_item_count": 0,
            "operator_evidence_request_report_path": (
                "/tmp/official_comparison_operator_evidence_request_report.json"
            ),
            "operator_evidence_request_state": "needs_operator_evidence",
            "operator_evidence_requested_task_count": 4,
            "operator_evidence_request_target_reference_version": "fixture-reference-v1",
            "operator_evidence_return_template_path": (
                "/tmp/operator_evidence_return_template.json"
            ),
            "operator_evidence_return_guide_markdown_path": (
                "/tmp/operator_evidence_return_guide.md"
            ),
            "operator_evidence_return_guide_html_path": (
                "/tmp/operator_evidence_return_guide.html"
            ),
            "operator_evidence_return_template_fill_command_template_path": (
                "/tmp/operator_evidence_return_template_fill_command_template.txt"
            ),
            "operator_evidence_return_workflow_command_template_path": (
                "/tmp/operator_evidence_return_workflow_command_template.txt"
            ),
            "operator_evidence_intake_command_template_path": (
                "/tmp/operator_evidence_intake_command_template.txt"
            ),
            "operator_evidence_release_workflow_command_template_path": (
                "/tmp/operator_evidence_release_workflow_command_template.txt"
            ),
            "command_template_paths": [
                "/tmp/operator_evidence_return_template_fill_command_template.txt",
                "/tmp/operator_evidence_return_workflow_command_template.txt",
                "/tmp/operator_evidence_intake_command_template.txt",
                "/tmp/operator_evidence_release_workflow_command_template.txt",
            ],
            "adoption_checklist_report_path": (
                "/tmp/official_comparison_adoption_checklist_report.json"
            ),
            "adoption_state": "blocked_official_adoption",
            "adoption_passed_item_count": 4,
            "adoption_blocked_item_count": 6,
            "adoption_unknown_item_count": 0,
            "adoption_remediation_plan_path": (
                "/tmp/official_comparison_adoption_remediation_plan.json"
            ),
            "adoption_remediation_plan_state": "ready_to_collect_evidence",
            "adoption_remediation_target_reference_version": "fixture-reference-v1",
            "adoption_remediation_task_count": 4,
            "adoption_remediation_open_task_count": 4,
            "operator_evidence_return_field_requirements": [
                {
                    "field": "reference_review_workflow_report_path",
                    "task_ids": ["reference_review"],
                    "requested_task_ids": ["reference_review"],
                    "source_paths": ["/tmp/reference_review_pack.md"],
                    "adoption_item_ids": [
                        "reference_reviewed_gold",
                        "gold_dev_stress_split_separated",
                        "reference_confidence_floor",
                    ],
                    "evidence_to_return": ["reference_review_batch_workflow_report"],
                    "acceptance_criteria": [
                        "reference_review_batch_workflow_report.workflow_state=applied"
                    ],
                    "next_actions": ["Return accepted operator evidence."],
                    "command_template_paths": [
                        "/tmp/operator_evidence_return_template_fill_command_template.txt",
                        "/tmp/operator_evidence_release_workflow_command_template.txt"
                    ],
                },
                {
                    "field": "run_bundle_manifest_paths",
                    "task_ids": [
                        "align_engine_reference_version",
                        "align_engine_comparability_contract",
                        "product_path_official_run",
                    ],
                    "requested_task_ids": [
                        "align_engine_reference_version",
                        "align_engine_comparability_contract",
                        "product_path_official_run",
                    ],
                    "source_paths": ["/tmp/engine_comparability_rerun_plan.md"],
                    "adoption_item_ids": [
                        "whisperkit_product_path_user_impact",
                        "product_path_only_default_decision",
                        "release_gate_ready_for_default",
                    ],
                    "evidence_to_return": ["engine_run_bundle_manifest"],
                    "acceptance_criteria": ["run bundle reference_version matches target"],
                    "next_actions": ["Return accepted operator evidence."],
                    "command_template_paths": [
                        "/tmp/operator_evidence_return_template_fill_command_template.txt",
                        "/tmp/operator_evidence_release_workflow_command_template.txt"
                    ],
                },
                {
                    "field": "target_reference_version",
                    "task_ids": [
                        "align_engine_reference_version",
                        "align_engine_comparability_contract",
                        "product_path_official_run",
                    ],
                    "requested_task_ids": [
                        "align_engine_reference_version",
                        "align_engine_comparability_contract",
                        "product_path_official_run",
                    ],
                    "source_paths": ["/tmp/engine_comparability_rerun_plan.md"],
                    "adoption_item_ids": [
                        "whisperkit_product_path_user_impact",
                        "product_path_only_default_decision",
                        "release_gate_ready_for_default",
                    ],
                    "evidence_to_return": ["target_reference_version"],
                    "acceptance_criteria": ["target_reference_version matches release target"],
                    "next_actions": ["Return accepted operator evidence."],
                    "command_template_paths": [
                        "/tmp/operator_evidence_return_template_fill_command_template.txt",
                        "/tmp/operator_evidence_release_workflow_command_template.txt"
                    ],
                },
            ],
            "adoption_blockers": [
                self.release_workflow_adoption_blocker(
                    "reference_reviewed_gold",
                    ["reference_review"],
                    ["reference_review_workflow_report_path"],
                ),
                self.release_workflow_adoption_blocker(
                    "gold_dev_stress_split_separated",
                    ["reference_review"],
                    ["reference_review_workflow_report_path"],
                ),
                self.release_workflow_adoption_blocker(
                    "reference_confidence_floor",
                    ["reference_review"],
                    ["reference_review_workflow_report_path"],
                ),
                self.release_workflow_adoption_blocker(
                    "whisperkit_product_path_user_impact",
                    ["product_path_official_run"],
                    ["target_reference_version", "run_bundle_manifest_paths"],
                ),
                self.release_workflow_adoption_blocker(
                    "product_path_only_default_decision",
                    ["product_path_official_run"],
                    ["target_reference_version", "run_bundle_manifest_paths"],
                ),
                self.release_workflow_adoption_blocker(
                    "release_gate_ready_for_default",
                    [
                        "align_engine_reference_version",
                        "align_engine_comparability_contract",
                        "product_path_official_run",
                    ],
                    ["target_reference_version", "run_bundle_manifest_paths"],
                ),
            ],
            "preflight_resume_plan_state": "blocked_operator_evidence",
            "preflight_resume_ready_to_rerun": False,
            "operator_tasks": [
                self.release_workflow_operator_task("reference_review", "missing"),
                self.release_workflow_operator_task("align_engine_reference_version", "missing"),
                self.release_workflow_operator_task("align_engine_comparability_contract", "missing"),
                self.release_workflow_operator_task("product_path_official_run", "missing"),
            ],
            "blocking_gates": ["preflight_not_ready"],
            "blocking_reasons": ["preflight workflow_state=blocked_preflight"],
            "next_actions": ["Return accepted operator evidence."],
            "evidence_paths": ["/tmp/official_comparison_release_gate_report.json"],
            "markdown_report_path": "/tmp/official_release_workflow_report.md",
            "html_report_path": "/tmp/official_release_workflow_report.html",
        }

    def release_artifact_audit_report(self):
        return {
            "manifest_type": "official_release_artifact_audit_report",
            "schema_version": 1,
            "audit_state": "ready_for_artifact_review",
            "release_workflow_report_path": "/tmp/official_release_workflow_report.json",
            "release_workflow_state": "blocked_operator_evidence",
            "release_state": "blocked_preflight",
            "eligible_for_default_release": False,
            "operator_evidence_intake_state": "blocked_missing_operator_evidence",
            "operator_evidence_ready_to_rerun_preflight": False,
            "operator_evidence_accepted_item_count": 0,
            "operator_evidence_missing_item_count": 4,
            "operator_evidence_rejected_item_count": 0,
            "preflight_resume_plan_state": "blocked_operator_evidence",
            "preflight_resume_ready_to_rerun": False,
            "adoption_state": "blocked_official_adoption",
            "adoption_passed_item_count": 4,
            "adoption_blocked_item_count": 6,
            "adoption_unknown_item_count": 0,
            "adoption_remediation_plan_state": "ready_to_collect_evidence",
            "adoption_remediation_open_task_count": 4,
            "artifact_count": 2,
            "valid_artifact_count": 2,
            "missing_artifact_count": 0,
            "invalid_artifact_count": 0,
            "artifacts": [
                {
                    "field": "release_workflow_report_path",
                    "path": "/tmp/official_release_workflow_report.json",
                    "artifact_kind": "json_manifest",
                    "expected_manifest_type": "official_release_workflow_report",
                    "state": "valid",
                    "errors": [],
                },
                {
                    "field": "operator_evidence_return_template_path",
                    "path": "/tmp/operator_evidence_return_template.json",
                    "artifact_kind": "json_manifest",
                    "expected_manifest_type": (
                        "official_comparison_operator_evidence_return_template"
                    ),
                    "state": "valid",
                    "errors": [],
                },
            ],
            "blocking_reasons": [],
            "next_actions": [
                "Use this artifact audit as release bundle integrity evidence."
            ],
            "evidence_paths": ["/tmp/official_release_workflow_report.json"],
            "markdown_report_path": "/tmp/official_release_artifact_audit_report.md",
            "html_report_path": "/tmp/official_release_artifact_audit_report.html",
        }

    def adoption_checklist_report(self):
        return {
            "manifest_type": "official_comparison_adoption_checklist_report",
            "schema_version": 1,
            "adoption_state": "blocked_official_adoption",
            "release_workflow_report_path": "/tmp/official_release_workflow_report.json",
            "preflight_workflow_report_path": "/tmp/official_comparison_preflight_workflow_report.json",
            "decision_workflow_report_path": "/tmp/official_decision_workflow_report.json",
            "release_state": "blocked_preflight",
            "workflow_state": "blocked_operator_evidence",
            "eligible_for_default_release": False,
            "checklist_item_count": 2,
            "passed_item_count": 1,
            "blocked_item_count": 1,
            "unknown_item_count": 0,
            "checklist_items": [
                {
                    "item_id": "report_uses_manifest_gate_results",
                    "title": "Report is backed by manifest and gate results",
                    "state": "passed",
                    "evidence_paths": ["/tmp/official_release_workflow_report.json"],
                    "reasons": ["linked release gate report exists"],
                    "next_actions": [],
                },
                {
                    "item_id": "release_gate_ready_for_default",
                    "title": "Release gate is ready for default release",
                    "state": "blocked",
                    "evidence_paths": ["/tmp/official_comparison_release_gate_report.json"],
                    "reasons": ["release_state=blocked_preflight"],
                    "next_actions": ["Return accepted operator evidence."],
                },
            ],
            "blocking_gates": ["release_gate_ready_for_default"],
            "blocking_reasons": ["release_gate_ready_for_default: release_state=blocked_preflight"],
            "next_actions": ["Return accepted operator evidence."],
            "evidence_paths": ["/tmp/official_release_workflow_report.json"],
            "markdown_report_path": "/tmp/official_comparison_adoption_checklist_report.md",
            "html_report_path": "/tmp/official_comparison_adoption_checklist_report.html",
        }

    def adoption_remediation_plan(self):
        return {
            "manifest_type": "official_comparison_adoption_remediation_plan",
            "schema_version": 1,
            "plan_state": "ready_to_collect_evidence",
            "adoption_state": "blocked_official_adoption",
            "target_reference_version": "fixture-reference-v1",
            "adoption_checklist_report_path": (
                "/tmp/official_comparison_adoption_checklist_report.json"
            ),
            "release_workflow_report_path": "/tmp/official_release_workflow_report.json",
            "operator_evidence_request_report_path": (
                "/tmp/official_comparison_operator_evidence_request_report.json"
            ),
            "operator_evidence_return_template_path": (
                "/tmp/operator_evidence_return_template.json"
            ),
            "operator_evidence_return_guide_markdown_path": (
                "/tmp/operator_evidence_return_guide.md"
            ),
            "operator_evidence_return_guide_html_path": (
                "/tmp/operator_evidence_return_guide.html"
            ),
            "operator_evidence_return_workflow_command_template_path": (
                "/tmp/operator_evidence_return_workflow_command_template.txt"
            ),
            "operator_evidence_intake_command_template_path": (
                "/tmp/operator_evidence_intake_command_template.txt"
            ),
            "operator_evidence_release_workflow_command_template_path": (
                "/tmp/operator_evidence_release_workflow_command_template.txt"
            ),
            "command_template_paths": [
                "/tmp/operator_evidence_return_workflow_command_template.txt",
                "/tmp/operator_evidence_intake_command_template.txt",
                "/tmp/operator_evidence_release_workflow_command_template.txt",
            ],
            "task_count": 1,
            "open_task_count": 1,
            "not_needed_task_count": 0,
            "return_field_requirements": [
                {
                    "field": "reference_review_workflow_report_path",
                    "task_ids": ["reference_review"],
                    "requested_task_ids": ["reference_review"],
                    "source_paths": ["/tmp/reference_review_pack.md"],
                    "adoption_item_ids": ["reference_reviewed_gold"],
                    "evidence_to_return": ["reference_review_batch_workflow_report"],
                    "acceptance_criteria": [
                        "reference_review_batch_workflow_report.workflow_state=applied"
                    ],
                    "next_actions": ["Return accepted operator evidence."],
                    "command_template_paths": [
                        "/tmp/operator_evidence_return_workflow_command_template.txt",
                        "/tmp/operator_evidence_intake_command_template.txt",
                        "/tmp/operator_evidence_release_workflow_command_template.txt"
                    ],
                    "value_type": "path",
                    "allow_multiple": False,
                    "expected_manifest_types": [
                        "reference_review_batch_workflow_report"
                    ],
                },
            ],
            "tasks": [
                {
                    "task_id": "reference_review",
                    "title": "Complete reference review",
                    "task_state": "open",
                    "request_state": "requested",
                    "execution_status": "waiting_for_manual_input",
                    "evidence_state": "missing",
                    "adoption_item_ids": ["reference_reviewed_gold"],
                    "operator_action": "Return applied reference review evidence.",
                    "evidence_to_return": ["reference_review_batch_workflow_report"],
                    "return_fields": ["reference_review_workflow_report_path"],
                    "acceptance_criteria": [
                        "reference_review_batch_workflow_report.workflow_state=applied"
                    ],
                    "reasons": ["reference review evidence is missing"],
                    "next_actions": ["Return accepted operator evidence."],
                    "source_paths": ["/tmp/reference_review_pack.md"],
                    "evidence_paths": ["/tmp/reference_review_pack.md"],
                    "command_template_paths": [
                        "/tmp/operator_evidence_return_workflow_command_template.txt",
                        "/tmp/operator_evidence_intake_command_template.txt",
                        "/tmp/operator_evidence_release_workflow_command_template.txt"
                    ],
                },
            ],
            "blocking_gates": ["reference_reviewed_gold"],
            "blocking_reasons": ["reference_reviewed_gold: reference review is missing"],
            "next_actions": ["Fill operator_evidence_return_template.json."],
            "evidence_paths": ["/tmp/official_comparison_adoption_checklist_report.json"],
            "markdown_report_path": "/tmp/official_comparison_adoption_remediation_plan.md",
            "html_report_path": "/tmp/official_comparison_adoption_remediation_plan.html",
        }

    def operator_evidence_request_report(self):
        return {
            "manifest_type": "official_comparison_operator_evidence_request_report",
            "schema_version": 1,
            "request_state": "needs_operator_evidence",
            "release_workflow_report_path": "/tmp/official_release_workflow_report.json",
            "preflight_workflow_report_path": "/tmp/official_comparison_preflight_workflow_report.json",
            "decision_workflow_report_path": "/tmp/official_decision_workflow_report.json",
            "workflow_state": "blocked_operator_evidence",
            "release_state": "blocked_preflight",
            "target_reference_version": "fixture-reference-v1",
            "operator_handoff_report_path": "/tmp/official_comparison_operator_handoff_report.json",
            "operator_evidence_intake_report_path": (
                "/tmp/official_comparison_operator_evidence_intake_report.json"
            ),
            "task_count": 1,
            "requested_task_count": 1,
            "requests": [
                {
                    "task_id": "reference_review",
                    "title": "Complete reference review",
                    "request_state": "requested",
                    "execution_status": "waiting_for_manual_input",
                    "evidence_state": "missing",
                    "adoption_item_ids": ["reference_reviewed_gold"],
                    "operator_action": "Run reference review batch workflow.",
                    "next_action": "Return reference review workflow report.",
                    "reasons": ["reference review workflow report was not provided"],
                    "evidence_to_return": ["reference_review_batch_workflow_report"],
                    "acceptance_criteria": [
                        "reference_review_batch_workflow_report.workflow_state=applied"
                    ],
                    "return_fields": ["reference_review_workflow_report_path"],
                    "source_paths": ["/tmp/reference_review_pack.html"],
                    "evidence_paths": ["/tmp/reference_review_pack.html"],
                    "command_template_paths": [
                        "/tmp/operator_evidence_return_template_fill_command_template.txt",
                        "/tmp/operator_evidence_return_workflow_command_template.txt",
                        "/tmp/operator_evidence_intake_command_template.txt",
                        "/tmp/operator_evidence_release_workflow_command_template.txt",
                    ],
                },
            ],
            "global_return_fields": [
                "target_reference_version",
                "reference_review_workflow_report_path",
                "run_bundle_manifest_paths",
            ],
            "task_return_requirements": [
                {
                    "task_id": "reference_review",
                    "title": "Complete reference review",
                    "request_state": "requested",
                    "adoption_item_ids": ["reference_reviewed_gold"],
                    "return_fields": ["reference_review_workflow_report_path"],
                    "evidence_to_return": ["reference_review_batch_workflow_report"],
                    "acceptance_criteria": [
                        "reference_review_batch_workflow_report.workflow_state=applied"
                    ],
                    "reasons": ["reference review workflow report was not provided"],
                    "next_action": "Return reference review workflow report.",
                    "source_paths": ["/tmp/reference_review_pack.html"],
                    "command_template_paths": [
                        "/tmp/operator_evidence_return_template_fill_command_template.txt",
                        "/tmp/operator_evidence_return_workflow_command_template.txt",
                        "/tmp/operator_evidence_intake_command_template.txt",
                        "/tmp/operator_evidence_release_workflow_command_template.txt",
                    ],
                },
            ],
            "return_field_requirements": [
                {
                    "field": "reference_review_workflow_report_path",
                    "task_ids": ["reference_review"],
                    "requested_task_ids": ["reference_review"],
                    "source_paths": ["/tmp/reference_review_pack.html"],
                    "adoption_item_ids": ["reference_reviewed_gold"],
                    "evidence_to_return": ["reference_review_batch_workflow_report"],
                    "acceptance_criteria": [
                        "reference_review_batch_workflow_report.workflow_state=applied"
                    ],
                    "next_actions": ["Return reference review workflow report."],
                    "command_template_paths": [
                        "/tmp/operator_evidence_return_template_fill_command_template.txt",
                        "/tmp/operator_evidence_return_workflow_command_template.txt",
                        "/tmp/operator_evidence_intake_command_template.txt",
                    ],
                },
            ],
            "return_template_path": "/tmp/operator_evidence_return_template.json",
            "return_template_fill_command_template_path": (
                "/tmp/operator_evidence_return_template_fill_command_template.txt"
            ),
            "return_workflow_command_template_path": (
                "/tmp/operator_evidence_return_workflow_command_template.txt"
            ),
            "intake_command_template_path": "/tmp/operator_evidence_intake_command_template.txt",
            "release_workflow_command_template_path": (
                "/tmp/operator_evidence_release_workflow_command_template.txt"
            ),
            "command_template_paths": [
                "/tmp/operator_evidence_return_template_fill_command_template.txt",
                "/tmp/operator_evidence_return_workflow_command_template.txt",
                "/tmp/operator_evidence_intake_command_template.txt",
                "/tmp/operator_evidence_release_workflow_command_template.txt",
            ],
            "next_actions": ["Fill operator_evidence_return_template.json."],
            "evidence_paths": ["/tmp/official_release_workflow_report.json"],
            "markdown_report_path": (
                "/tmp/official_comparison_operator_evidence_request_report.md"
            ),
            "html_report_path": (
                "/tmp/official_comparison_operator_evidence_request_report.html"
            ),
            "return_guide_markdown_path": "/tmp/operator_evidence_return_guide.md",
            "return_guide_html_path": "/tmp/operator_evidence_return_guide.html",
        }

    def operator_evidence_return_template(self):
        return {
            "manifest_type": "official_comparison_operator_evidence_return_template",
            "template_type": "official_comparison_operator_evidence_return_template",
            "schema_version": 1,
            "request_report_path": (
                "/tmp/official_comparison_operator_evidence_request_report.json"
            ),
            "target_reference_version": "fixture-reference-v1",
            "return_template_fill_command_template_path": (
                "/tmp/operator_evidence_return_template_fill_command_template.txt"
            ),
            "return_workflow_command_template_path": (
                "/tmp/operator_evidence_return_workflow_command_template.txt"
            ),
            "intake_command_template_path": "/tmp/operator_evidence_intake_command_template.txt",
            "release_workflow_command_template_path": (
                "/tmp/operator_evidence_release_workflow_command_template.txt"
            ),
            "command_template_paths": [
                "/tmp/operator_evidence_return_template_fill_command_template.txt",
                "/tmp/operator_evidence_return_workflow_command_template.txt",
                "/tmp/operator_evidence_intake_command_template.txt",
                "/tmp/operator_evidence_release_workflow_command_template.txt",
            ],
            "reference_review_workflow_report_path": "",
            "run_bundle_manifest_paths": [],
            "return_field_requirements": [
                {
                    "field": "reference_review_workflow_report_path",
                    "task_ids": ["reference_review"],
                    "requested_task_ids": ["reference_review"],
                    "source_paths": ["/tmp/reference_review_pack.md"],
                    "adoption_item_ids": ["reference_reviewed_gold"],
                    "evidence_to_return": ["reference_review_batch_workflow_report"],
                    "acceptance_criteria": [
                        "reference_review_batch_workflow_report.workflow_state=applied"
                    ],
                    "next_actions": ["Return accepted operator evidence."],
                    "command_template_paths": [
                        "/tmp/operator_evidence_return_template_fill_command_template.txt",
                        "/tmp/operator_evidence_return_workflow_command_template.txt",
                        "/tmp/operator_evidence_intake_command_template.txt",
                        "/tmp/operator_evidence_release_workflow_command_template.txt",
                    ],
                },
            ],
            "task_return_requirements": [
                {
                    "task_id": "reference_review",
                    "title": "Complete reference review",
                    "request_state": "requested",
                    "adoption_item_ids": ["reference_reviewed_gold"],
                    "return_fields": ["reference_review_workflow_report_path"],
                    "evidence_to_return": ["reference_review_batch_workflow_report"],
                    "acceptance_criteria": [
                        "reference_review_batch_workflow_report.workflow_state=applied"
                    ],
                    "reasons": ["reference review evidence is missing"],
                    "next_action": "Return accepted operator evidence.",
                    "source_paths": ["/tmp/reference_review_pack.md"],
                    "command_template_paths": [
                        "/tmp/operator_evidence_return_template_fill_command_template.txt",
                        "/tmp/operator_evidence_return_workflow_command_template.txt",
                        "/tmp/operator_evidence_intake_command_template.txt",
                        "/tmp/operator_evidence_release_workflow_command_template.txt",
                    ],
                },
            ],
            "notes": [],
        }

    def operator_evidence_submission_values_template(self):
        return {
            "manifest_type": (
                "official_comparison_operator_evidence_submission_values_template"
            ),
            "schema_version": 1,
            "submission_status_report_path": (
                "/tmp/official_comparison_operator_evidence_submission_status_report.json"
            ),
            "submission_checklist_path": (
                "/tmp/official_comparison_operator_evidence_submission_checklist.json"
            ),
            "operator_evidence_return_template_path": (
                "/tmp/operator_evidence_return_template.json"
            ),
            "target_reference_version": "fixture-reference-v1",
            "markdown_report_path": (
                "/tmp/operator_evidence_submission_values_template.md"
            ),
            "html_report_path": (
                "/tmp/operator_evidence_submission_values_template.html"
            ),
            "return_template_fill_from_status_command_template_path": (
                "/tmp/operator_evidence_return_template_fill_from_submission_status_command_template.txt"
            ),
            "return_workflow_from_status_command_template_path": (
                "/tmp/operator_evidence_return_workflow_from_status_command_template.txt"
            ),
            "release_workflow_from_status_command_template_path": (
                "/tmp/operator_evidence_release_workflow_from_status_command_template.txt"
            ),
            "editable_fields": ["slot_values[].path"],
            "path_editing_instructions": [
                "Edit only slot_values[].path values in this JSON file.",
                (
                    "Leave slot_id, return_field, slot_status, target_reference_version, "
                    "operator_evidence_return_template_path, and acceptance criteria "
                    "unchanged."
                ),
                "Blank path values are ignored by the fill command.",
            ],
            "slot_value_count": 2,
            "submission_action_group_count": 2,
            "submission_action_groups": [
                {
                    "group_id": "collect_reference_review",
                    "group_order": 1,
                    "group_status": "waiting_for_submissions",
                    "task_id": "reference_review",
                    "title": "Complete reference review and gold split promotion",
                    "slot_count": 1,
                    "submitted_slot_count": 0,
                    "missing_slot_count": 1,
                    "rejected_slot_count": 0,
                    "not_needed_slot_count": 0,
                    "slot_ids": ["reference_review_workflow_report"],
                    "blocking_slot_ids": ["reference_review_workflow_report"],
                    "return_fields": ["reference_review_workflow_report_path"],
                    "slot_types": ["reference_review_workflow_report"],
                    "expected_manifest_types": [
                        "reference_review_batch_workflow_report"
                    ],
                    "engine_ids": [],
                    "benchmark_kinds": [],
                    "sample_sets": ["reference_review_batch"],
                    "current_reference_versions": ["fixture-reference-v1"],
                    "target_reference_version": "fixture-reference-v1",
                    "evidence_to_collect": [
                        "reference_review_batch_workflow_report"
                    ],
                    "acceptance_criteria": [
                        "reference_review_batch_workflow_report.workflow_state=applied"
                    ],
                    "source_paths": ["/tmp/reference_review_pack_manifest.json"],
                    "source_candidate_summary": [
                        {
                            "candidate_state": "not_submission_manifest",
                            "candidate_count": 1,
                            "reasons": [
                                "manifest_type must be "
                                "reference_review_batch_workflow_report"
                            ],
                        }
                    ],
                    "command_template_paths": [
                        "/tmp/operator_evidence_return_template_fill_command_template.txt"
                    ],
                    "next_actions": ["Return accepted operator evidence."],
                },
                {
                    "group_id": "collect_product_path_official_run",
                    "group_order": 2,
                    "group_status": "all_slots_submitted",
                    "task_id": "product_path_official_run",
                    "title": "Capture real product-path official run evidence",
                    "slot_count": 1,
                    "submitted_slot_count": 1,
                    "missing_slot_count": 0,
                    "rejected_slot_count": 0,
                    "not_needed_slot_count": 0,
                    "slot_ids": ["product_path_bundle_speech_analyzer"],
                    "blocking_slot_ids": [],
                    "return_fields": ["run_bundle_manifest_paths"],
                    "slot_types": ["product_path_run_bundle"],
                    "expected_manifest_types": ["engine_run_bundle_manifest"],
                    "engine_ids": ["speech_analyzer"],
                    "benchmark_kinds": ["product_path_final"],
                    "sample_sets": ["product-path"],
                    "current_reference_versions": ["fixture-reference-v1"],
                    "target_reference_version": "fixture-reference-v1",
                    "evidence_to_collect": ["engine_run_bundle_manifest"],
                    "acceptance_criteria": [
                        "benchmark_run_manifest.product_path=true"
                    ],
                    "source_paths": ["/tmp/product_path_official_run_plan.json"],
                    "source_candidate_summary": [
                        {
                            "candidate_state": "usable_as_submission",
                            "candidate_count": 1,
                            "reasons": [],
                        }
                    ],
                    "command_template_paths": [
                        "/tmp/operator_evidence_return_template_fill_command_template.txt"
                    ],
                    "next_actions": [],
                },
            ],
            "filled_path_count": 1,
            "blank_path_count": 1,
            "submission_completion_state": "partial_submission_ready",
            "full_submission_ready": False,
            "remaining_required_slot_count": 1,
            "remaining_required_slot_ids": ["reference_review_workflow_report"],
            "submitted_required_slot_ids": ["product_path_bundle_speech_analyzer"],
            "missing_required_slot_ids": ["reference_review_workflow_report"],
            "rejected_required_slot_ids": [],
            "expected_submission_path_exists_count": 0,
            "expected_submission_path_missing_count": 2,
            "expected_submission_path_not_applicable_count": 0,
            "expected_submission_path_missing_slot_ids": [
                "reference_review_workflow_report",
                "product_path_bundle_speech_analyzer",
            ],
            "minimum_required_filled_path_count": 1,
            "fill_command_readiness_state": "ready_to_fill_return_template",
            "fill_command_blocking_reasons": [],
            "slot_values": [
                {
                    "slot_id": "reference_review_workflow_report",
                    "slot_status": "missing",
                    "slot_type": "reference_review_workflow_report",
                    "task_id": "reference_review",
                    "title": "Complete reference review",
                    "return_field": "reference_review_workflow_report_path",
                    "engine_id": "",
                    "benchmark_kind": "",
                    "sample_set": "reference_review_batch",
                    "current_reference_version": "fixture-reference-v1",
                    "target_reference_version": "fixture-reference-v1",
                    "editable_fields": ["path"],
                    "path": "",
                    "path_value_hint": (
                        "Path to a reference_review_batch_workflow_report JSON file."
                    ),
                    "expected_submission_path": (
                        "/tmp/reference_review_workflow/"
                        "reference_review_batch_workflow_report.json"
                    ),
                    "expected_submission_path_state": "known_from_command_template",
                    "expected_submission_path_file_state": "missing",
                    "expected_submission_path_note": (
                        "After the submission command succeeds, copy this path into "
                        "slot_values[].path."
                    ),
                    "expected_manifest_types": [
                        "reference_review_batch_workflow_report"
                    ],
                    "evidence_to_collect": [
                        "reference_review_batch_workflow_report"
                    ],
                    "acceptance_criteria": [
                        "reference_review_batch_workflow_report.workflow_state=applied"
                    ],
                    "command_template_paths": [
                        "/tmp/operator_evidence_return_template_fill_command_template.txt"
                    ],
                    "source_paths": ["/tmp/reference_review_pack_manifest.json"],
                    "source_artifact_hint_paths": [],
                    "source_candidate_diagnostics": [
                        {
                            "path": "/tmp/reference_review_pack_manifest.json",
                            "candidate_state": "not_submission_manifest",
                            "manifest_type": "",
                            "engine_id": "",
                            "benchmark_kind": "",
                            "reference_version": "fixture-reference-v1",
                            "benchmark_reference_version": "",
                            "product_path_state": "",
                            "runner_contract_dry_run_state": "",
                            "benchmark_run_manifest_path": "",
                            "reasons": [
                                "manifest_type must be "
                                "reference_review_batch_workflow_report"
                            ],
                        }
                    ],
                    "command_templates": [
                        "python3 scripts/run_stt_reference_review_batch_workflow.py "
                        "--review-decisions /tmp/reference_review_decisions.csv "
                        "--output-root /tmp/reference_review_workflow"
                    ],
                    "missing_reasons": [
                        "reference_review_workflow_report_path is missing"
                    ],
                    "rejection_reasons": [],
                    "metadata": {},
                    "next_actions": ["Return accepted operator evidence."],
                },
                {
                    "slot_id": "product_path_bundle_speech_analyzer",
                    "slot_status": "submitted",
                    "slot_type": "product_path_run_bundle",
                    "task_id": "product_path_official_run",
                    "title": "Run product path speech analyzer",
                    "return_field": "run_bundle_manifest_paths",
                    "engine_id": "speech_analyzer",
                    "benchmark_kind": "product_path_final",
                    "sample_set": "product-path",
                    "current_reference_version": "fixture-reference-v1",
                    "target_reference_version": "fixture-reference-v1",
                    "editable_fields": ["path"],
                    "path": "/tmp/engine_run_bundle_manifest.json",
                    "path_value_hint": "Path to an engine_run_bundle_manifest JSON file.",
                    "expected_submission_path": (
                        "/tmp/product_path_bundle/engine_run_bundle_manifest.json"
                    ),
                    "expected_submission_path_state": "known_from_command_template",
                    "expected_submission_path_file_state": "missing",
                    "expected_submission_path_note": (
                        "After the submission command succeeds, copy this path into "
                        "slot_values[].path."
                    ),
                    "expected_manifest_types": ["engine_run_bundle_manifest"],
                    "evidence_to_collect": ["engine_run_bundle_manifest"],
                    "acceptance_criteria": [
                        "benchmark_run_manifest.product_path=true"
                    ],
                    "command_template_paths": [
                        "/tmp/operator_evidence_return_template_fill_command_template.txt"
                    ],
                    "source_paths": ["/tmp/product_path_official_run_plan.json"],
                    "source_artifact_hint_paths": [],
                    "source_candidate_diagnostics": [
                        {
                            "path": "/tmp/engine_run_bundle_manifest.json",
                            "candidate_state": "usable_as_submission",
                            "manifest_type": "engine_run_bundle_manifest",
                            "engine_id": "speech_analyzer",
                            "benchmark_kind": "product_path_final",
                            "reference_version": "fixture-reference-v1",
                            "benchmark_reference_version": "fixture-reference-v1",
                            "product_path_state": "true",
                            "runner_contract_dry_run_state": "false",
                            "benchmark_run_manifest_path": (
                                "/tmp/benchmark_run_manifest.json"
                            ),
                            "reasons": [],
                        }
                    ],
                    "command_templates": [
                        "python3 scripts/convert_stt_pipeline_to_official_bundle.py "
                        "--pipeline-manifest /tmp/product_path_pipeline_manifest.json "
                        "--output-root /tmp/product_path_bundle"
                    ],
                    "missing_reasons": [],
                    "rejection_reasons": [],
                    "metadata": {},
                    "next_actions": [],
                },
            ],
            "command_sequence": [
                {
                    "step_id": "fill_return_template_from_status",
                    "step_order": 1,
                    "title": "Fill operator evidence return template from submission status",
                    "step_state": "open",
                    "command_template_path": (
                        "/tmp/operator_evidence_return_template_fill_from_submission_status_command_template.txt"
                    ),
                    "input_paths": [
                        "/tmp/operator_evidence_return_template.json",
                        "/tmp/operator_evidence_submission_values_template.json",
                        "/tmp/official_comparison_operator_evidence_submission_checklist.json",
                    ],
                    "output_paths": [
                        "/tmp/operator_evidence_return_template.filled.json"
                    ],
                    "depends_on_step_ids": [],
                    "next_actions": [
                        "Run this command to build the status-filled operator evidence return template."
                    ],
                },
                {
                    "step_id": "run_return_workflow_from_status",
                    "step_order": 2,
                    "title": "Validate status-filled operator evidence return template",
                    "step_state": "blocked",
                    "command_template_path": (
                        "/tmp/operator_evidence_return_workflow_from_status_command_template.txt"
                    ),
                    "input_paths": [
                        "/tmp/operator_evidence_return_template.filled.json"
                    ],
                    "output_paths": [
                        "/tmp/official_comparison_operator_evidence_return_workflow_report.json"
                    ],
                    "depends_on_step_ids": ["fill_return_template_from_status"],
                    "next_actions": [
                        "Run after the filled return template exists and contains returned evidence paths."
                    ],
                },
                {
                    "step_id": "rerun_release_workflow_from_status_return",
                    "step_order": 3,
                    "title": "Rerun official release workflow with status return workflow output",
                    "step_state": "blocked",
                    "command_template_path": (
                        "/tmp/operator_evidence_release_workflow_from_status_command_template.txt"
                    ),
                    "input_paths": [
                        "/tmp/official_release_workflow_input.json",
                        "/tmp/official_comparison_operator_evidence_return_workflow_report.json",
                    ],
                    "output_paths": ["/tmp/official_release_workflow_report.json"],
                    "depends_on_step_ids": ["run_return_workflow_from_status"],
                    "next_actions": [
                        "Run after the status return workflow report has been generated."
                    ],
                },
            ],
            "next_actions": ["Fill blank path values."],
            "evidence_paths": [
                "/tmp/official_comparison_operator_evidence_submission_status_report.json",
                "/tmp/official_comparison_operator_evidence_submission_checklist.json",
                "/tmp/operator_evidence_return_template.json",
                "/tmp/operator_evidence_return_template_fill_from_submission_status_command_template.txt",
                "/tmp/operator_evidence_return_workflow_from_status_command_template.txt",
                "/tmp/operator_evidence_release_workflow_from_status_command_template.txt",
            ],
        }

    def operator_evidence_return_workflow_report(self):
        payload = {
            "manifest_type": "official_comparison_operator_evidence_return_workflow_report",
            "schema_version": 1,
            "return_state": "blocked_operator_evidence",
            "return_template_path": "/tmp/operator_evidence_return_template.json",
            "release_workflow_report_path": "/tmp/official_release_workflow_report.json",
            "operator_evidence_request_report_path": (
                "/tmp/official_comparison_operator_evidence_request_report.json"
            ),
            "operator_evidence_return_guide_markdown_path": (
                "/tmp/operator_evidence_return_guide.md"
            ),
            "operator_evidence_return_guide_html_path": (
                "/tmp/operator_evidence_return_guide.html"
            ),
            "return_template_fill_command_template_path": (
                "/tmp/operator_evidence_return_template_fill_command_template.txt"
            ),
            "return_workflow_command_template_path": (
                "/tmp/operator_evidence_return_workflow_command_template.txt"
            ),
            "intake_command_template_path": "/tmp/operator_evidence_intake_command_template.txt",
            "release_workflow_command_template_path": (
                "/tmp/operator_evidence_release_workflow_command_template.txt"
            ),
            "command_template_paths": [
                "/tmp/operator_evidence_return_template_fill_command_template.txt",
                "/tmp/operator_evidence_return_workflow_command_template.txt",
                "/tmp/operator_evidence_intake_command_template.txt",
                "/tmp/operator_evidence_release_workflow_command_template.txt",
            ],
            "target_reference_version": "fixture-reference-v1",
            "reference_review_workflow_report_path": None,
            "run_bundle_manifest_paths": ["/tmp/engine_run_bundle_manifest.json"],
            "operator_handoff_report_path": "/tmp/official_comparison_operator_handoff_report.json",
            "operator_evidence_intake_report_path": (
                "/tmp/official_comparison_operator_evidence_intake_report.json"
            ),
            "preflight_resume_plan_path": "/tmp/official_comparison_preflight_resume_plan.json",
            "operator_evidence_intake_state": "blocked_missing_operator_evidence",
            "operator_evidence_ready_to_rerun_preflight": False,
            "operator_evidence_items": [
                {
                    "task_id": "product_path_official_run",
                    "state": "accepted",
                    "evidence_paths": ["/tmp/engine_run_bundle_manifest.json"],
                    "reasons": ["real product-path runs are ready"],
                    "next_action": "Product-path evidence accepted.",
                },
                {
                    "task_id": "reference_review",
                    "state": "missing",
                    "evidence_paths": ["/tmp/reference_review_pack.md"],
                    "reasons": ["reference review workflow report was not provided"],
                    "next_action": "Return an applied reference review workflow report.",
                },
                {
                    "task_id": "align_engine_reference_version",
                    "state": "rejected",
                    "evidence_paths": ["/tmp/engine_reference_alignment_plan.json"],
                    "reasons": ["missing target-reference run bundle entry"],
                    "next_action": "Return target-reference run bundles.",
                },
                {
                    "task_id": "align_engine_comparability_contract",
                    "state": "rejected",
                    "evidence_paths": ["/tmp/engine_comparability_rerun_plan.json"],
                    "reasons": ["missing comparable rerun bundle entry"],
                    "next_action": "Return comparable rerun bundles.",
                },
            ],
            "operator_evidence_task_results": [
                {
                    "task_id": "product_path_official_run",
                    "title": "Run product path official run",
                    "state": "accepted",
                    "request_state": "requested",
                    "adoption_item_ids": ["product_path_only_default_decision"],
                    "return_fields": ["target_reference_version", "run_bundle_manifest_paths"],
                    "provided_return_fields": [
                        "target_reference_version",
                        "run_bundle_manifest_paths",
                    ],
                    "missing_return_fields": [],
                    "evidence_to_return": ["real product-path pipeline_manifest.json"],
                    "acceptance_criteria": ["runner_contract.dry_run=false"],
                    "reasons": ["real product-path runs are ready"],
                    "next_action": "Product-path evidence accepted.",
                    "source_paths": ["/tmp/product_path_official_run_plan.json"],
                    "evidence_paths": ["/tmp/engine_run_bundle_manifest.json"],
                    "command_template_paths": ["/tmp/operator_evidence_intake_command_template.txt"],
                },
                {
                    "task_id": "reference_review",
                    "title": "Complete reference review",
                    "state": "missing",
                    "request_state": "requested",
                    "adoption_item_ids": ["reference_reviewed_gold"],
                    "return_fields": ["reference_review_workflow_report_path"],
                    "provided_return_fields": [],
                    "missing_return_fields": ["reference_review_workflow_report_path"],
                    "evidence_to_return": ["reference_review_batch_workflow_report"],
                    "acceptance_criteria": [
                        "reference_review_batch_workflow_report.workflow_state=applied"
                    ],
                    "reasons": ["reference review workflow report was not provided"],
                    "next_action": "Return an applied reference review workflow report.",
                    "source_paths": ["/tmp/reference_review_pack.md"],
                    "evidence_paths": ["/tmp/reference_review_pack.md"],
                    "command_template_paths": ["/tmp/operator_evidence_intake_command_template.txt"],
                },
                {
                    "task_id": "align_engine_reference_version",
                    "title": "Align engine reference version",
                    "state": "rejected",
                    "request_state": "requested",
                    "adoption_item_ids": ["release_gate_ready_for_default"],
                    "return_fields": ["target_reference_version", "run_bundle_manifest_paths"],
                    "provided_return_fields": [
                        "target_reference_version",
                        "run_bundle_manifest_paths",
                    ],
                    "missing_return_fields": [],
                    "evidence_to_return": ["target-reference run bundles"],
                    "acceptance_criteria": ["returned run bundles use the target reference_version"],
                    "reasons": ["missing target-reference run bundle entry"],
                    "next_action": "Return target-reference run bundles.",
                    "source_paths": ["/tmp/engine_reference_alignment_plan.json"],
                    "evidence_paths": ["/tmp/engine_reference_alignment_plan.json"],
                    "command_template_paths": ["/tmp/operator_evidence_intake_command_template.txt"],
                },
                {
                    "task_id": "align_engine_comparability_contract",
                    "title": "Align engine comparability contract",
                    "state": "rejected",
                    "request_state": "requested",
                    "adoption_item_ids": ["release_gate_ready_for_default"],
                    "return_fields": ["target_reference_version", "run_bundle_manifest_paths"],
                    "provided_return_fields": [
                        "target_reference_version",
                        "run_bundle_manifest_paths",
                    ],
                    "missing_return_fields": [],
                    "evidence_to_return": ["comparable rerun bundles"],
                    "acceptance_criteria": [
                        "engine_comparability_report.comparability_state=ready_for_official_comparison"
                    ],
                    "reasons": ["missing comparable rerun bundle entry"],
                    "next_action": "Return comparable rerun bundles.",
                    "source_paths": ["/tmp/engine_comparability_rerun_plan.json"],
                    "evidence_paths": ["/tmp/engine_comparability_rerun_plan.json"],
                    "command_template_paths": ["/tmp/operator_evidence_intake_command_template.txt"],
                },
            ],
            "return_field_statuses": [
                {
                    "field": "reference_review_workflow_report_path",
                    "value_type": "path",
                    "allow_multiple": False,
                    "expected_manifest_types": ["reference_review_batch_workflow_report"],
                    "expected_value": "",
                    "resolved_expected_value": "",
                    "value_contract_state": "missing",
                    "value_contract_errors": [],
                    "provided": False,
                    "value_count": 0,
                    "values": [],
                    "field_resolution_state": "missing",
                    "task_ids": ["reference_review"],
                    "requested_task_ids": ["reference_review"],
                    "provided_task_ids": [],
                    "missing_task_ids": ["reference_review"],
                    "accepted_evidence_task_ids": [],
                    "missing_evidence_task_ids": ["reference_review"],
                    "rejected_evidence_task_ids": [],
                    "not_needed_evidence_task_ids": [],
                    "blocked_evidence_task_ids": ["reference_review"],
                    "adoption_item_ids": ["reference_reviewed_gold"],
                    "source_paths": ["/tmp/reference_review_pack.md"],
                    "evidence_to_return": ["reference_review_batch_workflow_report"],
                    "acceptance_criteria": [
                        "reference_review_batch_workflow_report.workflow_state=applied"
                    ],
                    "next_actions": ["Return an applied reference review workflow report."],
                    "command_template_paths": ["/tmp/operator_evidence_intake_command_template.txt"],
                },
                {
                    "field": "run_bundle_manifest_paths",
                    "value_type": "path_list",
                    "allow_multiple": True,
                    "expected_manifest_types": ["engine_run_bundle_manifest"],
                    "expected_value": "",
                    "resolved_expected_value": "",
                    "value_contract_state": "valid",
                    "value_contract_errors": [],
                    "provided": True,
                    "value_count": 1,
                    "values": ["/tmp/engine_run_bundle_manifest.json"],
                    "field_resolution_state": "partially_accepted",
                    "task_ids": [
                        "product_path_official_run",
                        "align_engine_reference_version",
                        "align_engine_comparability_contract",
                    ],
                    "requested_task_ids": [
                        "product_path_official_run",
                        "align_engine_reference_version",
                        "align_engine_comparability_contract",
                    ],
                    "provided_task_ids": [
                        "product_path_official_run",
                        "align_engine_reference_version",
                        "align_engine_comparability_contract",
                    ],
                    "missing_task_ids": [],
                    "accepted_evidence_task_ids": ["product_path_official_run"],
                    "missing_evidence_task_ids": [],
                    "rejected_evidence_task_ids": [
                        "align_engine_reference_version",
                        "align_engine_comparability_contract",
                    ],
                    "not_needed_evidence_task_ids": [],
                    "blocked_evidence_task_ids": [
                        "align_engine_reference_version",
                        "align_engine_comparability_contract",
                    ],
                    "adoption_item_ids": [
                        "product_path_only_default_decision",
                        "release_gate_ready_for_default",
                    ],
                    "source_paths": [
                        "/tmp/product_path_official_run_plan.json",
                        "/tmp/engine_reference_alignment_plan.json",
                        "/tmp/engine_comparability_rerun_plan.json",
                    ],
                    "evidence_to_return": [
                        "real product-path pipeline_manifest.json",
                        "target-reference run bundles",
                        "comparable rerun bundles",
                    ],
                    "acceptance_criteria": [
                        "runner_contract.dry_run=false",
                        "returned run bundles use the target reference_version",
                        "engine_comparability_report.comparability_state=ready_for_official_comparison",
                    ],
                    "next_actions": [
                        "Product-path evidence accepted.",
                        "Return target-reference run bundles.",
                        "Return comparable rerun bundles.",
                    ],
                    "command_template_paths": ["/tmp/operator_evidence_intake_command_template.txt"],
                },
                {
                    "field": "target_reference_version",
                    "value_type": "string",
                    "allow_multiple": False,
                    "expected_manifest_types": [],
                    "expected_value": "target_reference_version",
                    "resolved_expected_value": "fixture-reference-v1",
                    "value_contract_state": "valid",
                    "value_contract_errors": [],
                    "provided": True,
                    "value_count": 1,
                    "values": ["fixture-reference-v1"],
                    "field_resolution_state": "partially_accepted",
                    "task_ids": [
                        "product_path_official_run",
                        "align_engine_reference_version",
                        "align_engine_comparability_contract",
                    ],
                    "requested_task_ids": [
                        "product_path_official_run",
                        "align_engine_reference_version",
                        "align_engine_comparability_contract",
                    ],
                    "provided_task_ids": [
                        "product_path_official_run",
                        "align_engine_reference_version",
                        "align_engine_comparability_contract",
                    ],
                    "missing_task_ids": [],
                    "accepted_evidence_task_ids": ["product_path_official_run"],
                    "missing_evidence_task_ids": [],
                    "rejected_evidence_task_ids": [
                        "align_engine_reference_version",
                        "align_engine_comparability_contract",
                    ],
                    "not_needed_evidence_task_ids": [],
                    "blocked_evidence_task_ids": [
                        "align_engine_reference_version",
                        "align_engine_comparability_contract",
                    ],
                    "adoption_item_ids": [
                        "product_path_only_default_decision",
                        "release_gate_ready_for_default",
                    ],
                    "source_paths": [
                        "/tmp/product_path_official_run_plan.json",
                        "/tmp/engine_reference_alignment_plan.json",
                        "/tmp/engine_comparability_rerun_plan.json",
                    ],
                    "evidence_to_return": [
                        "real product-path pipeline_manifest.json",
                        "target-reference run bundles",
                        "comparable rerun bundles",
                    ],
                    "acceptance_criteria": [
                        "runner_contract.dry_run=false",
                        "returned run bundles use the target reference_version",
                        "engine_comparability_report.comparability_state=ready_for_official_comparison",
                    ],
                    "next_actions": [
                        "Product-path evidence accepted.",
                        "Return target-reference run bundles.",
                        "Return comparable rerun bundles.",
                    ],
                    "command_template_paths": ["/tmp/operator_evidence_intake_command_template.txt"],
                },
            ],
            "operator_evidence_accepted_item_count": 1,
            "operator_evidence_missing_item_count": 1,
            "operator_evidence_rejected_item_count": 2,
            "preflight_resume_plan_state": "blocked_operator_evidence",
            "preflight_resume_ready_to_rerun": False,
            "preflight_rerun_command": "",
            "blocking_reasons": ["operator evidence intake is not ready_to_rerun_preflight"],
            "next_actions": ["Return accepted operator evidence before rerunning preflight."],
            "evidence_paths": ["/tmp/official_comparison_operator_evidence_intake_report.json"],
            "markdown_report_path": (
                "/tmp/official_comparison_operator_evidence_return_workflow_report.md"
            ),
            "html_report_path": (
                "/tmp/official_comparison_operator_evidence_return_workflow_report.html"
            ),
        }
        payload["return_blocker_summary"] = (
            validator.expected_operator_evidence_return_blocker_summary(payload)
        )
        return payload

    def release_workflow_report_with_return_context(self):
        payload = self.release_workflow_report()
        return_payload = self.operator_evidence_return_workflow_report()
        payload.update({
            "operator_evidence_return_workflow_report_path": (
                "/tmp/official_comparison_operator_evidence_return_workflow_report.json"
            ),
            "operator_evidence_return_state": return_payload["return_state"],
            "operator_evidence_return_target_reference_version": (
                return_payload["target_reference_version"]
            ),
            "operator_evidence_return_intake_state": (
                return_payload["operator_evidence_intake_state"]
            ),
            "operator_evidence_return_accepted_item_count": (
                return_payload["operator_evidence_accepted_item_count"]
            ),
            "operator_evidence_return_missing_item_count": (
                return_payload["operator_evidence_missing_item_count"]
            ),
            "operator_evidence_return_rejected_item_count": (
                return_payload["operator_evidence_rejected_item_count"]
            ),
            "operator_evidence_return_preflight_resume_plan_state": (
                return_payload["preflight_resume_plan_state"]
            ),
            "operator_evidence_return_ready_to_rerun_preflight": (
                return_payload["preflight_resume_ready_to_rerun"]
            ),
            "operator_evidence_return_field_statuses": copy.deepcopy(
                return_payload["return_field_statuses"]
            ),
            "operator_evidence_return_submission_slot_values": [
                {
                    "slot_id": "product_path_bundle_speech_analyzer",
                    "return_field": "run_bundle_manifest_paths",
                    "path": "/tmp/engine_run_bundle_manifest.json",
                },
            ],
            "operator_evidence_submission_slot_count": 3,
            "operator_evidence_submitted_submission_slot_count": 1,
            "operator_evidence_missing_submission_slot_count": 1,
            "operator_evidence_rejected_submission_slot_count": 1,
            "operator_evidence_not_needed_submission_slot_count": 0,
            "operator_evidence_submitted_submission_slot_ids": [
                "product_path_bundle_speech_analyzer",
            ],
            "operator_evidence_missing_submission_slot_ids": [
                "reference_review_workflow_report",
            ],
            "operator_evidence_rejected_submission_slot_ids": [
                "target_reference_bundle_speech_analyzer_offline_final",
            ],
            "operator_evidence_not_needed_submission_slot_ids": [],
            "operator_evidence_submission_values_filled_path_count": 2,
            "operator_evidence_submission_values_blank_path_count": 1,
            "operator_evidence_submission_values_minimum_required_filled_path_count": 1,
            "operator_evidence_submission_values_fill_command_readiness_state": (
                "blocked_invalid_submission_values"
            ),
            "operator_evidence_submission_values_fill_command_blocking_reasons": [
                "Fix rejected slot_values[].path values before running the status fill command.",
            ],
            "operator_evidence_submission_status_state": "blocked_invalid_submissions",
            "operator_evidence_submission_blocking_reasons": [
                "Fix rejected slot_values[].path values before running the status fill command.",
            ],
            "operator_evidence_blocking_submission_slots": [
                {
                    "slot_id": "reference_review_workflow_report",
                    "slot_type": "reference_review_workflow_report",
                    "slot_status": "missing",
                    "task_id": "reference_review",
                    "title": "Complete reference review",
                    "return_field": "reference_review_workflow_report_path",
                    "expected_manifest_types": ["reference_review_batch_workflow_report"],
                    "expected_submission_path": (
                        "/tmp/reference_review_workflow/"
                        "reference_review_batch_workflow_report.json"
                    ),
                    "expected_submission_path_state": "known_from_command_template",
                    "expected_submission_path_file_state": "missing",
                    "expected_submission_path_note": (
                        "After the submission command succeeds, copy this path into "
                        "slot_values[].path."
                    ),
                    "engine_id": "",
                    "benchmark_kind": "",
                    "sample_set": "reference_review_batch",
                    "current_reference_version": "fixture-reference-v1",
                    "target_reference_version": "fixture-reference-v1",
                    "evidence_to_collect": ["reference_review_batch_workflow_report"],
                    "acceptance_criteria": [
                        "reference_review_batch_workflow_report.workflow_state=applied"
                    ],
                    "source_paths": ["/tmp/reference_review_pack.md"],
                    "source_artifact_hint_paths": [],
                    "source_candidate_diagnostics": [
                        {
                            "path": "/tmp/reference_review_pack.md",
                            "candidate_state": "not_submission_manifest",
                            "manifest_type": "",
                            "engine_id": "",
                            "benchmark_kind": "",
                            "reference_version": "fixture-reference-v1",
                            "benchmark_reference_version": "",
                            "product_path_state": "",
                            "runner_contract_dry_run_state": "",
                            "benchmark_run_manifest_path": "",
                            "reasons": [
                                "manifest_type must be "
                                "reference_review_batch_workflow_report"
                            ],
                        }
                    ],
                    "command_template_paths": [
                        "/tmp/operator_evidence_return_template_fill_command_template.txt"
                    ],
                    "command_templates": [
                        "python3 scripts/run_stt_reference_review_batch_workflow.py "
                        "--review-decisions /tmp/reference_review_decisions.csv "
                        "--output-root /tmp/reference_review_workflow"
                    ],
                    "return_task_state": "missing",
                    "return_task_reasons": ["reference review workflow report was not provided"],
                    "return_field_resolution_state": "missing",
                    "return_field_value_contract_state": "missing",
                    "return_field_value_contract_errors": [],
                    "return_field_blocked_evidence_task_ids": ["reference_review"],
                    "matched_evidence_paths": [],
                    "rejection_reasons": [],
                    "missing_reasons": ["reference review workflow report was not provided"],
                    "matched_evidence": [],
                    "next_actions": ["Return an applied reference review workflow report."],
                    "metadata": {},
                },
                {
                    "slot_id": "target_reference_bundle_speech_analyzer_offline_final",
                    "slot_type": "target_reference_engine_bundle",
                    "slot_status": "rejected",
                    "task_id": "align_engine_reference_version",
                    "title": "Align speech analyzer reference version",
                    "return_field": "run_bundle_manifest_paths",
                    "expected_manifest_types": ["engine_run_bundle_manifest"],
                    "expected_submission_path": (
                        "/tmp/target_reference_bundle/engine_run_bundle_manifest.json"
                    ),
                    "expected_submission_path_state": "known_from_command_template",
                    "expected_submission_path_file_state": "missing",
                    "expected_submission_path_note": (
                        "After the submission command succeeds, copy this path into "
                        "slot_values[].path."
                    ),
                    "engine_id": "speech_analyzer",
                    "benchmark_kind": "offline_final",
                    "sample_set": "meeting-all7",
                    "current_reference_version": "seed-reference-v1",
                    "target_reference_version": "fixture-reference-v1",
                    "evidence_to_collect": ["engine_run_bundle_manifest"],
                    "acceptance_criteria": [
                        "benchmark_run_manifest.reference_version must equal fixture-reference-v1"
                    ],
                    "source_paths": ["/tmp/engine_reference_alignment_plan.json"],
                    "source_artifact_hint_paths": [],
                    "source_candidate_diagnostics": [
                        {
                            "path": "/tmp/engine_run_bundle_manifest.json",
                            "candidate_state": "rejected_candidate",
                            "manifest_type": "engine_run_bundle_manifest",
                            "engine_id": "speech_analyzer",
                            "benchmark_kind": "offline_final",
                            "reference_version": "seed-reference-v1",
                            "benchmark_reference_version": "seed-reference-v1",
                            "product_path_state": "false",
                            "runner_contract_dry_run_state": "false",
                            "benchmark_run_manifest_path": (
                                "/tmp/benchmark_run_manifest.json"
                            ),
                            "reasons": [
                                "benchmark_run_manifest.reference_version must "
                                "equal fixture-reference-v1"
                            ],
                        }
                    ],
                    "command_template_paths": [
                        "/tmp/operator_evidence_return_template_fill_command_template.txt"
                    ],
                    "command_templates": [
                        "python3 scripts/convert_stt_pipeline_to_official_bundle.py "
                        "--pipeline-manifest /tmp/target_reference_pipeline_manifest.json "
                        "--output-root /tmp/target_reference_bundle"
                    ],
                    "return_task_state": "rejected",
                    "return_task_reasons": ["missing target-reference run bundle entry"],
                    "return_field_resolution_state": "partially_accepted",
                    "return_field_value_contract_state": "valid",
                    "return_field_value_contract_errors": [],
                    "return_field_blocked_evidence_task_ids": [
                        "align_engine_reference_version",
                    ],
                    "matched_evidence_paths": ["/tmp/engine_run_bundle_manifest.json"],
                    "rejection_reasons": ["missing target-reference run bundle entry"],
                    "missing_reasons": [],
                    "matched_evidence": [],
                    "next_actions": ["Return target-reference run bundles."],
                    "metadata": {},
                },
            ],
        })
        payload["next_actions"] = list(
            dict.fromkeys(
                payload["next_actions"]
                + payload["operator_evidence_submission_values_fill_command_blocking_reasons"]
            )
        )
        payload["operator_evidence_return_blocker_summary"] = (
            validator.expected_release_return_blocker_summary(payload)
        )
        return payload

    def release_workflow_operator_task(self, task_id, evidence_state):
        return {
            "task_id": task_id,
            "title": task_id.replace("_", " "),
            "execution_status": "waiting_for_manual_input",
            "evidence_state": evidence_state,
            "operator_action": f"Provide evidence for {task_id}.",
            "next_action": f"Return accepted evidence for {task_id}.",
            "reasons": ["missing evidence"],
            "evidence_to_return": ["accepted operator evidence"],
            "source_paths": [f"/tmp/{task_id}.json"],
            "evidence_paths": [f"/tmp/{task_id}.json"],
        }

    def release_workflow_adoption_blocker(
        self,
        item_id,
        remediation_task_ids,
        return_fields,
    ):
        return {
            "item_id": item_id,
            "title": item_id.replace("_", " "),
            "state": "blocked",
            "remediation_task_ids": remediation_task_ids,
            "return_fields": return_fields,
            "evidence_to_return": ["accepted operator evidence"],
            "acceptance_criteria": [f"{item_id}=passed"],
            "command_template_paths": ["/tmp/operator_evidence_return_workflow_command_template.txt"],
            "reasons": ["missing evidence"],
            "next_actions": ["Return accepted operator evidence."],
        }

    def test_minimal_decision_fixture_is_valid(self):
        errors = validator.validate_manifest(self.valid_decision_manifest())

        self.assertEqual(errors, [])

    def test_minimal_benchmark_run_fixture_is_valid(self):
        path = ROOT / "fixtures/minimal_benchmark_run_manifest.json"
        payload = json.loads(path.read_text(encoding="utf-8"))

        self.assertEqual(validator.validate_manifest(payload), [])

    def test_benchmark_run_accepts_missing_repeat_index(self):
        path = ROOT / "fixtures/minimal_benchmark_run_manifest.json"
        payload = json.loads(path.read_text(encoding="utf-8"))

        self.assertNotIn("repeat_index", payload)
        self.assertEqual(validator.validate_manifest(payload), [])

    def test_benchmark_run_accepts_repeat_index(self):
        path = ROOT / "fixtures/minimal_benchmark_run_manifest.json"
        payload = json.loads(path.read_text(encoding="utf-8"))
        payload["repeat_index"] = 0

        self.assertEqual(validator.validate_manifest(payload), [])

    def test_benchmark_run_rejects_non_integer_repeat_index(self):
        path = ROOT / "fixtures/minimal_benchmark_run_manifest.json"
        payload = json.loads(path.read_text(encoding="utf-8"))
        payload["repeat_index"] = "0"

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "benchmark_run_manifest.repeat_index must be a non-negative integer",
            errors,
        )

    def test_benchmark_run_rejects_negative_repeat_index(self):
        path = ROOT / "fixtures/minimal_benchmark_run_manifest.json"
        payload = json.loads(path.read_text(encoding="utf-8"))
        payload["repeat_index"] = -1

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "benchmark_run_manifest.repeat_index must be a non-negative integer",
            errors,
        )

    def test_minimal_engine_fixture_is_valid(self):
        path = ROOT / "fixtures/minimal_engine_manifest.json"
        payload = json.loads(path.read_text(encoding="utf-8"))

        self.assertEqual(validator.validate_manifest(payload), [])

    def test_official_operator_evidence_request_report_manifest_is_valid(self):
        self.assertEqual(
            validator.validate_manifest(self.operator_evidence_request_report()),
            [],
        )

    def test_official_operator_evidence_request_report_rejects_mismatched_field_requirement(self):
        payload = self.operator_evidence_request_report()
        payload["return_field_requirements"][0]["task_ids"] = ["product_path_official_run"]

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_request_report."
            "return_field_requirements must match requested request return_fields",
            errors,
        )

    def test_official_operator_evidence_request_report_rejects_mismatched_adoption_items(self):
        payload = self.operator_evidence_request_report()
        payload["return_field_requirements"][0]["adoption_item_ids"] = [
            "product_path_only_default_decision"
        ]

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_request_report."
            "return_field_requirements adoption_item_ids must match requested requests",
            errors,
        )

    def test_official_operator_evidence_request_report_rejects_bad_field_value_type(self):
        payload = self.operator_evidence_request_report()
        payload["return_field_requirements"][0]["value_type"] = "unknown_type"
        payload["return_field_requirements"][0]["resolved_expected_value"] = 7

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_request_report."
            "return_field_requirements[0].value_type is invalid: 'unknown_type'",
            errors,
        )
        self.assertIn(
            "official_comparison_operator_evidence_request_report."
            "return_field_requirements[0].resolved_expected_value must be str",
            errors,
        )

    def test_official_operator_evidence_request_report_rejects_mismatched_task_requirement(self):
        payload = self.operator_evidence_request_report()
        payload["task_return_requirements"][0]["return_fields"] = [
            "run_bundle_manifest_paths"
        ]

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_request_report."
            "task_return_requirements must match requested requests",
            errors,
        )

    def test_official_operator_evidence_return_template_manifest_is_valid(self):
        self.assertEqual(
            validator.validate_manifest(self.operator_evidence_return_template()),
            [],
        )

    def test_official_operator_evidence_return_template_accepts_submission_slot_values(self):
        payload = self.operator_evidence_return_template()
        payload["reference_review_workflow_report_path"] = "/tmp/review_report.json"
        payload["run_bundle_manifest_paths"] = ["/tmp/engine_run_bundle_manifest.json"]
        payload["submission_slot_values"] = [
            {
                "slot_id": "reference_review_workflow_report",
                "return_field": "reference_review_workflow_report_path",
                "path": "/tmp/review_report.json",
            },
            {
                "slot_id": "target_reference_bundle_whisper_accurate_offline_final",
                "return_field": "run_bundle_manifest_paths",
                "path": "/tmp/engine_run_bundle_manifest.json",
            },
        ]

        self.assertEqual(validator.validate_manifest(payload), [])

    def test_official_operator_evidence_return_template_accepts_autofill_diagnostics(self):
        payload = self.operator_evidence_return_template()
        payload["submission_slot_autofill_diagnostics"] = [
            {
                "slot_id": "reference_review_workflow_report",
                "task_id": "reference_review",
                "return_field": "reference_review_workflow_report_path",
                "expected_submission_path": "/tmp/reference_review_report.json",
                "autofill_state": "skipped_invalid_expected_submission_path",
                "reason": "workflow_state must be applied",
            }
        ]

        self.assertEqual(validator.validate_manifest(payload), [])

    def test_official_operator_evidence_return_template_rejects_bad_autofill_state(self):
        payload = self.operator_evidence_return_template()
        payload["submission_slot_autofill_diagnostics"] = [
            {
                "slot_id": "reference_review_workflow_report",
                "return_field": "reference_review_workflow_report_path",
                "expected_submission_path": "/tmp/reference_review_report.json",
                "autofill_state": "accepted_invalid_expected_submission_path",
                "reason": "workflow_state must be applied",
            }
        ]

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_return_template."
            "submission_slot_autofill_diagnostics[0].autofill_state is invalid: "
            "'accepted_invalid_expected_submission_path'",
            errors,
        )

    def test_official_operator_evidence_return_template_rejects_slot_value_drift(self):
        payload = self.operator_evidence_return_template()
        payload["run_bundle_manifest_paths"] = ["/tmp/engine_run_bundle_manifest.json"]
        payload["submission_slot_values"] = [
            {
                "slot_id": "target_reference_bundle_whisper_accurate_offline_final",
                "return_field": "run_bundle_manifest_paths",
                "path": "/tmp/other_engine_run_bundle_manifest.json",
            },
        ]

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_return_template."
            "submission_slot_values run bundle path must be in run_bundle_manifest_paths",
            errors,
        )

    def test_official_operator_evidence_return_template_rejects_duplicate_submission_slot_values(self):
        payload = self.operator_evidence_return_template()
        payload["run_bundle_manifest_paths"] = ["/tmp/engine_run_bundle_manifest.json"]
        payload["submission_slot_values"] = [
            {
                "slot_id": "product_path_bundle_speech_analyzer",
                "return_field": "run_bundle_manifest_paths",
                "path": "/tmp/engine_run_bundle_manifest.json",
            },
            {
                "slot_id": "product_path_bundle_speech_analyzer",
                "return_field": "run_bundle_manifest_paths",
                "path": "/tmp/engine_run_bundle_manifest.json",
            },
        ]

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_return_template."
            "submission_slot_values[1].slot_id must be unique: "
            "product_path_bundle_speech_analyzer",
            errors,
        )

    def test_official_operator_evidence_return_template_rejects_bad_task_requirement(self):
        payload = self.operator_evidence_return_template()
        payload["task_return_requirements"][0]["return_fields"] = []

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_return_template."
            "task_return_requirements[0].requested item requires return_fields",
            errors,
        )

    def test_official_operator_evidence_return_template_rejects_missing_acceptance_criteria(self):
        payload = self.operator_evidence_return_template()
        payload["task_return_requirements"][0]["acceptance_criteria"] = []

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_return_template."
            "task_return_requirements[0].requested item requires acceptance_criteria",
            errors,
        )

    def test_official_operator_evidence_return_template_rejects_mismatched_field_requirement(self):
        payload = self.operator_evidence_return_template()
        payload["return_field_requirements"][0]["task_ids"] = ["product_path_official_run"]

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_return_template."
            "return_field_requirements must match task_return_requirements return_fields",
            errors,
        )

    def test_official_operator_evidence_return_template_rejects_mismatched_adoption_items(self):
        payload = self.operator_evidence_return_template()
        payload["return_field_requirements"][0]["adoption_item_ids"] = [
            "product_path_only_default_decision"
        ]

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_return_template."
            "return_field_requirements adoption_item_ids must match task_return_requirements",
            errors,
        )

    def test_official_operator_evidence_submission_values_template_manifest_is_valid(self):
        self.assertEqual(
            validator.validate_manifest(self.operator_evidence_submission_values_template()),
            [],
        )

    def test_official_operator_evidence_submission_values_template_rejects_bad_count(self):
        payload = self.operator_evidence_submission_values_template()
        payload["slot_value_count"] = 0
        payload["filled_path_count"] = 0

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_submission_values_template."
            "slot_value_count must equal slot_values length",
            errors,
        )
        self.assertIn(
            "official_comparison_operator_evidence_submission_values_template."
            "filled_path_count must equal filled slot_values paths",
            errors,
        )

    def test_official_operator_evidence_submission_values_template_rejects_expected_path_summary_drift(self):
        payload = self.operator_evidence_submission_values_template()
        payload["expected_submission_path_missing_count"] = 1
        payload["expected_submission_path_missing_slot_ids"] = [
            "reference_review_workflow_report"
        ]

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_submission_values_template."
            "expected_submission_path_missing_count must match "
            "expected_submission_path_file_state",
            errors,
        )
        self.assertIn(
            "official_comparison_operator_evidence_submission_values_template."
            "expected_submission_path_missing_slot_ids must match "
            "expected_submission_path_file_state",
            errors,
        )

    def test_official_operator_evidence_submission_values_template_rejects_bad_fill_readiness(self):
        payload = self.operator_evidence_submission_values_template()
        payload["slot_values"][1]["path"] = ""
        payload["slot_values"][1]["slot_status"] = "missing"
        payload["slot_values"][1]["missing_reasons"] = ["path missing"]
        payload["filled_path_count"] = 0
        payload["blank_path_count"] = 2
        payload["fill_command_readiness_state"] = "ready_to_fill_return_template"
        payload["command_sequence"][0]["step_state"] = "blocked"

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_submission_values_template."
            "fill_command_readiness_state must be blocked_empty_submission_values",
            errors,
        )

    def test_official_operator_evidence_submission_values_template_rejects_command_sequence_drift(self):
        payload = self.operator_evidence_submission_values_template()
        payload["command_sequence"][1]["command_template_path"] = "/tmp/stale.txt"

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_submission_values_template."
            "command_sequence.run_return_workflow_from_status."
            "command_template_path must match "
            "return_workflow_from_status_command_template_path",
            errors,
        )

    def test_official_operator_evidence_submission_values_template_rejects_ready_state_with_rejected_path(self):
        payload = self.operator_evidence_submission_values_template()
        payload["slot_values"][1]["slot_status"] = "rejected"
        payload["slot_values"][1]["rejection_reasons"] = ["stale reference"]
        payload["fill_command_readiness_state"] = "ready_to_fill_return_template"

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_submission_values_template."
            "fill_command_readiness_state must be blocked_invalid_submission_values",
            errors,
        )

    def test_official_operator_evidence_submission_values_template_allows_blank_rejected_slot_path(self):
        payload = self.operator_evidence_submission_values_template()
        payload["slot_values"][0]["slot_status"] = "rejected"
        payload["slot_values"][0]["missing_reasons"] = []
        payload["slot_values"][0]["rejection_reasons"] = [
            "stale reference path was cleared"
        ]
        payload["submission_action_groups"][0]["group_status"] = (
            "blocked_invalid_submissions"
        )
        payload["submission_action_groups"][0]["missing_slot_count"] = 0
        payload["submission_action_groups"][0]["rejected_slot_count"] = 1
        payload["fill_command_readiness_state"] = "ready_to_fill_return_template"
        payload["fill_command_blocking_reasons"] = []
        payload["submission_completion_state"] = "blocked_invalid_submissions"
        payload["full_submission_ready"] = False
        payload["remaining_required_slot_count"] = 1
        payload["remaining_required_slot_ids"] = ["reference_review_workflow_report"]
        payload["submitted_required_slot_ids"] = ["product_path_bundle_speech_analyzer"]
        payload["missing_required_slot_ids"] = []
        payload["rejected_required_slot_ids"] = ["reference_review_workflow_report"]

        errors = validator.validate_manifest(payload)

        self.assertEqual(errors, [])

    def test_official_operator_evidence_submission_values_template_requires_blocking_reason(self):
        payload = self.operator_evidence_submission_values_template()
        payload["slot_values"][1]["path"] = ""
        payload["slot_values"][1]["slot_status"] = "missing"
        payload["slot_values"][1]["missing_reasons"] = ["path missing"]
        payload["filled_path_count"] = 0
        payload["blank_path_count"] = 2
        payload["fill_command_readiness_state"] = "blocked_empty_submission_values"
        payload["fill_command_blocking_reasons"] = []

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_submission_values_template."
            "blocked_empty_submission_values requires fill_command_blocking_reasons",
            errors,
        )

    def test_official_operator_evidence_submission_values_template_requires_invalid_blocking_reason(self):
        payload = self.operator_evidence_submission_values_template()
        payload["slot_values"][1]["slot_status"] = "rejected"
        payload["slot_values"][1]["rejection_reasons"] = ["stale reference"]
        payload["fill_command_readiness_state"] = "blocked_invalid_submission_values"
        payload["fill_command_blocking_reasons"] = []

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_submission_values_template."
            "blocked_invalid_submission_values requires fill_command_blocking_reasons",
            errors,
        )

    def test_official_operator_evidence_submission_values_template_rejects_missing_contract(self):
        payload = self.operator_evidence_submission_values_template()
        payload["slot_values"][0]["expected_manifest_types"] = []
        payload["slot_values"][0]["evidence_to_collect"] = []
        payload["slot_values"][0]["acceptance_criteria"] = []

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_submission_values_template."
            "slot_values[0].missing slot requires expected_manifest_types",
            errors,
        )
        self.assertIn(
            "official_comparison_operator_evidence_submission_values_template."
            "slot_values[0].missing slot requires evidence_to_collect",
            errors,
        )
        self.assertIn(
            "official_comparison_operator_evidence_submission_values_template."
            "slot_values[0].missing slot requires acceptance_criteria",
            errors,
        )

    def test_official_operator_evidence_submission_values_template_rejects_list_literal_sample_set(self):
        payload = self.operator_evidence_submission_values_template()
        payload["slot_values"][1]["sample_set"] = "['a', 'b']"

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_submission_values_template."
            "slot_values[1].sample_set must not use list literal formatting",
            errors,
        )

    def test_official_operator_evidence_submission_values_template_rejects_path_value_hint_drift(self):
        payload = self.operator_evidence_submission_values_template()
        payload["slot_values"][0]["path_value_hint"] = (
            "Path to an engine_run_bundle_manifest JSON file."
        )
        payload["slot_values"][1]["path_value_hint"] = (
            "Path to a reference_review_batch_workflow_report JSON file."
        )

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_submission_values_template."
            "slot_values[0].path_value_hint must be "
            "'Path to a reference_review_batch_workflow_report JSON file.'",
            errors,
        )
        self.assertIn(
            "official_comparison_operator_evidence_submission_values_template."
            "slot_values[1].path_value_hint must be "
            "'Path to an engine_run_bundle_manifest JSON file.'",
            errors,
        )

    def test_official_operator_evidence_submission_values_template_rejects_expected_submission_path_drift(self):
        payload = self.operator_evidence_submission_values_template()
        payload["slot_values"][0]["expected_submission_path"] = "/tmp/stale.json"
        payload["slot_values"][1]["expected_submission_path_state"] = (
            "no_submission_manifest_command_template"
        )

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_submission_values_template."
            "slot_values[0].expected_submission_path must be "
            "'/tmp/reference_review_workflow/"
            "reference_review_batch_workflow_report.json'",
            errors,
        )
        self.assertIn(
            "official_comparison_operator_evidence_submission_values_template."
            "slot_values[1].expected_submission_path_state must be "
            "'known_from_command_template'",
            errors,
        )

    def test_official_operator_evidence_submission_values_template_rejects_empty_source_candidate_summary(self):
        payload = self.operator_evidence_submission_values_template()
        payload["submission_action_groups"][0]["source_candidate_summary"] = []

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_submission_values_template."
            "submission_action_groups[0].source_candidate_summary must not be empty "
            "when source_paths exist",
            errors,
        )

    def test_official_operator_evidence_submission_values_template_rejects_source_candidate_summary_drift(self):
        payload = self.operator_evidence_submission_values_template()
        payload["submission_action_groups"][0]["source_candidate_summary"][0][
            "candidate_count"
        ] = 99

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_submission_values_template."
            "submission_action_groups[0].source_candidate_summary "
            "must match grouped slot source_candidate_diagnostics",
            errors,
        )

    def test_official_operator_evidence_submission_values_template_rejects_action_group_next_actions_drift(self):
        payload = self.operator_evidence_submission_values_template()
        payload["submission_action_groups"][0]["next_actions"] = ["Use stale guidance."]

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_submission_values_template."
            "submission_action_groups[0].next_actions "
            "must match grouped slot next_actions",
            errors,
        )

    def test_official_operator_evidence_submission_values_template_rejects_action_group_context_drift(self):
        payload = self.operator_evidence_submission_values_template()
        payload["submission_action_groups"][0]["return_fields"] = [
            "run_bundle_manifest_paths"
        ]

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_submission_values_template."
            "submission_action_groups[0].return_fields "
            "must match grouped slot context",
            errors,
        )

    def test_official_operator_evidence_submission_values_template_rejects_duplicate_slot_id(self):
        payload = self.operator_evidence_submission_values_template()
        payload["slot_values"][1]["slot_id"] = payload["slot_values"][0]["slot_id"]

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_submission_values_template."
            "slot_values[1].slot_id must be unique: "
            "reference_review_workflow_report",
            errors,
        )

    def test_official_operator_evidence_submission_values_template_rejects_extra_editable_fields(self):
        payload = self.operator_evidence_submission_values_template()
        payload["editable_fields"] = ["slot_values[].path", "slot_values[].slot_id"]
        payload["slot_values"][0]["editable_fields"] = ["path", "slot_id"]

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_submission_values_template."
            "editable_fields must be ['slot_values[].path']",
            errors,
        )
        self.assertIn(
            "official_comparison_operator_evidence_submission_values_template."
            "slot_values[0].editable_fields must be ['path']",
            errors,
        )

    def test_official_operator_evidence_submission_values_template_requires_read_only_instructions(self):
        payload = self.operator_evidence_submission_values_template()
        payload["path_editing_instructions"] = [
            "Edit only slot_values[].path values in this JSON file.",
        ]

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_submission_values_template."
            "path_editing_instructions must mention target_reference_version",
            errors,
        )
        self.assertIn(
            "official_comparison_operator_evidence_submission_values_template."
            "path_editing_instructions must mention "
            "operator_evidence_return_template_path",
            errors,
        )

    def test_official_operator_evidence_submission_values_template_requires_source_candidate_diagnostics(self):
        payload = self.operator_evidence_submission_values_template()
        del payload["slot_values"][0]["source_candidate_diagnostics"]

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_submission_values_template."
            "slot_values[0].source_candidate_diagnostics is required",
            errors,
        )

    def test_official_operator_evidence_submission_values_template_rejects_empty_source_candidate_diagnostics(self):
        payload = self.operator_evidence_submission_values_template()
        payload["slot_values"][0]["source_candidate_diagnostics"] = []

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_submission_values_template."
            "slot_values[0].source_candidate_diagnostics must not be empty "
            "when source_paths exist",
            errors,
        )

    def test_official_operator_evidence_submission_values_template_rejects_slot_target_reference_drift(self):
        payload = self.operator_evidence_submission_values_template()
        payload["slot_values"][0]["target_reference_version"] = "other-reference"

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_submission_values_template."
            "slot_values[0].target_reference_version must match "
            "target_reference_version",
            errors,
        )

    def test_official_operator_evidence_submission_values_template_rejects_expected_manifest_type_drift(self):
        payload = self.operator_evidence_submission_values_template()
        payload["slot_values"][0]["expected_manifest_types"] = [
            "engine_run_bundle_manifest",
        ]

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_submission_values_template."
            "slot_values[0].expected_manifest_types must be "
            "['reference_review_batch_workflow_report'] for "
            "return_field=reference_review_workflow_report_path",
            errors,
        )

    def test_official_operator_evidence_submission_values_template_rejects_product_path_context_drift(self):
        payload = self.operator_evidence_submission_values_template()
        payload["slot_values"][1]["benchmark_kind"] = "offline_final"

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_submission_values_template."
            "slot_values[1].product_path_run_bundle requires "
            "benchmark_kind=product_path_final",
            errors,
        )

    def test_official_operator_evidence_submission_values_template_requires_return_template_path(self):
        payload = self.operator_evidence_submission_values_template()
        del payload["operator_evidence_return_template_path"]

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_submission_values_template."
            "operator_evidence_return_template_path is required",
            errors,
        )

    def test_official_operator_evidence_submission_values_template_requires_return_template_evidence_path(self):
        payload = self.operator_evidence_submission_values_template()
        payload["evidence_paths"].remove(payload["operator_evidence_return_template_path"])

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_submission_values_template."
            "evidence_paths must include operator_evidence_return_template_path",
            errors,
        )

    def test_official_operator_evidence_return_workflow_report_manifest_is_valid(self):
        self.assertEqual(
            validator.validate_manifest(self.operator_evidence_return_workflow_report()),
            [],
        )

    def test_official_operator_evidence_return_workflow_report_accepts_submission_slot_values(self):
        payload = self.operator_evidence_return_workflow_report()
        payload["run_bundle_manifest_paths"] = ["/tmp/engine_run_bundle_manifest.json"]
        payload["submission_slot_values"] = [
            {
                "slot_id": "product_path_bundle_speech_analyzer",
                "return_field": "run_bundle_manifest_paths",
                "path": "/tmp/engine_run_bundle_manifest.json",
            },
        ]

        self.assertEqual(validator.validate_manifest(payload), [])

    def test_official_operator_evidence_return_workflow_report_rejects_slot_value_drift(self):
        payload = self.operator_evidence_return_workflow_report()
        payload["run_bundle_manifest_paths"] = ["/tmp/engine_run_bundle_manifest.json"]
        payload["submission_slot_values"] = [
            {
                "slot_id": "product_path_bundle_speech_analyzer",
                "return_field": "run_bundle_manifest_paths",
                "path": "/tmp/other_engine_run_bundle_manifest.json",
            },
        ]

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_return_workflow_report."
            "submission_slot_values run bundle path must be in run_bundle_manifest_paths",
            errors,
        )

    def test_official_operator_evidence_return_workflow_report_rejects_duplicate_submission_slot_values(self):
        payload = self.operator_evidence_return_workflow_report()
        payload["run_bundle_manifest_paths"] = ["/tmp/engine_run_bundle_manifest.json"]
        payload["submission_slot_values"] = [
            {
                "slot_id": "product_path_bundle_speech_analyzer",
                "return_field": "run_bundle_manifest_paths",
                "path": "/tmp/engine_run_bundle_manifest.json",
            },
            {
                "slot_id": "product_path_bundle_speech_analyzer",
                "return_field": "run_bundle_manifest_paths",
                "path": "/tmp/engine_run_bundle_manifest.json",
            },
        ]

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_return_workflow_report."
            "submission_slot_values[1].slot_id must be unique: "
            "product_path_bundle_speech_analyzer",
            errors,
        )

    def test_official_operator_evidence_return_workflow_report_rejects_bad_item_count(self):
        payload = self.operator_evidence_return_workflow_report()
        payload["operator_evidence_missing_item_count"] = 0

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_return_workflow_report."
            "operator_evidence_missing_item_count must equal missing items",
            errors,
        )

    def test_official_operator_evidence_return_workflow_report_rejects_mismatched_task_result(self):
        payload = self.operator_evidence_return_workflow_report()
        payload["operator_evidence_task_results"][0]["state"] = "rejected"

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_return_workflow_report."
            "operator_evidence_task_results must match operator_evidence_items task states",
            errors,
        )

    def test_official_operator_evidence_return_workflow_report_rejects_mismatched_task_detail(self):
        payload = self.operator_evidence_return_workflow_report()
        payload["operator_evidence_task_results"][0]["reasons"] = [
            "manually edited reason"
        ]

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_return_workflow_report."
            "operator_evidence_task_results must match operator_evidence_items task details",
            errors,
        )

    def test_official_operator_evidence_return_workflow_report_rejects_incomplete_field_status(self):
        payload = self.operator_evidence_return_workflow_report()
        payload["operator_evidence_task_results"][0]["provided_return_fields"] = [
            "target_reference_version"
        ]

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_return_workflow_report."
            "operator_evidence_task_results[0].provided_return_fields and "
            "missing_return_fields must cover return_fields",
            errors,
        )

    def test_official_operator_evidence_return_workflow_report_rejects_mismatched_return_field_status(self):
        payload = self.operator_evidence_return_workflow_report()
        payload["return_field_statuses"][0]["task_ids"] = [
            "reference_review",
            "product_path_official_run",
        ]

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_return_workflow_report."
            "return_field_statuses must match operator_evidence_task_results return_fields",
            errors,
        )

    def test_official_operator_evidence_return_workflow_report_rejects_bad_field_value_type(self):
        payload = self.operator_evidence_return_workflow_report()
        payload["return_field_statuses"][0]["value_type"] = "unknown_type"
        payload["return_field_statuses"][0]["resolved_expected_value"] = 7
        payload["return_field_statuses"][0]["field_resolution_state"] = "unknown_state"

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_return_workflow_report."
            "return_field_statuses[0].value_type is invalid: 'unknown_type'",
            errors,
        )
        self.assertIn(
            "official_comparison_operator_evidence_return_workflow_report."
            "return_field_statuses[0].resolved_expected_value must be str",
            errors,
        )
        self.assertIn(
            "official_comparison_operator_evidence_return_workflow_report."
            "return_field_statuses[0].field_resolution_state is invalid: "
            "'unknown_state'",
            errors,
        )

    def test_official_operator_evidence_return_workflow_report_rejects_mismatched_field_verdicts(self):
        payload = self.operator_evidence_return_workflow_report()
        payload["return_field_statuses"][1]["accepted_evidence_task_ids"] = []
        payload["return_field_statuses"][1]["field_resolution_state"] = "accepted"

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_return_workflow_report."
            "return_field_statuses accepted_evidence_task_ids must match "
            "operator_evidence_task_results",
            errors,
        )
        self.assertIn(
            "official_comparison_operator_evidence_return_workflow_report."
            "return_field_statuses field_resolution_state must match "
            "operator_evidence_task_results",
            errors,
        )

    def test_official_operator_evidence_return_workflow_report_rejects_bad_field_contract_state(self):
        payload = self.operator_evidence_return_workflow_report()
        payload["return_field_statuses"][0]["value_contract_state"] = "unknown_state"
        payload["return_field_statuses"][0]["value_contract_errors"] = []

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_return_workflow_report."
            "return_field_statuses[0].value_contract_state is invalid: 'unknown_state'",
            errors,
        )

    def test_official_operator_evidence_return_workflow_report_rejects_invalid_contract_without_errors(self):
        payload = self.operator_evidence_return_workflow_report()
        payload["return_field_statuses"][1]["value_contract_state"] = "invalid"
        payload["return_field_statuses"][1]["value_contract_errors"] = []

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_return_workflow_report."
            "return_field_statuses[1].value_contract_state=invalid requires value_contract_errors",
            errors,
        )

    def test_official_operator_evidence_return_workflow_report_rejects_contract_state_without_errors_field(self):
        payload = self.operator_evidence_return_workflow_report()
        payload["return_field_statuses"][1].pop("value_contract_errors")

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_return_workflow_report."
            "return_field_statuses[1].value_contract_state and value_contract_errors must appear together",
            errors,
        )

    def test_official_operator_evidence_return_workflow_report_rejects_mismatched_status_adoption_items(self):
        payload = self.operator_evidence_return_workflow_report()
        payload["return_field_statuses"][0]["adoption_item_ids"] = [
            "product_path_only_default_decision"
        ]

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_return_workflow_report."
            "return_field_statuses adoption_item_ids must match operator_evidence_task_results",
            errors,
        )

    def test_official_operator_evidence_return_workflow_report_rejects_mismatched_status_requested_tasks(self):
        payload = self.operator_evidence_return_workflow_report()
        payload["return_field_statuses"][0]["requested_task_ids"] = []

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_return_workflow_report."
            "return_field_statuses requested_task_ids must match operator_evidence_task_results",
            errors,
        )

    def test_official_operator_evidence_return_workflow_report_rejects_mismatched_blocker_summary(self):
        payload = self.operator_evidence_return_workflow_report()
        payload["return_blocker_summary"][1]["blocked_adoption_item_ids"] = []

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_return_workflow_report."
            "return_blocker_summary must match return_field_statuses and "
            "operator_evidence_task_results",
            errors,
        )

    def test_official_operator_evidence_return_workflow_report_rejects_target_field_value_mismatch(self):
        payload = self.operator_evidence_return_workflow_report()
        for item in payload["return_field_statuses"]:
            if item["field"] == "target_reference_version":
                item["values"] = ["other-reference"]

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_return_workflow_report."
            "return_field_statuses target_reference_version values must match target_reference_version",
            errors,
        )

    def test_engine_lane_matrix_manifest_is_valid(self):
        payload = {
            "manifest_type": "engine_lane_matrix",
            "schema_version": 1,
            "reference_versions": ["fixture-reference-v1"],
            "entry_count": 1,
            "lanes": [
                {
                    "engine_id": "speech_analyzer",
                    "engine_label": "SpeechAnalyzer",
                    "lane": "offline_final",
                    "benchmark_kind": "offline_final",
                    "product_path": False,
                    "default_gate_input": False,
                    "runtime": "apple_speech",
                    "model_id": "apple_speech_analyzer_ko_KR",
                    "requires_sidecar": False,
                    "supports_streaming": False,
                    "reference_version": "fixture-reference-v1",
                    "sample_set": "fixture-set",
                    "sample_count": 7,
                    "weighted_cer": 0.31,
                    "macro_cer": 0.32,
                    "empty_final_count": 0,
                    "timeout_count": 0,
                    "crash_count": 0,
                    "user_impact_metric_complete": False,
                    "health_status": "ready",
                    "source_paths": {
                        "benchmark_run_manifest": "/tmp/benchmark.json",
                        "metric_summary": "/tmp/metric.json",
                        "engine_manifest": "/tmp/engine.json",
                    },
                },
            ],
            "source_paths": [
                "/tmp/benchmark.json",
                "/tmp/metric.json",
                "/tmp/engine.json",
            ],
        }

        self.assertEqual(validator.validate_manifest(payload), [])

    def test_engine_coverage_report_manifest_is_valid(self):
        payload = {
            "manifest_type": "engine_coverage_report",
            "schema_version": 1,
            "coverage_state": "ready_for_official_comparison",
            "eligible_for_official_comparison": True,
            "engine_lane_matrix_path": "/tmp/engine_lane_matrix.json",
            "reference_versions": ["fixture-reference-v1"],
            "entry_count": 2,
            "required_engine_ids": ["speech_analyzer", "whisper_accurate"],
            "present_engine_ids": ["speech_analyzer", "whisper_accurate"],
            "missing_engine_ids": [],
            "ready_engine_ids": ["speech_analyzer", "whisper_accurate"],
            "unavailable_engine_ids": [],
            "default_gate_input_engine_ids": ["speech_analyzer"],
            "required_engine_lane_counts": {
                "speech_analyzer": 1,
                "whisper_accurate": 1,
            },
            "blocking_gates": [],
            "reasons": ["all required engine ids are present in the lane matrix"],
            "next_actions": ["Use this coverage report as official comparison completeness evidence."],
            "evidence_paths": ["/tmp/engine_lane_matrix.json"],
        }

        self.assertEqual(validator.validate_manifest(payload), [])

    def test_engine_coverage_report_missing_ids_must_match_required_minus_present(self):
        payload = {
            "manifest_type": "engine_coverage_report",
            "schema_version": 1,
            "coverage_state": "blocked_engine_coverage",
            "eligible_for_official_comparison": False,
            "engine_lane_matrix_path": "/tmp/engine_lane_matrix.json",
            "reference_versions": ["fixture-reference-v1"],
            "entry_count": 1,
            "required_engine_ids": ["speech_analyzer", "whisper_accurate"],
            "present_engine_ids": ["speech_analyzer"],
            "missing_engine_ids": [],
            "ready_engine_ids": ["speech_analyzer"],
            "unavailable_engine_ids": [],
            "default_gate_input_engine_ids": [],
            "required_engine_lane_counts": {
                "speech_analyzer": 1,
                "whisper_accurate": 0,
            },
            "blocking_gates": ["missing_required_engine"],
            "reasons": ["missing required engine ids: whisper_accurate"],
            "next_actions": ["Add run bundle entries for every missing required engine before treating the matrix as official."],
            "evidence_paths": ["/tmp/engine_lane_matrix.json"],
        }

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "engine_coverage_report.missing_engine_ids must equal required_engine_ids minus present_engine_ids",
            errors,
        )

    def test_official_comparison_next_action_plan_manifest_is_valid(self):
        payload = {
            "manifest_type": "official_comparison_next_action_plan",
            "schema_version": 1,
            "plan_state": "blocked_next_actions",
            "workflow_report_path": "/tmp/official_comparison_preflight_workflow_report.json",
            "workflow_state": "blocked_preflight",
            "eligible_for_official_comparison": False,
            "reference_version": "fixture-reference-v1",
            "blocking_gates": ["missing_required_engine"],
            "task_count": 1,
            "open_task_count": 1,
            "tasks": [
                {
                    "task_id": "required_engine_whisper_accurate",
                    "category": "engine_run",
                    "title": "Add required official run bundle entry for whisper_accurate.",
                    "state": "open",
                    "blocking_gates": ["missing_required_engine"],
                    "target": "whisper_accurate",
                    "command": "python3 scripts/convert_stt_pipeline_to_official_bundle.py",
                    "evidence_needed": ["whisper_accurate metric_summary"],
                    "evidence_paths": ["/tmp/engine_coverage_report.json"],
                },
            ],
            "evidence_paths": ["/tmp/official_comparison_preflight_workflow_report.json"],
            "markdown_report_path": "/tmp/official_comparison_next_action_plan.md",
            "html_report_path": "/tmp/official_comparison_next_action_plan.html",
        }

        self.assertEqual(validator.validate_manifest(payload), [])

    def test_official_comparison_next_action_plan_rejects_missing_open_task(self):
        payload = {
            "manifest_type": "official_comparison_next_action_plan",
            "schema_version": 1,
            "plan_state": "blocked_next_actions",
            "workflow_report_path": "/tmp/official_comparison_preflight_workflow_report.json",
            "workflow_state": "blocked_preflight",
            "eligible_for_official_comparison": False,
            "reference_version": "fixture-reference-v1",
            "blocking_gates": ["missing_required_engine"],
            "task_count": 0,
            "open_task_count": 0,
            "tasks": [],
            "evidence_paths": ["/tmp/official_comparison_preflight_workflow_report.json"],
            "markdown_report_path": "/tmp/official_comparison_next_action_plan.md",
            "html_report_path": "/tmp/official_comparison_next_action_plan.html",
        }

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_next_action_plan.blocked state requires open_task_count>0",
            errors,
        )

    def test_official_comparison_next_action_artifact_prep_report_manifest_is_valid(self):
        payload = {
            "manifest_type": "official_comparison_next_action_artifact_prep_report",
            "schema_version": 1,
            "prep_state": "prepared_reference_review_pack",
            "workflow_report_path": "/tmp/official_comparison_preflight_workflow_report.json",
            "workflow_state": "blocked_preflight",
            "eligible_for_official_comparison": False,
            "reference_version": "fixture-reference-v1",
            "reference_batch_duration_minutes": 60.0,
            "prepared_task_ids": ["reference_review"],
            "prepared_artifact_count": 2,
            "prepared_artifact_paths": [
                "/tmp/reference_review_progress_report.json",
                "/tmp/reference_review_pack_manifest.json",
            ],
            "next_actions": ["Open the reference review HTML pack."],
            "notes": ["Reference review decisions are still manual."],
            "evidence_paths": ["/tmp/official_comparison_preflight_workflow_report.json"],
            "markdown_report_path": "/tmp/official_comparison_next_action_artifact_prep_report.md",
            "html_report_path": "/tmp/official_comparison_next_action_artifact_prep_report.html",
        }

        self.assertEqual(validator.validate_manifest(payload), [])

    def test_official_comparison_next_action_artifact_prep_rejects_count_mismatch(self):
        payload = {
            "manifest_type": "official_comparison_next_action_artifact_prep_report",
            "schema_version": 1,
            "prep_state": "prepared_reference_review_pack",
            "workflow_report_path": "/tmp/official_comparison_preflight_workflow_report.json",
            "workflow_state": "blocked_preflight",
            "eligible_for_official_comparison": False,
            "reference_version": "fixture-reference-v1",
            "reference_batch_duration_minutes": 60.0,
            "prepared_task_ids": ["reference_review"],
            "prepared_artifact_count": 0,
            "prepared_artifact_paths": ["/tmp/reference_review_pack_manifest.json"],
            "next_actions": ["Open the reference review HTML pack."],
            "notes": ["Reference review decisions are still manual."],
            "evidence_paths": ["/tmp/official_comparison_preflight_workflow_report.json"],
            "markdown_report_path": "/tmp/official_comparison_next_action_artifact_prep_report.md",
            "html_report_path": "/tmp/official_comparison_next_action_artifact_prep_report.html",
        }

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_next_action_artifact_prep_report.prepared_artifact_count "
            "must equal prepared_artifact_paths length",
            errors,
        )

    def test_official_comparison_next_action_execution_status_report_manifest_is_valid(self):
        payload = {
            "manifest_type": "official_comparison_next_action_execution_status_report",
            "schema_version": 1,
            "execution_state": "blocked_waiting_for_evidence",
            "workflow_report_path": "/tmp/official_comparison_preflight_workflow_report.json",
            "artifact_prep_report_path": "/tmp/official_comparison_next_action_artifact_prep_report.json",
            "workflow_state": "blocked_preflight",
            "eligible_for_official_comparison": False,
            "reference_version": "fixture-reference-v1",
            "task_status_count": 1,
            "ready_task_count": 0,
            "blocked_task_count": 1,
            "total_runnable_command_count": 0,
            "task_statuses": [
                {
                    "task_id": "reference_review",
                    "category": "reference",
                    "status": "waiting_for_manual_input",
                    "runnable_command_count": 0,
                    "runnable_commands": [],
                    "evidence_needed": ["reviewed reference_review_decisions.csv"],
                    "prepared_artifact_paths": ["/tmp/reference_review_pack.html"],
                    "blocking_reasons": ["reference review preflight is blocked_review_decision_incomplete"],
                    "next_action": "Complete the reference review CSV.",
                },
            ],
            "next_actions": ["Complete the reference review CSV."],
            "evidence_paths": ["/tmp/official_comparison_preflight_workflow_report.json"],
            "markdown_report_path": "/tmp/official_comparison_next_action_execution_status_report.md",
            "html_report_path": "/tmp/official_comparison_next_action_execution_status_report.html",
        }

        self.assertEqual(validator.validate_manifest(payload), [])

    def test_official_comparison_next_action_execution_status_rejects_ready_without_command(self):
        payload = {
            "manifest_type": "official_comparison_next_action_execution_status_report",
            "schema_version": 1,
            "execution_state": "ready_to_execute",
            "workflow_report_path": "/tmp/official_comparison_preflight_workflow_report.json",
            "artifact_prep_report_path": "/tmp/official_comparison_next_action_artifact_prep_report.json",
            "workflow_state": "blocked_preflight",
            "eligible_for_official_comparison": False,
            "reference_version": "fixture-reference-v1",
            "task_status_count": 1,
            "ready_task_count": 1,
            "blocked_task_count": 0,
            "total_runnable_command_count": 0,
            "task_statuses": [
                {
                    "task_id": "product_path_official_run",
                    "category": "product_path",
                    "status": "ready_to_execute",
                    "runnable_command_count": 0,
                    "runnable_commands": [],
                    "evidence_needed": ["source-contract dry-run"],
                    "prepared_artifact_paths": ["/tmp/product_path_official_run_plan.json"],
                    "blocking_reasons": [],
                    "next_action": "Run dry-run command.",
                },
            ],
            "next_actions": ["Run dry-run command."],
            "evidence_paths": ["/tmp/official_comparison_preflight_workflow_report.json"],
            "markdown_report_path": "/tmp/official_comparison_next_action_execution_status_report.md",
            "html_report_path": "/tmp/official_comparison_next_action_execution_status_report.html",
        }

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_next_action_execution_status_report.task_statuses[0]."
            "ready_to_execute requires runnable_command_count>0",
            errors,
        )

    def test_official_comparison_operator_handoff_report_manifest_is_valid(self):
        payload = {
            "manifest_type": "official_comparison_operator_handoff_report",
            "schema_version": 1,
            "handoff_state": "blocked_waiting_for_operator_evidence",
            "workflow_report_path": "/tmp/official_comparison_preflight_workflow_report.json",
            "artifact_prep_report_path": "/tmp/official_comparison_next_action_artifact_prep_report.json",
            "execution_status_report_path": "/tmp/official_comparison_next_action_execution_status_report.json",
            "workflow_state": "blocked_preflight",
            "eligible_for_official_comparison": False,
            "reference_version": "fixture-reference-v1",
            "item_count": 1,
            "ready_item_count": 0,
            "blocked_item_count": 1,
            "handoff_items": [
                {
                    "item_id": "01_reference_review",
                    "task_id": "reference_review",
                    "category": "reference",
                    "execution_status": "waiting_for_manual_input",
                    "title": "Complete reference review and gold split promotion",
                    "operator_action": "Open the reference review HTML pack.",
                    "evidence_to_return": ["reviewed reference_review_decisions.csv"],
                    "source_paths": ["/tmp/reference_review_pack.html"],
                    "blocking_reasons": ["reference review preflight is blocked_review_decision_incomplete"],
                },
            ],
            "next_actions": ["Open the reference review HTML pack."],
            "evidence_paths": ["/tmp/official_comparison_preflight_workflow_report.json"],
            "markdown_report_path": "/tmp/official_comparison_operator_handoff_report.md",
            "html_report_path": "/tmp/official_comparison_operator_handoff_report.html",
        }

        self.assertEqual(validator.validate_manifest(payload), [])

    def test_official_comparison_operator_handoff_rejects_count_mismatch(self):
        payload = {
            "manifest_type": "official_comparison_operator_handoff_report",
            "schema_version": 1,
            "handoff_state": "blocked_waiting_for_operator_evidence",
            "workflow_report_path": "/tmp/official_comparison_preflight_workflow_report.json",
            "artifact_prep_report_path": "/tmp/official_comparison_next_action_artifact_prep_report.json",
            "execution_status_report_path": "/tmp/official_comparison_next_action_execution_status_report.json",
            "workflow_state": "blocked_preflight",
            "eligible_for_official_comparison": False,
            "reference_version": "fixture-reference-v1",
            "item_count": 0,
            "ready_item_count": 0,
            "blocked_item_count": 1,
            "handoff_items": [
                {
                    "item_id": "01_reference_review",
                    "task_id": "reference_review",
                    "category": "reference",
                    "execution_status": "waiting_for_manual_input",
                    "title": "Complete reference review and gold split promotion",
                    "operator_action": "Open the reference review HTML pack.",
                    "evidence_to_return": ["reviewed reference_review_decisions.csv"],
                    "source_paths": ["/tmp/reference_review_pack.html"],
                    "blocking_reasons": ["reference review preflight is blocked_review_decision_incomplete"],
                },
            ],
            "next_actions": ["Open the reference review HTML pack."],
            "evidence_paths": ["/tmp/official_comparison_preflight_workflow_report.json"],
            "markdown_report_path": "/tmp/official_comparison_operator_handoff_report.md",
            "html_report_path": "/tmp/official_comparison_operator_handoff_report.html",
        }

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_handoff_report.item_count must equal handoff_items length",
            errors,
        )

    def test_official_comparison_operator_evidence_intake_report_manifest_is_valid(self):
        payload = {
            "manifest_type": "official_comparison_operator_evidence_intake_report",
            "schema_version": 1,
            "intake_state": "ready_to_rerun_preflight",
            "handoff_report_path": "/tmp/official_comparison_operator_handoff_report.json",
            "target_reference_version": "fixture-reference-v1",
            "ready_to_rerun_preflight": True,
            "item_count": 1,
            "accepted_item_count": 1,
            "missing_item_count": 0,
            "rejected_item_count": 0,
            "items": [
                {
                    "task_id": "product_path_official_run",
                    "state": "accepted",
                    "evidence_paths": ["/tmp/engine_run_bundle_manifest.json"],
                    "reasons": ["real product-path run is ready for the official default gate"],
                    "next_action": "Product-path evidence accepted.",
                },
            ],
            "reference_review_workflow_report_path": None,
            "run_bundle_manifest_paths": ["/tmp/engine_run_bundle_manifest.json"],
            "next_actions": ["Rerun the official comparison preflight with the accepted operator evidence."],
            "evidence_paths": ["/tmp/official_comparison_operator_handoff_report.json"],
            "markdown_report_path": "/tmp/official_comparison_operator_evidence_intake_report.md",
            "html_report_path": "/tmp/official_comparison_operator_evidence_intake_report.html",
        }

        self.assertEqual(validator.validate_manifest(payload), [])

    def test_official_comparison_operator_evidence_intake_rejects_ready_with_missing_item(self):
        payload = {
            "manifest_type": "official_comparison_operator_evidence_intake_report",
            "schema_version": 1,
            "intake_state": "ready_to_rerun_preflight",
            "handoff_report_path": "/tmp/official_comparison_operator_handoff_report.json",
            "target_reference_version": "fixture-reference-v1",
            "ready_to_rerun_preflight": True,
            "item_count": 1,
            "accepted_item_count": 0,
            "missing_item_count": 1,
            "rejected_item_count": 0,
            "items": [
                {
                    "task_id": "reference_review",
                    "state": "missing",
                    "evidence_paths": ["/tmp/reference_review_pack.html"],
                    "reasons": ["reference review workflow report was not provided"],
                    "next_action": "Return a reference_review_batch_workflow_report.",
                },
            ],
            "reference_review_workflow_report_path": None,
            "run_bundle_manifest_paths": [],
            "next_actions": ["Return a reference_review_batch_workflow_report."],
            "evidence_paths": ["/tmp/official_comparison_operator_handoff_report.json"],
            "markdown_report_path": "/tmp/official_comparison_operator_evidence_intake_report.md",
            "html_report_path": "/tmp/official_comparison_operator_evidence_intake_report.html",
        }

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_operator_evidence_intake_report."
            "ready_to_rerun_preflight must reflect accepted/not_needed items only",
            errors,
        )
        self.assertIn(
            "official_comparison_operator_evidence_intake_report."
            "ready_to_rerun_preflight state requires no missing or rejected items",
            errors,
        )

    def test_official_comparison_preflight_resume_plan_manifest_is_valid(self):
        payload = {
            "manifest_type": "official_comparison_preflight_resume_plan",
            "schema_version": 1,
            "plan_state": "ready_to_rerun_preflight",
            "ready_to_rerun_preflight": True,
            "intake_report_path": "/tmp/official_comparison_operator_evidence_intake_report.json",
            "handoff_report_path": "/tmp/official_comparison_operator_handoff_report.json",
            "source_workflow_report_path": "/tmp/official_comparison_preflight_workflow_report.json",
            "target_reference_version": "fixture-reference-v1",
            "reference_manifest_path": "/tmp/reference_manifest.json",
            "run_bundle_manifest_paths": ["/tmp/engine_run_bundle_manifest.json"],
            "required_engine_ids": ["speech_analyzer"],
            "min_gold_samples": 1,
            "min_gold_duration_minutes": 60.0,
            "preflight_output_root": "/tmp/preflight_rerun",
            "rerun_command": "python3 scripts/run_stt_official_comparison_preflight_workflow.py",
            "blocking_reasons": [],
            "next_actions": ["Run: python3 scripts/run_stt_official_comparison_preflight_workflow.py"],
            "evidence_paths": ["/tmp/official_comparison_operator_evidence_intake_report.json"],
            "markdown_report_path": "/tmp/official_comparison_preflight_resume_plan.md",
            "html_report_path": "/tmp/official_comparison_preflight_resume_plan.html",
        }

        self.assertEqual(validator.validate_manifest(payload), [])

    def test_official_comparison_preflight_resume_plan_rejects_ready_without_command(self):
        payload = {
            "manifest_type": "official_comparison_preflight_resume_plan",
            "schema_version": 1,
            "plan_state": "ready_to_rerun_preflight",
            "ready_to_rerun_preflight": True,
            "intake_report_path": "/tmp/official_comparison_operator_evidence_intake_report.json",
            "handoff_report_path": "/tmp/official_comparison_operator_handoff_report.json",
            "source_workflow_report_path": "/tmp/official_comparison_preflight_workflow_report.json",
            "target_reference_version": "fixture-reference-v1",
            "reference_manifest_path": "/tmp/reference_manifest.json",
            "run_bundle_manifest_paths": [],
            "required_engine_ids": ["speech_analyzer"],
            "min_gold_samples": 1,
            "min_gold_duration_minutes": 60.0,
            "preflight_output_root": "/tmp/preflight_rerun",
            "rerun_command": "",
            "blocking_reasons": [],
            "next_actions": [],
            "evidence_paths": ["/tmp/official_comparison_operator_evidence_intake_report.json"],
            "markdown_report_path": "/tmp/official_comparison_preflight_resume_plan.md",
            "html_report_path": "/tmp/official_comparison_preflight_resume_plan.html",
        }

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_preflight_resume_plan."
            "ready_to_rerun_preflight state requires rerun_command",
            errors,
        )
        self.assertIn(
            "official_comparison_preflight_resume_plan."
            "ready_to_rerun_preflight state requires run_bundle_manifest_paths",
            errors,
        )

    def test_official_comparison_release_gate_report_manifest_is_valid(self):
        payload = self.release_gate_report()

        self.assertEqual(validator.validate_manifest(payload), [])

    def test_official_comparison_release_gate_rejects_blocked_without_gates(self):
        payload = self.release_gate_report()
        payload["release_state"] = "blocked_regression"
        payload["eligible_for_default_release"] = False
        payload["regression_state"] = "missing_baseline"
        payload["blocking_reasons"] = ["regression_state=missing_baseline"]

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_release_gate_report.blocked release requires blocking_gates",
            errors,
        )

    def test_official_comparison_release_gate_rejects_wrong_state_priority(self):
        payload = self.release_gate_report()
        payload["regression_state"] = "missing_baseline"
        payload["blocking_gates"] = ["regression_not_passed"]
        payload["blocking_reasons"] = ["regression_state=missing_baseline"]

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_release_gate_report."
            "release_state must be blocked_regression for current gate states",
            errors,
        )

    def test_official_comparison_release_gate_accepts_operator_context(self):
        payload = self.release_gate_report()
        payload["release_state"] = "blocked_preflight"
        payload["eligible_for_default_release"] = False
        payload["preflight_workflow_state"] = "blocked_preflight"
        payload["preflight_eligible_for_official_comparison"] = False
        payload["blocking_gates"] = ["preflight_not_ready"]
        payload["blocking_reasons"] = ["preflight workflow_state=blocked_preflight"]
        payload.update({
            "operator_handoff_report_path": "/tmp/official_comparison_operator_handoff_report.json",
            "operator_handoff_state": "blocked_waiting_for_operator_evidence",
            "operator_handoff_item_count": 4,
            "operator_handoff_blocked_item_count": 4,
            "operator_evidence_intake_report_path": (
                "/tmp/official_comparison_operator_evidence_intake_report.json"
            ),
            "operator_evidence_intake_state": "blocked_missing_operator_evidence",
            "operator_evidence_ready_to_rerun_preflight": False,
            "operator_evidence_accepted_item_count": 0,
            "operator_evidence_missing_item_count": 4,
            "operator_evidence_rejected_item_count": 0,
            "preflight_resume_plan_path": "/tmp/official_comparison_preflight_resume_plan.json",
            "preflight_resume_plan_state": "blocked_operator_evidence",
            "preflight_resume_ready_to_rerun": False,
        })

        self.assertEqual(validator.validate_manifest(payload), [])

    def test_official_comparison_release_gate_rejects_ready_with_blocked_operator_context(self):
        payload = self.release_gate_report()
        payload.update({
            "operator_handoff_state": "blocked_waiting_for_operator_evidence",
            "operator_evidence_intake_state": "blocked_missing_operator_evidence",
            "preflight_resume_plan_state": "blocked_operator_evidence",
        })

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_release_gate_report."
            "ready release requires operator_handoff_state=no_handoff_needed",
            errors,
        )
        self.assertIn(
            "official_comparison_release_gate_report."
            "ready release requires operator_evidence_intake_state=no_handoff_needed",
            errors,
        )
        self.assertIn(
            "official_comparison_release_gate_report."
            "ready release requires preflight_resume_plan_state=no_resume_needed",
            errors,
        )

    def test_official_comparison_release_gate_rejects_invalid_operator_context(self):
        payload = self.release_gate_report()
        payload["operator_handoff_state"] = "invalid"
        payload["operator_evidence_missing_item_count"] = -1

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_release_gate_report.operator_handoff_state is invalid: 'invalid'",
            errors,
        )
        self.assertIn(
            "official_comparison_release_gate_report.operator_evidence_missing_item_count "
            "must be a non-negative integer",
            errors,
        )

    def test_official_release_workflow_report_manifest_is_valid(self):
        payload = self.release_workflow_report()

        self.assertEqual(validator.validate_manifest(payload), [])

    def test_official_release_workflow_rejects_release_gate_copy_drift(self):
        payload = self.release_workflow_report()
        gate_payload = {
            "manifest_type": "official_comparison_release_gate_report",
            "release_state": payload["release_state"],
            "eligible_for_default_release": payload["eligible_for_default_release"],
            "preflight_workflow_report_path": payload[
                "preflight_workflow_report_path"
            ],
            "decision_workflow_report_path": payload[
                "decision_workflow_report_path"
            ],
            "blocking_gates": copy.deepcopy(payload["blocking_gates"]),
            "blocking_reasons": copy.deepcopy(payload["blocking_reasons"]),
            "operator_handoff_report_path": payload["operator_handoff_report_path"],
            "operator_handoff_state": payload["operator_handoff_state"],
            "operator_handoff_item_count": payload["operator_handoff_item_count"],
            "operator_handoff_blocked_item_count": payload[
                "operator_handoff_blocked_item_count"
            ],
            "operator_evidence_intake_report_path": payload[
                "operator_evidence_intake_report_path"
            ],
            "operator_evidence_intake_state": payload[
                "operator_evidence_intake_state"
            ],
            "operator_evidence_ready_to_rerun_preflight": payload[
                "operator_evidence_ready_to_rerun_preflight"
            ],
            "operator_evidence_accepted_item_count": payload[
                "operator_evidence_accepted_item_count"
            ],
            "operator_evidence_missing_item_count": payload[
                "operator_evidence_missing_item_count"
            ],
            "operator_evidence_rejected_item_count": payload[
                "operator_evidence_rejected_item_count"
            ],
            "preflight_resume_plan_path": payload["preflight_resume_plan_path"],
            "preflight_resume_plan_state": payload["preflight_resume_plan_state"],
            "preflight_resume_ready_to_rerun": payload[
                "preflight_resume_ready_to_rerun"
            ],
        }

        with tempfile.TemporaryDirectory() as temp_dir:
            gate_path = Path(temp_dir) / "release_gate_report.json"
            gate_path.write_text(json.dumps(gate_payload), encoding="utf-8")
            payload["release_gate_report_path"] = str(gate_path)
            self.assertEqual(validator.validate_manifest(payload), [])

            payload["operator_evidence_missing_item_count"] = 3

            errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_release_workflow_report."
            "operator_evidence_missing_item_count must match "
            "release_gate_report.operator_evidence_missing_item_count",
            errors,
        )

    def test_official_release_workflow_rejects_artifact_prep_copy_drift(self):
        payload = self.release_workflow_report()
        artifact_prep_payload = {
            "manifest_type": "official_comparison_next_action_artifact_prep_report",
            "prep_state": "prepared_reference_review_pack",
            "workflow_report_path": payload["preflight_workflow_report_path"],
            "workflow_state": "blocked_preflight",
            "eligible_for_official_comparison": False,
            "reference_version": payload["target_reference_version"],
            "reference_batch_duration_minutes": 60.0,
            "prepared_task_ids": ["reference_review"],
            "prepared_artifact_count": 1,
            "prepared_artifact_paths": ["/tmp/reference_review_pack_manifest.json"],
            "next_actions": ["Open the reference review HTML pack."],
            "notes": ["Reference review decisions are still manual."],
            "evidence_paths": [payload["preflight_workflow_report_path"]],
            "markdown_report_path": (
                "/tmp/official_comparison_next_action_artifact_prep_report.md"
            ),
            "html_report_path": (
                "/tmp/official_comparison_next_action_artifact_prep_report.html"
            ),
        }

        with tempfile.TemporaryDirectory() as temp_dir:
            artifact_prep_path = Path(temp_dir) / "artifact_prep_report.json"
            artifact_prep_path.write_text(
                json.dumps(artifact_prep_payload),
                encoding="utf-8",
            )
            payload["artifact_prep_report_path"] = str(artifact_prep_path)
            self.assertEqual(validator.validate_manifest(payload), [])

            payload["preflight_workflow_report_path"] = (
                "/tmp/stale_official_comparison_preflight_workflow_report.json"
            )

            errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_release_workflow_report."
            "preflight_workflow_report_path must match "
            "artifact_prep_report.workflow_report_path",
            errors,
        )

    def test_official_release_workflow_rejects_wrong_child_manifest_type(self):
        payload = self.release_workflow_report()
        wrong_child_payload = {
            "manifest_type": "official_comparison_release_gate_report",
        }

        with tempfile.TemporaryDirectory() as temp_dir:
            artifact_prep_path = Path(temp_dir) / "artifact_prep_report.json"
            artifact_prep_path.write_text(
                json.dumps(wrong_child_payload),
                encoding="utf-8",
            )
            payload["artifact_prep_report_path"] = str(artifact_prep_path)

            errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_release_workflow_report.artifact_prep_report_path "
            "must reference official_comparison_next_action_artifact_prep_report; "
            "got 'official_comparison_release_gate_report'",
            errors,
        )

    def test_official_release_workflow_rejects_execution_status_copy_drift(self):
        payload = self.release_workflow_report()
        execution_status_payload = {
            "manifest_type": (
                "official_comparison_next_action_execution_status_report"
            ),
            "execution_state": "blocked_waiting_for_evidence",
            "workflow_report_path": payload["preflight_workflow_report_path"],
            "artifact_prep_report_path": payload["artifact_prep_report_path"],
            "workflow_state": "blocked_preflight",
            "eligible_for_official_comparison": False,
            "reference_version": payload["target_reference_version"],
            "task_status_count": 1,
            "ready_task_count": 0,
            "blocked_task_count": 1,
            "total_runnable_command_count": 0,
            "task_statuses": [
                {
                    "task_id": "reference_review",
                    "category": "reference",
                    "status": "waiting_for_manual_input",
                    "runnable_command_count": 0,
                    "runnable_commands": [],
                    "evidence_needed": ["reviewed reference_review_decisions.csv"],
                    "prepared_artifact_paths": ["/tmp/reference_review_pack.html"],
                    "blocking_reasons": [
                        "reference review preflight is blocked_review_decision_incomplete"
                    ],
                    "next_action": "Complete the reference review CSV.",
                },
            ],
            "next_actions": ["Complete the reference review CSV."],
            "evidence_paths": [payload["preflight_workflow_report_path"]],
            "markdown_report_path": (
                "/tmp/official_comparison_next_action_execution_status_report.md"
            ),
            "html_report_path": (
                "/tmp/official_comparison_next_action_execution_status_report.html"
            ),
        }

        with tempfile.TemporaryDirectory() as temp_dir:
            execution_status_path = Path(temp_dir) / "execution_status_report.json"
            execution_status_path.write_text(
                json.dumps(execution_status_payload),
                encoding="utf-8",
            )
            payload["execution_status_report_path"] = str(execution_status_path)
            self.assertEqual(validator.validate_manifest(payload), [])

            payload["artifact_prep_report_path"] = "/tmp/stale_artifact_prep_report.json"

            errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_release_workflow_report."
            "artifact_prep_report_path must match "
            "execution_status_report.artifact_prep_report_path",
            errors,
        )

    def test_official_release_workflow_rejects_operator_handoff_copy_drift(self):
        payload = self.release_workflow_report()
        handoff_payload = {
            "manifest_type": "official_comparison_operator_handoff_report",
            "handoff_state": payload["operator_handoff_state"],
            "workflow_report_path": payload["preflight_workflow_report_path"],
            "artifact_prep_report_path": payload["artifact_prep_report_path"],
            "execution_status_report_path": payload["execution_status_report_path"],
            "workflow_state": "blocked_preflight",
            "eligible_for_official_comparison": False,
            "reference_version": payload["target_reference_version"],
            "item_count": payload["operator_handoff_item_count"],
            "ready_item_count": payload["operator_handoff_ready_item_count"],
            "blocked_item_count": payload["operator_handoff_blocked_item_count"],
            "handoff_items": [
                {
                    "item_id": f"{index:02d}_{task['task_id']}",
                    "task_id": task["task_id"],
                    "category": "operator_evidence",
                    "execution_status": task["execution_status"],
                    "title": task["title"],
                    "operator_action": task["operator_action"],
                    "evidence_to_return": copy.deepcopy(
                        task["evidence_to_return"]
                    ),
                    "source_paths": copy.deepcopy(task["source_paths"]),
                    "blocking_reasons": copy.deepcopy(task["reasons"]),
                }
                for index, task in enumerate(payload["operator_tasks"], start=1)
            ],
            "next_actions": copy.deepcopy(payload["next_actions"]),
            "evidence_paths": [
                payload["preflight_workflow_report_path"],
                payload["artifact_prep_report_path"],
                payload["execution_status_report_path"],
            ],
            "markdown_report_path": "/tmp/official_comparison_operator_handoff_report.md",
            "html_report_path": "/tmp/official_comparison_operator_handoff_report.html",
        }

        with tempfile.TemporaryDirectory() as temp_dir:
            handoff_path = Path(temp_dir) / "operator_handoff_report.json"
            handoff_path.write_text(json.dumps(handoff_payload), encoding="utf-8")
            payload["operator_handoff_report_path"] = str(handoff_path)
            self.assertEqual(validator.validate_manifest(payload), [])

            payload["operator_handoff_ready_item_count"] = 1

            errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_release_workflow_report."
            "operator_handoff_ready_item_count must match "
            "operator_handoff_report.ready_item_count",
            errors,
        )

    def test_official_release_workflow_rejects_operator_intake_copy_drift(self):
        payload = self.release_workflow_report()
        intake_payload = {
            "manifest_type": "official_comparison_operator_evidence_intake_report",
            "intake_state": payload["operator_evidence_intake_state"],
            "handoff_report_path": payload["operator_handoff_report_path"],
            "target_reference_version": payload["target_reference_version"],
            "ready_to_rerun_preflight": payload[
                "operator_evidence_ready_to_rerun_preflight"
            ],
            "item_count": payload["operator_handoff_item_count"],
            "accepted_item_count": payload["operator_evidence_accepted_item_count"],
            "missing_item_count": payload["operator_evidence_missing_item_count"],
            "rejected_item_count": payload["operator_evidence_rejected_item_count"],
            "items": [
                {
                    "task_id": task["task_id"],
                    "state": task["evidence_state"],
                    "evidence_paths": copy.deepcopy(task["evidence_paths"]),
                    "reasons": copy.deepcopy(task["reasons"]),
                    "next_action": task["next_action"],
                }
                for task in payload["operator_tasks"]
            ],
            "reference_review_workflow_report_path": None,
            "run_bundle_manifest_paths": [],
            "next_actions": copy.deepcopy(payload["next_actions"]),
            "evidence_paths": [payload["operator_handoff_report_path"]],
            "markdown_report_path": (
                "/tmp/official_comparison_operator_evidence_intake_report.md"
            ),
            "html_report_path": (
                "/tmp/official_comparison_operator_evidence_intake_report.html"
            ),
        }

        with tempfile.TemporaryDirectory() as temp_dir:
            intake_path = Path(temp_dir) / "operator_evidence_intake_report.json"
            intake_path.write_text(json.dumps(intake_payload), encoding="utf-8")
            payload["operator_evidence_intake_report_path"] = str(intake_path)
            self.assertEqual(validator.validate_manifest(payload), [])

            payload["operator_evidence_missing_item_count"] = 3

            errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_release_workflow_report."
            "operator_evidence_missing_item_count must match "
            "operator_evidence_intake_report.missing_item_count",
            errors,
        )

    def test_official_release_workflow_rejects_preflight_resume_copy_drift(self):
        payload = self.release_workflow_report()
        resume_payload = {
            "manifest_type": "official_comparison_preflight_resume_plan",
            "plan_state": payload["preflight_resume_plan_state"],
            "ready_to_rerun_preflight": payload["preflight_resume_ready_to_rerun"],
            "intake_report_path": payload["operator_evidence_intake_report_path"],
            "handoff_report_path": payload["operator_handoff_report_path"],
            "source_workflow_report_path": payload["preflight_workflow_report_path"],
            "target_reference_version": payload["target_reference_version"],
            "reference_manifest_path": "",
            "run_bundle_manifest_paths": [],
            "required_engine_ids": ["speech_analyzer"],
            "min_gold_samples": 1,
            "min_gold_duration_minutes": 60.0,
            "preflight_output_root": "/tmp/preflight_rerun",
            "rerun_command": "",
            "blocking_reasons": ["operator evidence intake is not ready"],
            "next_actions": ["Return accepted operator evidence before rerunning preflight."],
            "evidence_paths": [payload["operator_evidence_intake_report_path"]],
            "markdown_report_path": "/tmp/official_comparison_preflight_resume_plan.md",
            "html_report_path": "/tmp/official_comparison_preflight_resume_plan.html",
        }

        with tempfile.TemporaryDirectory() as temp_dir:
            resume_path = Path(temp_dir) / "preflight_resume_plan.json"
            resume_path.write_text(json.dumps(resume_payload), encoding="utf-8")
            payload["preflight_resume_plan_path"] = str(resume_path)
            self.assertEqual(validator.validate_manifest(payload), [])

            payload["preflight_workflow_report_path"] = (
                "/tmp/stale_official_comparison_preflight_workflow_report.json"
            )

            errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_release_workflow_report."
            "preflight_workflow_report_path must match "
            "preflight_resume_plan.source_workflow_report_path",
            errors,
        )

    def test_official_release_workflow_rejects_execution_plan_copy_drift(self):
        payload = self.release_workflow_report()
        execution_summary = {
            "operator_evidence_execution_step_state_counts": {
                "open": 1,
                "blocked": 3,
                "completed": 0,
                "not_needed": 0,
            },
            "operator_evidence_open_execution_step_count": 1,
            "operator_evidence_blocked_execution_step_count": 3,
            "operator_evidence_completed_execution_step_count": 0,
            "operator_evidence_not_needed_execution_step_count": 0,
            "operator_evidence_open_execution_step_ids": ["collect_reference_review"],
            "operator_evidence_blocked_execution_step_ids": [
                "fill_return_template",
                "run_return_workflow",
                "rerun_release_workflow",
            ],
            "operator_evidence_next_open_execution_step_id": "collect_reference_review",
        }
        execution_summary.update(self.release_next_open_execution_summary())
        payload.update(execution_summary)
        plan_payload = {
            "manifest_type": (
                "official_comparison_operator_evidence_execution_plan"
            ),
            "workflow_state": payload["workflow_state"],
            "adoption_state": payload["adoption_state"],
            "target_reference_version": payload["target_reference_version"],
            "operator_evidence_request_report_path": payload[
                "operator_evidence_request_report_path"
            ],
            "operator_evidence_return_template_path": payload[
                "operator_evidence_return_template_path"
            ],
            "operator_evidence_return_template_fill_command_template_path": payload[
                "operator_evidence_return_template_fill_command_template_path"
            ],
            "operator_evidence_return_workflow_command_template_path": payload[
                "operator_evidence_return_workflow_command_template_path"
            ],
            "operator_evidence_release_workflow_command_template_path": payload[
                "operator_evidence_release_workflow_command_template_path"
            ],
            "adoption_remediation_plan_path": payload[
                "adoption_remediation_plan_path"
            ],
            "operator_task_count": payload["operator_handoff_item_count"],
            "return_field_requirements": copy.deepcopy(
                payload["operator_evidence_return_field_requirements"]
            ),
            "operator_tasks": copy.deepcopy(payload["operator_tasks"]),
            "command_template_paths": copy.deepcopy(payload["command_template_paths"]),
            "execution_step_state_counts": copy.deepcopy(
                execution_summary["operator_evidence_execution_step_state_counts"]
            ),
            "open_execution_step_count": (
                execution_summary["operator_evidence_open_execution_step_count"]
            ),
            "blocked_execution_step_count": (
                execution_summary["operator_evidence_blocked_execution_step_count"]
            ),
            "completed_execution_step_count": (
                execution_summary["operator_evidence_completed_execution_step_count"]
            ),
            "not_needed_execution_step_count": (
                execution_summary[
                    "operator_evidence_not_needed_execution_step_count"
                ]
            ),
            "open_execution_step_ids": copy.deepcopy(
                execution_summary["operator_evidence_open_execution_step_ids"]
            ),
            "blocked_execution_step_ids": copy.deepcopy(
                execution_summary["operator_evidence_blocked_execution_step_ids"]
            ),
            "next_open_execution_step_id": (
                execution_summary["operator_evidence_next_open_execution_step_id"]
            ),
        }
        plan_payload.update(self.execution_plan_next_open_summary())

        with tempfile.TemporaryDirectory() as temp_dir:
            plan_path = Path(temp_dir) / "operator_evidence_execution_plan.json"
            plan_path.write_text(json.dumps(plan_payload), encoding="utf-8")
            payload["operator_evidence_execution_plan_path"] = str(plan_path)
            self.assertEqual(validator.validate_manifest(payload), [])

            payload["operator_evidence_return_template_path"] = (
                "/tmp/stale_operator_evidence_return_template.json"
            )

            errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_release_workflow_report."
            "operator_evidence_return_template_path must match "
            "operator_evidence_execution_plan.operator_evidence_return_template_path",
            errors,
        )

    def test_official_release_workflow_rejects_execution_plan_summary_drift(self):
        payload = self.release_workflow_report()
        payload.update({
            "operator_evidence_execution_step_state_counts": {
                "open": 1,
                "blocked": 3,
                "completed": 0,
                "not_needed": 0,
            },
            "operator_evidence_open_execution_step_count": 1,
            "operator_evidence_blocked_execution_step_count": 3,
            "operator_evidence_completed_execution_step_count": 0,
            "operator_evidence_not_needed_execution_step_count": 0,
            "operator_evidence_open_execution_step_ids": ["collect_reference_review"],
            "operator_evidence_blocked_execution_step_ids": [
                "fill_return_template",
                "run_return_workflow",
                "rerun_release_workflow",
            ],
            "operator_evidence_next_open_execution_step_id": "collect_reference_review",
        })
        payload.update(self.release_next_open_execution_summary())
        plan_payload = {
            "manifest_type": (
                "official_comparison_operator_evidence_execution_plan"
            ),
            "execution_step_state_counts": {
                "open": 1,
                "blocked": 3,
                "completed": 0,
                "not_needed": 0,
            },
            "open_execution_step_count": 1,
            "blocked_execution_step_count": 3,
            "completed_execution_step_count": 0,
            "not_needed_execution_step_count": 0,
            "open_execution_step_ids": ["collect_reference_review"],
            "blocked_execution_step_ids": [
                "fill_return_template",
                "run_return_workflow",
                "rerun_release_workflow",
            ],
            "next_open_execution_step_id": "collect_reference_review",
        }
        plan_payload.update(self.execution_plan_next_open_summary())

        with tempfile.TemporaryDirectory() as temp_dir:
            plan_path = Path(temp_dir) / "operator_evidence_execution_plan.json"
            plan_path.write_text(json.dumps(plan_payload), encoding="utf-8")
            payload["operator_evidence_execution_plan_path"] = str(plan_path)
            self.assertEqual(validator.validate_manifest(payload), [])

            payload["operator_evidence_open_execution_step_count"] = 2

            errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_release_workflow_report."
            "operator_evidence_open_execution_step_count must match "
            "operator_evidence_execution_plan.open_execution_step_count",
            errors,
        )

    def test_official_release_workflow_rejects_submission_checklist_copy_drift(self):
        payload = self.release_workflow_report()
        payload["operator_evidence_submission_slot_count"] = 2
        checklist_payload = {
            "manifest_type": (
                "official_comparison_operator_evidence_submission_checklist"
            ),
            "workflow_state": payload["workflow_state"],
            "adoption_state": payload["adoption_state"],
            "target_reference_version": payload["target_reference_version"],
            "operator_task_count": payload["operator_handoff_item_count"],
            "submission_slot_count": payload[
                "operator_evidence_submission_slot_count"
            ],
            "command_template_paths": copy.deepcopy(payload["command_template_paths"]),
        }

        with tempfile.TemporaryDirectory() as temp_dir:
            checklist_path = Path(temp_dir) / "operator_evidence_submission_checklist.json"
            checklist_path.write_text(json.dumps(checklist_payload), encoding="utf-8")
            payload["operator_evidence_submission_checklist_path"] = str(checklist_path)
            self.assertEqual(validator.validate_manifest(payload), [])

            payload["operator_evidence_submission_slot_count"] = 3

            errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_release_workflow_report."
            "operator_evidence_submission_slot_count must match "
            "operator_evidence_submission_checklist.submission_slot_count",
            errors,
        )

    def test_official_release_workflow_allows_artifact_audit_snapshot_counts(self):
        payload = self.release_workflow_report()
        audit_payload = self.release_artifact_audit_report()
        audit_payload["adoption_passed_item_count"] = (
            payload["adoption_passed_item_count"] + 1
        )
        audit_payload["adoption_unknown_item_count"] = (
            payload["adoption_unknown_item_count"] + 1
        )
        audit_payload["adoption_remediation_open_task_count"] = (
            payload["adoption_remediation_open_task_count"] + 1
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            audit_path = Path(temp_dir) / "release_artifact_audit_report.json"
            audit_path.write_text(json.dumps(audit_payload), encoding="utf-8")
            payload["release_artifact_audit_report_path"] = str(audit_path)

            self.assertEqual(validator.validate_manifest(audit_payload), [])
            self.assertEqual(validator.validate_manifest(payload), [])

    def test_official_release_workflow_rejects_request_report_copy_drift(self):
        payload = self.release_workflow_report()
        request_payload = {
            "manifest_type": "official_comparison_operator_evidence_request_report",
            "request_state": payload["operator_evidence_request_state"],
            "target_reference_version": (
                payload["operator_evidence_request_target_reference_version"]
            ),
            "requested_task_count": payload["operator_evidence_requested_task_count"],
            "return_template_path": payload["operator_evidence_return_template_path"],
            "return_guide_markdown_path": (
                payload["operator_evidence_return_guide_markdown_path"]
            ),
            "return_guide_html_path": (
                payload["operator_evidence_return_guide_html_path"]
            ),
            "return_template_fill_command_template_path": payload[
                "operator_evidence_return_template_fill_command_template_path"
            ],
            "return_workflow_command_template_path": payload[
                "operator_evidence_return_workflow_command_template_path"
            ],
            "intake_command_template_path": payload[
                "operator_evidence_intake_command_template_path"
            ],
            "release_workflow_command_template_path": payload[
                "operator_evidence_release_workflow_command_template_path"
            ],
            "command_template_paths": copy.deepcopy(payload["command_template_paths"]),
            "return_field_requirements": copy.deepcopy(
                payload["operator_evidence_return_field_requirements"]
            ),
        }

        with tempfile.TemporaryDirectory() as temp_dir:
            request_path = Path(temp_dir) / "operator_evidence_request_report.json"
            request_path.write_text(json.dumps(request_payload), encoding="utf-8")
            payload["operator_evidence_request_report_path"] = str(request_path)
            self.assertEqual(validator.validate_manifest(payload), [])

            payload["operator_evidence_return_field_requirements"][0][
                "next_actions"
            ] = ["Use stale request guidance."]

            errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_release_workflow_report."
            "operator_evidence_return_field_requirements must match "
            "operator_evidence_request_report.return_field_requirements",
            errors,
        )

    def test_official_release_workflow_rejects_adoption_remediation_plan_copy_drift(self):
        payload = self.release_workflow_report()
        remediation_payload = {
            "manifest_type": "official_comparison_adoption_remediation_plan",
            "plan_state": payload["adoption_remediation_plan_state"],
            "adoption_state": payload["adoption_state"],
            "target_reference_version": payload[
                "adoption_remediation_target_reference_version"
            ],
            "task_count": payload["adoption_remediation_task_count"],
            "open_task_count": payload["adoption_remediation_open_task_count"],
            "command_template_paths": copy.deepcopy(payload["command_template_paths"]),
        }

        with tempfile.TemporaryDirectory() as temp_dir:
            remediation_path = Path(temp_dir) / "adoption_remediation_plan.json"
            remediation_path.write_text(
                json.dumps(remediation_payload),
                encoding="utf-8",
            )
            payload["adoption_remediation_plan_path"] = str(remediation_path)
            self.assertEqual(validator.validate_manifest(payload), [])

            payload["adoption_remediation_open_task_count"] = 3

            errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_release_workflow_report."
            "adoption_remediation_open_task_count must match "
            "adoption_remediation_plan.open_task_count",
            errors,
        )

    def test_official_release_workflow_rejects_adoption_checklist_copy_drift(self):
        payload = self.release_workflow_report()
        checklist_items = [
            {
                "item_id": f"passed_item_{index}",
                "state": "passed",
            }
            for index in range(payload["adoption_passed_item_count"])
        ]
        checklist_items.extend(
            {
                "item_id": blocker["item_id"],
                "state": blocker["state"],
            }
            for blocker in payload["adoption_blockers"]
        )
        checklist_payload = {
            "manifest_type": "official_comparison_adoption_checklist_report",
            "workflow_state": payload["workflow_state"],
            "release_state": payload["release_state"],
            "eligible_for_default_release": payload[
                "eligible_for_default_release"
            ],
            "adoption_state": payload["adoption_state"],
            "passed_item_count": payload["adoption_passed_item_count"],
            "blocked_item_count": payload["adoption_blocked_item_count"],
            "unknown_item_count": payload["adoption_unknown_item_count"],
            "checklist_items": checklist_items,
        }

        with tempfile.TemporaryDirectory() as temp_dir:
            checklist_path = Path(temp_dir) / "adoption_checklist_report.json"
            checklist_path.write_text(
                json.dumps(checklist_payload),
                encoding="utf-8",
            )
            payload["adoption_checklist_report_path"] = str(checklist_path)
            self.assertEqual(validator.validate_manifest(payload), [])

            payload["adoption_passed_item_count"] = 3

            errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_release_workflow_report."
            "adoption_passed_item_count must match "
            "adoption_checklist_report.passed_item_count",
            errors,
        )

    def test_official_release_workflow_rejects_return_workflow_copy_drift(self):
        payload = self.release_workflow_report_with_return_context()
        return_payload = self.operator_evidence_return_workflow_report()
        return_payload["submission_slot_values"] = copy.deepcopy(
            payload["operator_evidence_return_submission_slot_values"]
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            return_path = Path(temp_dir) / "return_workflow_report.json"
            return_path.write_text(json.dumps(return_payload), encoding="utf-8")
            payload["operator_evidence_return_workflow_report_path"] = str(return_path)
            self.assertEqual(validator.validate_manifest(payload), [])

            payload["operator_evidence_return_field_statuses"][0]["provided"] = True

            errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_release_workflow_report."
            "operator_evidence_return_field_statuses must match "
            "operator_evidence_return_workflow_report.return_field_statuses",
            errors,
        )

    def test_official_release_workflow_rejects_duplicate_return_submission_slot_values(self):
        payload = self.release_workflow_report_with_return_context()
        self.assertEqual(validator.validate_manifest(payload), [])

        payload["operator_evidence_return_submission_slot_values"].append(
            dict(payload["operator_evidence_return_submission_slot_values"][0])
        )

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_release_workflow_report."
            "operator_evidence_return_submission_slot_values[1].slot_id "
            "must be unique: product_path_bundle_speech_analyzer",
            errors,
        )

    def test_official_release_workflow_rejects_unknown_return_submission_slot_value(self):
        payload = self.release_workflow_report_with_return_context()
        self.assertEqual(validator.validate_manifest(payload), [])

        payload["operator_evidence_return_submission_slot_values"][0]["slot_id"] = (
            "unknown_slot"
        )

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_release_workflow_report."
            "operator_evidence_return_submission_slot_values "
            "slot_id must exist in submission slot ids: unknown_slot",
            errors,
        )

    def test_official_release_workflow_rejects_missing_return_submission_slot_value(self):
        payload = self.release_workflow_report_with_return_context()
        self.assertEqual(validator.validate_manifest(payload), [])

        payload["operator_evidence_return_submission_slot_values"][0]["slot_id"] = (
            "reference_review_workflow_report"
        )

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_release_workflow_report."
            "operator_evidence_return_submission_slot_values "
            "slot_id must be submitted or rejected: reference_review_workflow_report",
            errors,
        )

    def test_official_release_workflow_rejects_duplicate_submission_slot_id_list(self):
        payload = self.release_workflow_report_with_return_context()
        self.assertEqual(validator.validate_manifest(payload), [])

        payload["operator_evidence_missing_submission_slot_ids"].append(
            payload["operator_evidence_missing_submission_slot_ids"][0]
        )

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_release_workflow_report."
            "operator_evidence_missing_submission_slot_ids "
            "must contain unique slot ids: reference_review_workflow_report",
            errors,
        )

    def test_official_release_workflow_rejects_overlapping_submission_slot_id_states(self):
        payload = self.release_workflow_report_with_return_context()
        self.assertEqual(validator.validate_manifest(payload), [])

        payload["operator_evidence_missing_submission_slot_ids"] = [
            "product_path_bundle_speech_analyzer",
        ]
        payload["operator_evidence_blocking_submission_slots"][0]["slot_id"] = (
            "product_path_bundle_speech_analyzer"
        )

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_release_workflow_report."
            "operator_evidence_submission_slot_ids must be disjoint across states: "
            "product_path_bundle_speech_analyzer",
            errors,
        )
        self.assertIn(
            "official_release_workflow_report."
            "operator_evidence_submission_slot_ids must cover "
            "operator_evidence_submission_slot_count",
            errors,
        )

    def test_official_release_workflow_rejects_submission_status_state_drift(self):
        payload = self.release_workflow_report_with_return_context()
        self.assertEqual(validator.validate_manifest(payload), [])

        payload["operator_evidence_submission_status_state"] = "all_slots_submitted"

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_release_workflow_report."
            "operator_evidence_submission_status_state must be "
            "blocked_invalid_submissions",
            errors,
        )

    def test_official_release_workflow_rejects_invalid_submission_completion_summary(self):
        payload = self.release_workflow_report_with_return_context()
        self.assertEqual(validator.validate_manifest(payload), [])

        payload["operator_evidence_submission_completion_state"] = "all_done"
        payload["operator_evidence_full_submission_ready"] = "yes"
        payload["operator_evidence_remaining_required_slot_count"] = -1

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_release_workflow_report."
            "operator_evidence_submission_completion_state is invalid: 'all_done'",
            errors,
        )
        self.assertIn(
            "official_release_workflow_report."
            "operator_evidence_full_submission_ready must be bool",
            errors,
        )
        self.assertIn(
            "official_release_workflow_report."
            "operator_evidence_remaining_required_slot_count must be "
            "a non-negative integer",
            errors,
        )

    def test_official_release_workflow_allows_rejected_slot_without_submission_path(self):
        payload = self.release_workflow_report_with_return_context()
        rejected_slot = [
            item
            for item in payload["operator_evidence_blocking_submission_slots"]
            if item["slot_status"] == "rejected"
        ][0]
        rejected_slot["matched_evidence_paths"] = []
        rejected_slot["matched_evidence"] = []
        payload["operator_evidence_submission_values_filled_path_count"] = 1
        payload["operator_evidence_submission_values_blank_path_count"] = 2
        payload[
            "operator_evidence_submission_values_fill_command_readiness_state"
        ] = "ready_to_fill_return_template"
        payload["operator_evidence_submission_values_fill_command_blocking_reasons"] = []
        payload["operator_evidence_submission_command_sequence"] = [
            {
                "step_id": "fill_return_template_from_status",
                "step_order": 1,
                "title": "Fill operator evidence return template from submission status",
                "step_state": "open",
                "command_template_path": "/tmp/fill_from_status_command.txt",
                "input_paths": ["/tmp/operator_evidence_submission_values_template.json"],
                "output_paths": ["/tmp/operator_evidence_return_template.filled.json"],
                "depends_on_step_ids": [],
                "next_actions": ["Run status fill command."],
            },
            {
                "step_id": "run_return_workflow_from_status",
                "step_order": 2,
                "title": "Validate status-filled operator evidence return template",
                "step_state": "blocked",
                "command_template_path": "/tmp/return_workflow_from_status_command.txt",
                "input_paths": ["/tmp/operator_evidence_return_template.filled.json"],
                "output_paths": ["/tmp/operator_evidence_return_workflow_report.json"],
                "depends_on_step_ids": ["fill_return_template_from_status"],
                "next_actions": ["Run after filled return template exists."],
            },
            {
                "step_id": "rerun_release_workflow_from_status_return",
                "step_order": 3,
                "title": "Rerun official release workflow with status return workflow output",
                "step_state": "blocked",
                "command_template_path": "/tmp/release_workflow_from_status_command.txt",
                "input_paths": ["/tmp/operator_evidence_return_workflow_report.json"],
                "output_paths": ["/tmp/official_release_workflow_report.json"],
                "depends_on_step_ids": ["run_return_workflow_from_status"],
                "next_actions": ["Run after status return workflow report exists."],
            },
        ]
        payload["command_template_paths"] = list(
            dict.fromkeys(
                payload["command_template_paths"]
                + [
                    item["command_template_path"]
                    for item in payload["operator_evidence_submission_command_sequence"]
                ]
            )
        )

        errors = validator.validate_manifest(payload)

        self.assertEqual(errors, [])

    def test_official_release_artifact_audit_report_manifest_is_valid(self):
        payload = self.release_artifact_audit_report()

        self.assertEqual(validator.validate_manifest(payload), [])

    def test_official_release_artifact_audit_rejects_bad_counts(self):
        payload = self.release_artifact_audit_report()
        payload["missing_artifact_count"] = 1

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_release_artifact_audit_report."
            "missing_artifact_count must equal missing artifacts",
            errors,
        )

    def test_official_release_artifact_audit_rejects_bad_operator_summary(self):
        payload = self.release_artifact_audit_report()
        payload["operator_evidence_intake_state"] = "invalid"
        payload["operator_evidence_missing_item_count"] = -1

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_release_artifact_audit_report."
            "operator_evidence_intake_state is invalid: 'invalid'",
            errors,
        )
        self.assertIn(
            "official_release_artifact_audit_report."
            "operator_evidence_missing_item_count must be a non-negative integer",
            errors,
        )

    def test_official_release_artifact_audit_rejects_ready_with_missing_artifact(self):
        payload = self.release_artifact_audit_report()
        payload["artifacts"][1]["state"] = "missing"
        payload["artifacts"][1]["errors"] = ["path does not exist"]
        payload["valid_artifact_count"] = 1
        payload["missing_artifact_count"] = 1

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_release_artifact_audit_report."
            "audit_state must be blocked_missing_artifact when missing artifacts exist",
            errors,
        )

    def test_official_release_artifact_audit_rejects_file_manifest_type_mismatch(self):
        payload = self.release_artifact_audit_report()
        payload["artifacts"][0]["artifact_kind"] = "file"

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_release_artifact_audit_report.artifacts[0]."
            "file artifact requires expected_manifest_type=file",
            errors,
        )

    def test_official_comparison_adoption_checklist_report_manifest_is_valid(self):
        self.assertEqual(
            validator.validate_manifest(self.adoption_checklist_report()),
            [],
        )

    def test_official_comparison_adoption_checklist_rejects_bad_counts(self):
        payload = self.adoption_checklist_report()
        payload["blocked_item_count"] = 0

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_adoption_checklist_report."
            "blocked_item_count must equal blocked checklist items",
            errors,
        )

    def test_official_comparison_adoption_remediation_plan_manifest_is_valid(self):
        self.assertEqual(
            validator.validate_manifest(self.adoption_remediation_plan()),
            [],
        )

    def test_official_comparison_adoption_remediation_plan_rejects_bad_counts(self):
        payload = self.adoption_remediation_plan()
        payload["open_task_count"] = 0

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_adoption_remediation_plan."
            "open_task_count must equal open tasks",
            errors,
        )

    def test_official_comparison_adoption_remediation_plan_rejects_missing_target_reference(self):
        payload = self.adoption_remediation_plan()
        payload["target_reference_version"] = ""

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_adoption_remediation_plan."
            "target_reference_version must be a non-empty string",
            errors,
        )

    def test_official_comparison_adoption_remediation_plan_rejects_mismatched_return_fields(self):
        payload = self.adoption_remediation_plan()
        payload["return_field_requirements"][0]["task_ids"] = ["product_path_official_run"]

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_adoption_remediation_plan."
            "return_field_requirements must match task return_fields",
            errors,
        )

    def test_official_comparison_adoption_remediation_plan_rejects_mismatched_return_field_adoption_items(self):
        payload = self.adoption_remediation_plan()
        payload["return_field_requirements"][0]["adoption_item_ids"] = [
            "product_path_only_default_decision"
        ]

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_adoption_remediation_plan."
            "return_field_requirements adoption_item_ids must match tasks",
            errors,
        )

    def test_official_comparison_adoption_remediation_plan_rejects_bad_field_value_type(self):
        payload = self.adoption_remediation_plan()
        payload["return_field_requirements"][0]["value_type"] = "unknown_type"

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_comparison_adoption_remediation_plan."
            "return_field_requirements[0].value_type is invalid: 'unknown_type'",
            errors,
        )

    def test_official_release_workflow_rejects_wrong_state_priority(self):
        payload = self.release_workflow_report()
        payload["workflow_state"] = "blocked_release"

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_release_workflow_report."
            "workflow_state must be blocked_operator_evidence for current gate states",
            errors,
        )

    def test_official_release_workflow_rejects_negative_operator_count(self):
        payload = self.release_workflow_report()
        payload["operator_evidence_missing_item_count"] = -1

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_release_workflow_report."
            "operator_evidence_missing_item_count must be a non-negative integer",
            errors,
        )

    def test_official_release_workflow_rejects_bad_return_field_requirements(self):
        payload = self.release_workflow_report()
        payload["operator_evidence_return_field_requirements"][0]["requested_task_ids"] = []

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_release_workflow_report."
            "operator_evidence_return_field_requirements[0].requested_task_ids must not be empty",
            errors,
        )

    def test_official_release_workflow_rejects_bad_adoption_blocker_count(self):
        payload = self.release_workflow_report()
        payload["adoption_blockers"] = payload["adoption_blockers"][:-1]

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_release_workflow_report."
            "adoption_blockers must equal blocked plus unknown adoption items",
            errors,
        )

    def test_official_release_workflow_rejects_missing_adoption_blocker_next_action(self):
        payload = self.release_workflow_report()
        payload["next_actions"] = ["Rerun the official release workflow."]

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_release_workflow_report."
            "next_actions must include adoption_blockers next_actions",
            errors,
        )

    def test_official_release_workflow_rejects_return_field_task_mapping_drift(self):
        payload = self.release_workflow_report()
        payload["operator_evidence_return_field_requirements"][1]["requested_task_ids"] = [
            "align_engine_reference_version",
            "product_path_official_run",
        ]

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_release_workflow_report."
            "operator_evidence_return_field_requirements must match "
            "adoption blocker return_fields",
            errors,
        )

    def test_official_release_workflow_rejects_return_field_adoption_item_mapping_drift(self):
        payload = self.release_workflow_report()
        payload["operator_evidence_return_field_requirements"][0]["adoption_item_ids"] = [
            "reference_reviewed_gold"
        ]

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_release_workflow_report."
            "operator_evidence_return_field_requirements adoption_item_ids "
            "must match adoption blockers",
            errors,
        )

    def test_official_release_workflow_rejects_operator_evidence_request_target_mismatch(self):
        payload = self.release_workflow_report()
        payload["operator_evidence_request_target_reference_version"] = "other-reference"

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_release_workflow_report."
            "operator_evidence_request_target_reference_version must match target_reference_version",
            errors,
        )

    def test_official_release_workflow_requires_operator_evidence_request_target_when_request_exists(self):
        payload = self.release_workflow_report()
        del payload["operator_evidence_request_target_reference_version"]

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_release_workflow_report."
            "operator_evidence_request_target_reference_version must be a non-empty string",
            errors,
        )

    def test_official_release_workflow_requires_operator_evidence_request_paths_when_request_exists(self):
        payload = self.release_workflow_report()
        del payload["operator_evidence_return_template_path"]
        del payload["command_template_paths"]

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_release_workflow_report."
            "operator_evidence_return_template_path must be a non-empty string",
            errors,
        )
        self.assertIn(
            "official_release_workflow_report.command_template_paths is required",
            errors,
        )

    def test_official_release_workflow_requires_return_fields_when_request_has_tasks(self):
        payload = self.release_workflow_report()
        payload["operator_evidence_return_field_requirements"] = []

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_release_workflow_report."
            "operator_evidence_return_field_requirements must not be empty "
            "when operator evidence request has tasks",
            errors,
        )

    def test_official_release_workflow_rejects_stale_operator_evidence_request_count(self):
        payload = self.release_workflow_report()
        payload["operator_evidence_requested_task_count"] = 3

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_release_workflow_report."
            "operator_evidence_requested_task_count must equal distinct requested_task_ids",
            errors,
        )

    def test_official_release_workflow_rejects_adoption_remediation_target_mismatch(self):
        payload = self.release_workflow_report()
        payload["adoption_remediation_target_reference_version"] = "other-reference"

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_release_workflow_report."
            "adoption_remediation_target_reference_version must match target_reference_version",
            errors,
        )

    def test_official_release_workflow_requires_adoption_remediation_target_when_plan_exists(self):
        payload = self.release_workflow_report()
        del payload["adoption_remediation_target_reference_version"]

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_release_workflow_report."
            "adoption_remediation_target_reference_version must be a non-empty string",
            errors,
        )

    def test_official_release_workflow_rejects_stale_adoption_remediation_task_count(self):
        payload = self.release_workflow_report()
        payload["adoption_remediation_task_count"] = 3

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_release_workflow_report."
            "adoption_remediation_task_count must equal "
            "distinct adoption blocker remediation_task_ids",
            errors,
        )

    def test_official_release_workflow_rejects_passed_adoption_blocker(self):
        payload = self.release_workflow_report()
        payload["adoption_blockers"][0]["state"] = "passed"

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_release_workflow_report."
            "adoption_blockers[0].state is invalid: 'passed'",
            errors,
        )

    def test_official_release_workflow_rejects_invalid_operator_task(self):
        payload = self.release_workflow_report()
        payload["operator_tasks"][0]["evidence_state"] = "unknown"

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "official_release_workflow_report."
            "operator_tasks[0].evidence_state is invalid: 'unknown'",
            errors,
        )

    def test_engine_lane_matrix_rejects_mixed_reference_versions(self):
        payload = {
            "manifest_type": "engine_lane_matrix",
            "schema_version": 1,
            "reference_versions": ["fixture-reference-v1", "other-reference-v1"],
            "entry_count": 0,
            "lanes": [],
            "source_paths": [],
        }

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "engine_lane_matrix.reference_versions must contain exactly one reference version "
            "for official comparison",
            errors,
        )

    def test_engine_run_bundle_fixture_is_valid(self):
        path = ROOT / "fixtures/minimal_engine_run_bundle_manifest.json"
        payload = json.loads(path.read_text(encoding="utf-8"))

        self.assertEqual(validator.validate_manifest(payload), [])

    def test_engine_run_bundle_accepts_missing_repeat_count(self):
        path = ROOT / "fixtures/minimal_engine_run_bundle_manifest.json"
        payload = json.loads(path.read_text(encoding="utf-8"))

        self.assertNotIn("repeat_count", payload)
        self.assertEqual(validator.validate_manifest(payload), [])

    def test_engine_run_bundle_accepts_repeat_count(self):
        path = ROOT / "fixtures/minimal_engine_run_bundle_manifest.json"
        payload = json.loads(path.read_text(encoding="utf-8"))
        payload["repeat_count"] = 2

        self.assertEqual(validator.validate_manifest(payload), [])

    def test_engine_run_bundle_rejects_non_integer_repeat_count(self):
        path = ROOT / "fixtures/minimal_engine_run_bundle_manifest.json"
        payload = json.loads(path.read_text(encoding="utf-8"))
        payload["repeat_count"] = "2"

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "engine_run_bundle_manifest.repeat_count must be an integer >= 1",
            errors,
        )

    def test_engine_run_bundle_rejects_non_positive_repeat_count(self):
        path = ROOT / "fixtures/minimal_engine_run_bundle_manifest.json"
        payload = json.loads(path.read_text(encoding="utf-8"))
        payload["repeat_count"] = 0

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "engine_run_bundle_manifest.repeat_count must be an integer >= 1",
            errors,
        )

    def test_engine_run_bundle_accepts_missing_relative_improvement(self):
        path = ROOT / "fixtures/minimal_engine_run_bundle_manifest.json"
        payload = json.loads(path.read_text(encoding="utf-8"))

        self.assertNotIn("relative_improvement", payload)
        self.assertEqual(validator.validate_manifest(payload), [])

    def test_engine_run_bundle_accepts_relative_improvement(self):
        path = ROOT / "fixtures/minimal_engine_run_bundle_manifest.json"
        payload = json.loads(path.read_text(encoding="utf-8"))
        payload["relative_improvement"] = {
            "cer_improvement_rate": 0.15,
            "baseline_engine_id": "nemotron",
        }

        self.assertEqual(validator.validate_manifest(payload), [])

    def test_engine_run_bundle_rejects_non_dict_relative_improvement(self):
        path = ROOT / "fixtures/minimal_engine_run_bundle_manifest.json"
        payload = json.loads(path.read_text(encoding="utf-8"))
        payload["relative_improvement"] = ["cer_improvement_rate=0.15"]

        errors = validator.validate_manifest(payload)

        self.assertIn("engine_run_bundle_manifest.relative_improvement must be dict", errors)

    def test_engine_run_bundle_rejects_partial_relative_improvement_rate_only(self):
        path = ROOT / "fixtures/minimal_engine_run_bundle_manifest.json"
        payload = json.loads(path.read_text(encoding="utf-8"))
        payload["relative_improvement"] = {"cer_improvement_rate": 0.15}

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "engine_run_bundle_manifest.relative_improvement must include both "
            "cer_improvement_rate and baseline_engine_id",
            errors,
        )

    def test_engine_run_bundle_rejects_partial_relative_improvement_baseline_only(self):
        path = ROOT / "fixtures/minimal_engine_run_bundle_manifest.json"
        payload = json.loads(path.read_text(encoding="utf-8"))
        payload["relative_improvement"] = {"baseline_engine_id": "nemotron"}

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "engine_run_bundle_manifest.relative_improvement must include both "
            "cer_improvement_rate and baseline_engine_id",
            errors,
        )

    def test_engine_run_bundle_rejects_out_of_range_relative_improvement_rate(self):
        path = ROOT / "fixtures/minimal_engine_run_bundle_manifest.json"
        for cer_improvement_rate in [1.01, -1.01]:
            with self.subTest(cer_improvement_rate=cer_improvement_rate):
                payload = json.loads(path.read_text(encoding="utf-8"))
                payload["relative_improvement"] = {
                    "cer_improvement_rate": cer_improvement_rate,
                    "baseline_engine_id": "nemotron",
                }

                errors = validator.validate_manifest(payload)

                self.assertIn(
                    "engine_run_bundle_manifest.relative_improvement.cer_improvement_rate "
                    "must be a number between -1 and 1",
                    errors,
                )

    def test_engine_run_bundle_rejects_empty_relative_improvement_baseline_engine_id(self):
        path = ROOT / "fixtures/minimal_engine_run_bundle_manifest.json"
        payload = json.loads(path.read_text(encoding="utf-8"))
        payload["relative_improvement"] = {
            "cer_improvement_rate": 0.15,
            "baseline_engine_id": " ",
        }

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "engine_run_bundle_manifest.relative_improvement.baseline_engine_id "
            "must be a non-empty string",
            errors,
        )

    def test_engine_run_bundle_accepts_missing_decoding_parameters(self):
        payload = {
            "manifest_type": "engine_run_bundle_manifest",
            "schema_version": 1,
            "reference_version": "fixture-reference-v1",
            "bundle_count": 1,
            "runs": [
                {
                    "engine_id": "speech_analyzer",
                    "benchmark_run_manifest": "/tmp/benchmark.json",
                    "metric_summary": "/tmp/metric.json",
                    "engine_manifest": "/tmp/engine.json",
                }
            ],
        }

        self.assertNotIn("decoding_parameters", payload["runs"][0])
        self.assertEqual(validator.validate_manifest(payload), [])

    def test_engine_run_bundle_accepts_decoding_parameters(self):
        payload = {
            "manifest_type": "engine_run_bundle_manifest",
            "schema_version": 1,
            "reference_version": "fixture-reference-v1",
            "bundle_count": 1,
            "runs": [
                {
                    "engine_id": "whisperkit",
                    "benchmark_run_manifest": "/tmp/benchmark.json",
                    "metric_summary": "/tmp/metric.json",
                    "engine_manifest": "/tmp/engine.json",
                    "decoding_parameters": {
                        "temperature": 0.0,
                        "beam_size": 5,
                        "no_speech_threshold": 0.6,
                        "condition_on_previous_text": False,
                        "language": "ko",
                    },
                }
            ],
        }

        self.assertEqual(validator.validate_manifest(payload), [])

    def test_engine_run_bundle_rejects_non_object_decoding_parameters(self):
        payload = {
            "manifest_type": "engine_run_bundle_manifest",
            "schema_version": 1,
            "reference_version": "fixture-reference-v1",
            "bundle_count": 1,
            "runs": [
                {
                    "engine_id": "whisperkit",
                    "benchmark_run_manifest": "/tmp/benchmark.json",
                    "metric_summary": "/tmp/metric.json",
                    "engine_manifest": "/tmp/engine.json",
                    "decoding_parameters": ["temperature=0.0"],
                }
            ],
        }

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "engine_run_bundle_manifest.runs[0].decoding_parameters must be dict",
            errors,
        )

    def test_engine_run_bundle_accepts_missing_engine_ranking(self):
        payload = {
            "manifest_type": "engine_run_bundle_manifest",
            "schema_version": 1,
            "reference_version": "fixture-reference-v1",
            "bundle_count": 1,
            "runs": [
                {
                    "engine_id": "speech_analyzer",
                    "benchmark_run_manifest": "/tmp/benchmark.json",
                    "metric_summary": "/tmp/metric.json",
                    "engine_manifest": "/tmp/engine.json",
                }
            ],
        }

        self.assertNotIn("engine_ranking", payload)
        self.assertEqual(validator.validate_manifest(payload), [])

    def test_engine_run_bundle_accepts_engine_ranking(self):
        payload = {
            "manifest_type": "engine_run_bundle_manifest",
            "schema_version": 1,
            "reference_version": "fixture-reference-v1",
            "bundle_count": 2,
            "runs": [
                {
                    "engine_id": "whisperkit",
                    "benchmark_run_manifest": "/tmp/whisperkit-benchmark.json",
                    "metric_summary": "/tmp/whisperkit-metric.json",
                    "engine_manifest": "/tmp/whisperkit-engine.json",
                },
                {
                    "engine_id": "nemotron",
                    "benchmark_run_manifest": "/tmp/nemotron-benchmark.json",
                    "metric_summary": "/tmp/nemotron-metric.json",
                    "engine_manifest": "/tmp/nemotron-engine.json",
                },
            ],
            "engine_ranking": [
                {"rank": 1, "engine_id": "whisperkit", "weighted_cer": 0.21},
                {"rank": 2, "engine_id": "nemotron", "weighted_cer": 0.28},
            ],
        }

        self.assertEqual(validator.validate_manifest(payload), [])

    def test_engine_run_bundle_rejects_non_list_engine_ranking(self):
        payload = {
            "manifest_type": "engine_run_bundle_manifest",
            "schema_version": 1,
            "reference_version": "fixture-reference-v1",
            "bundle_count": 1,
            "runs": [
                {
                    "engine_id": "whisperkit",
                    "benchmark_run_manifest": "/tmp/benchmark.json",
                    "metric_summary": "/tmp/metric.json",
                    "engine_manifest": "/tmp/engine.json",
                }
            ],
            "engine_ranking": {
                "rank": 1,
                "engine_id": "whisperkit",
                "weighted_cer": 0.21,
            },
        }

        errors = validator.validate_manifest(payload)

        self.assertIn("engine_run_bundle_manifest.engine_ranking must be list", errors)

    def test_engine_run_bundle_rejects_invalid_engine_ranking_item_fields(self):
        payload = {
            "manifest_type": "engine_run_bundle_manifest",
            "schema_version": 1,
            "reference_version": "fixture-reference-v1",
            "bundle_count": 1,
            "runs": [
                {
                    "engine_id": "whisperkit",
                    "benchmark_run_manifest": "/tmp/benchmark.json",
                    "metric_summary": "/tmp/metric.json",
                    "engine_manifest": "/tmp/engine.json",
                }
            ],
            "engine_ranking": [
                {"rank": 0, "engine_id": " ", "weighted_cer": 1.2},
            ],
        }

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "engine_run_bundle_manifest.engine_ranking[0].rank must be an integer >= 1",
            errors,
        )
        self.assertIn(
            "engine_run_bundle_manifest.engine_ranking[0].engine_id must be a non-empty string",
            errors,
        )
        self.assertIn(
            "engine_run_bundle_manifest.engine_ranking[0].weighted_cer "
            "must be a number between 0 and 1",
            errors,
        )

    def test_engine_run_bundle_rejects_count_mismatch(self):
        payload = {
            "manifest_type": "engine_run_bundle_manifest",
            "schema_version": 1,
            "reference_version": "fixture-reference-v1",
            "bundle_count": 2,
            "runs": [
                {
                    "engine_id": "speech_analyzer",
                    "benchmark_run_manifest": "/tmp/benchmark.json",
                    "metric_summary": "/tmp/metric.json",
                    "engine_manifest": "/tmp/engine.json",
                }
            ],
        }

        errors = validator.validate_manifest(payload)

        self.assertIn("engine_run_bundle_manifest.bundle_count must equal runs length", errors)

    def test_reference_audit_fixture_is_valid(self):
        errors = validator.validate_manifest(self.reference_audit_manifest())

        self.assertEqual(errors, [])

    def test_complete_user_impact_metric_fixture_is_valid(self):
        errors = validator.validate_manifest(self.complete_user_impact_metric_summary())

        self.assertEqual(errors, [])

    def test_metric_summary_accepts_missing_baseline_cer(self):
        payload = self.complete_user_impact_metric_summary()

        self.assertNotIn("baseline_cer", payload)
        self.assertEqual(validator.validate_manifest(payload), [])

    def test_metric_summary_accepts_baseline_cer(self):
        payload = self.complete_user_impact_metric_summary()
        payload["baseline_cer"] = 0.42

        self.assertEqual(validator.validate_manifest(payload), [])

    def test_metric_summary_rejects_non_number_baseline_cer(self):
        payload = self.complete_user_impact_metric_summary()
        payload["baseline_cer"] = "0.42"

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "metric_summary.baseline_cer must be a number between 0 and 1",
            errors,
        )

    def test_metric_summary_rejects_out_of_range_baseline_cer(self):
        payload = self.complete_user_impact_metric_summary()
        payload["baseline_cer"] = 1.2

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "metric_summary.baseline_cer must be a number between 0 and 1",
            errors,
        )

    def test_metric_summary_accepts_missing_phantom_rate(self):
        payload = self.complete_user_impact_metric_summary()

        self.assertNotIn("phantom_rate", payload)
        self.assertEqual(validator.validate_manifest(payload), [])

    def test_metric_summary_accepts_phantom_rate(self):
        payload = self.complete_user_impact_metric_summary()
        payload["phantom_rate"] = 0.25

        self.assertEqual(validator.validate_manifest(payload), [])

    def test_metric_summary_rejects_non_number_phantom_rate(self):
        payload = self.complete_user_impact_metric_summary()
        payload["phantom_rate"] = "0.25"

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "metric_summary.phantom_rate must be a number between 0 and 1",
            errors,
        )

    def test_metric_summary_rejects_out_of_range_phantom_rate(self):
        payload = self.complete_user_impact_metric_summary()
        payload["phantom_rate"] = 1.2

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "metric_summary.phantom_rate must be a number between 0 and 1",
            errors,
        )

    def test_regression_report_fixture_is_valid(self):
        errors = validator.validate_manifest(self.regression_report())

        self.assertEqual(errors, [])

    def test_failed_regression_report_requires_blocking_gates(self):
        payload = self.regression_report()
        payload["regression_state"] = "failed"
        payload["eligible_for_default_gate"] = False

        errors = validator.validate_manifest(payload)

        self.assertIn("regression_report.non-passed state requires blocking_gates", errors)

    def test_user_impact_complete_requires_detail_metrics(self):
        payload = self.complete_user_impact_metric_summary()
        del payload["user_impact_metrics"]

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "metric_summary.user_impact_metrics is required when user_impact_metric_complete=true",
            errors,
        )

    def test_user_impact_ratio_must_be_between_zero_and_one(self):
        payload = self.complete_user_impact_metric_summary()
        payload["user_impact_metrics"]["unstable_partial_ratio"] = 1.2

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "metric_summary.user_impact_metrics.unstable_partial_ratio must be a number between 0 and 1",
            errors,
        )

    def test_gold_reference_rows_must_be_reviewed(self):
        payload = self.reference_audit_manifest()
        payload["references"][0]["review_status"] = "unreviewed"

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "reference_manifest.references[0].gold split requires review_status=reviewed",
            errors,
        )

    def test_reviewed_reference_rows_require_reviewer(self):
        payload = self.reference_audit_manifest()
        payload["references"][0]["reviewer"] = ""

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "reference_manifest.references[0].reviewer must be a non-empty string",
            errors,
        )

    def test_reference_split_counts_must_match_rows(self):
        payload = self.reference_audit_manifest()
        payload["split_counts"]["gold"] = 2

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "reference_manifest.split_counts.gold must equal references split count",
            errors,
        )

    def test_reference_issue_count_must_match_audited_rows(self):
        payload = self.reference_audit_manifest()
        payload["reference_quality_issue_count"] = 0

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "reference_manifest.reference_quality_issue_count must equal audited issue rows",
            errors,
        )

    def test_missing_required_field_fails(self):
        payload = self.valid_decision_manifest()
        del payload["decision_state"]

        errors = validator.validate_manifest(payload)

        self.assertIn("decision_manifest.decision_state is required", errors)

    def test_invalid_decision_state_fails(self):
        payload = self.valid_decision_manifest()
        payload["decision_state"] = "looks_good"

        errors = validator.validate_manifest(payload)

        self.assertIn("decision_manifest.decision_state is invalid: 'looks_good'", errors)

    def test_default_allowed_requires_product_path(self):
        payload = self.valid_decision_manifest()
        payload["decision_state"] = "default_allowed"
        payload["default_change"] = "allowed"
        payload["eligible_for_default"] = True
        payload["manual_review_manifest"]["next_bucket_counts"] = {}

        errors = validator.validate_manifest(payload)

        self.assertIn("decision_manifest.default_allowed requires product_path=true", errors)

    def test_product_path_flag_requires_product_path_benchmark_kind(self):
        payload = self.valid_decision_manifest()
        payload["benchmark_run_manifest"]["product_path"] = True

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "decision_manifest.benchmark_run_manifest.product_path=true "
            "requires benchmark_kind=product_path_final",
            errors,
        )

    def test_incomplete_manual_review_requires_blocked_state(self):
        payload = self.valid_decision_manifest()
        payload["manual_review_manifest"]["complete"] = False

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "decision_manifest.manual_review_manifest.complete=false requires "
            "decision_state=blocked_manual_review",
            errors,
        )

    def test_reference_quality_issue_blocks_candidate_states(self):
        payload = self.valid_decision_manifest()
        payload["reference_manifest"]["reference_quality_issue_count"] = 1

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "decision_manifest.reference quality issues block default/fallback/sidecar candidate states",
            errors,
        )

    def test_reference_version_mismatch_requires_stale_gate(self):
        payload = self.valid_decision_manifest()
        payload["reference_manifest"]["reference_version"] = "new-reviewed-reference-v2"

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "decision_manifest.reference_version mismatch requires "
            "decision_state=blocked_reference_quality",
            errors,
        )
        self.assertIn(
            "decision_manifest.reference_version mismatch requires "
            "stale_reference_version blocking gate",
            errors,
        )

    def test_default_allowed_rejects_boundary_slicing_issue(self):
        payload = self.valid_decision_manifest()
        payload["decision_state"] = "default_allowed"
        payload["default_change"] = "allowed"
        payload["eligible_for_default"] = True
        payload["benchmark_run_manifest"]["product_path"] = True

        errors = validator.validate_manifest(payload)

        self.assertIn("decision_manifest.default_allowed cannot have boundary_slicing_issue rows", errors)

    def test_default_allowed_requires_user_impact_metric_contract(self):
        payload = self.valid_decision_manifest()
        payload["decision_state"] = "default_allowed"
        payload["default_change"] = "allowed"
        payload["eligible_for_default"] = True
        payload["benchmark_run_manifest"]["benchmark_kind"] = "product_path_final"
        payload["benchmark_run_manifest"]["product_path"] = True
        payload["manual_review_manifest"]["next_bucket_counts"] = {}

        errors = validator.validate_manifest(payload)

        self.assertIn("decision_manifest.default_allowed requires user_impact_metric_complete=true", errors)

    def test_default_allowed_rejects_product_path_dry_run(self):
        payload = self.valid_decision_manifest()
        payload["decision_state"] = "default_allowed"
        payload["default_change"] = "allowed"
        payload["eligible_for_default"] = True
        payload["benchmark_run_manifest"]["benchmark_kind"] = "product_path_final"
        payload["benchmark_run_manifest"]["product_path"] = True
        payload["benchmark_run_manifest"]["runner_contract"]["dry_run"] = True
        payload["manual_review_manifest"]["next_bucket_counts"] = {}
        payload["metric_summary"] = self.complete_user_impact_metric_summary()
        payload["reference_readiness_report"] = self.reference_readiness_report()
        payload["regression_report"] = self.regression_report()

        errors = validator.validate_manifest(payload)

        self.assertIn("decision_manifest.default_allowed cannot use dry_run product path", errors)

    def test_default_allowed_requires_reference_readiness_report(self):
        payload = self.valid_decision_manifest()
        payload["decision_state"] = "default_allowed"
        payload["default_change"] = "allowed"
        payload["eligible_for_default"] = True
        payload["benchmark_run_manifest"]["benchmark_kind"] = "product_path_final"
        payload["benchmark_run_manifest"]["product_path"] = True
        payload["manual_review_manifest"]["next_bucket_counts"] = {}
        payload["metric_summary"] = self.complete_user_impact_metric_summary()

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "decision_manifest.default_allowed requires reference_readiness_report",
            errors,
        )

    def test_default_allowed_requires_regression_report(self):
        payload = self.valid_decision_manifest()
        payload["decision_state"] = "default_allowed"
        payload["default_change"] = "allowed"
        payload["eligible_for_default"] = True
        payload["benchmark_run_manifest"]["benchmark_kind"] = "product_path_final"
        payload["benchmark_run_manifest"]["product_path"] = True
        payload["manual_review_manifest"]["next_bucket_counts"] = {}
        payload["metric_summary"] = self.complete_user_impact_metric_summary()
        payload["reference_readiness_report"] = self.reference_readiness_report()

        errors = validator.validate_manifest(payload)

        self.assertIn("decision_manifest.default_allowed requires regression_report", errors)

    def test_default_allowed_requires_passed_regression_report(self):
        payload = self.valid_decision_manifest()
        payload["decision_state"] = "default_allowed"
        payload["default_change"] = "allowed"
        payload["eligible_for_default"] = True
        payload["benchmark_run_manifest"]["benchmark_kind"] = "product_path_final"
        payload["benchmark_run_manifest"]["product_path"] = True
        payload["manual_review_manifest"]["next_bucket_counts"] = {}
        payload["metric_summary"] = self.complete_user_impact_metric_summary()
        payload["reference_readiness_report"] = self.reference_readiness_report()
        payload["regression_report"] = self.regression_report()
        payload["regression_report"]["regression_state"] = "failed"
        payload["regression_report"]["eligible_for_default_gate"] = False
        payload["regression_report"]["blocking_gates"] = ["weighted_cer_regression"]

        errors = validator.validate_manifest(payload)

        self.assertIn("decision_manifest.default_allowed requires passed regression_report", errors)

    def test_reference_readiness_version_mismatch_requires_stale_gate(self):
        payload = self.valid_decision_manifest()
        payload["reference_readiness_report"] = self.reference_readiness_report()
        payload["reference_readiness_report"]["reference_version"] = "other-reference-v2"

        errors = validator.validate_manifest(payload)

        self.assertIn(
            "decision_manifest.reference_readiness_report version mismatch requires "
            "decision_state=blocked_reference_quality",
            errors,
        )
        self.assertIn(
            "decision_manifest.reference_readiness_report version mismatch requires "
            "stale_reference_readiness_report blocking gate",
            errors,
        )

    def reference_readiness_report(self):
        return {
            "manifest_type": "reference_readiness_report",
            "schema_version": 1,
            "reference_version": "seed-smi-2026-06-12",
            "reference_manifest_path": "/tmp/reference.json",
            "readiness_state": "ready_for_default_gate",
            "eligible_for_default_gate": True,
            "blocking_gates": [],
            "reasons": [],
            "next_actions": [],
            "min_gold_samples": 1,
            "min_gold_duration_minutes": 0.0,
            "counts": {
                "sample_count": 1,
                "gold_count": 1,
                "dev_count": 0,
                "stress_count": 0,
                "reviewed_count": 1,
                "unreviewed_count": 0,
                "excluded_count": 0,
                "reference_quality_issue_count": 0,
            },
            "duration_minutes": {
                "total": 1.0,
                "gold": 1.0,
                "dev": 0.0,
                "stress": 0.0,
                "reviewed": 1.0,
                "unreviewed": 0.0,
                "excluded": 0.0,
            },
        }

    def test_cli_returns_nonzero_for_invalid_manifest(self):
        payload = copy.deepcopy(self.valid_decision_manifest())
        payload["decision_state"] = "invalid"
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "invalid.json"
            path.write_text(json.dumps(payload), encoding="utf-8")

            output = io.StringIO()
            with redirect_stdout(output):
                exit_code = validator.main_for_tests([path])

            self.assertEqual(exit_code, 1)
            self.assertIn("invalid", output.getvalue())


if __name__ == "__main__":
    unittest.main()
