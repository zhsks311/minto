import copy
import importlib
import json
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "lib"
FIXTURES = ROOT / "fixtures"
sys.path.insert(0, str(SCRIPTS))

gate = importlib.import_module("run_stt_benchmark_decision_gate")
validator = importlib.import_module("validate_stt_benchmark_manifest")


class STTBenchmarkDecisionGateTests(unittest.TestCase):

    def load(self, name):
        return json.loads((FIXTURES / name).read_text(encoding="utf-8"))

    def args(self, root):
        return type("Args", (), {
            "benchmark_run_manifest": root / "benchmark.json",
            "metric_summary": root / "metric.json",
            "manual_review_manifest": root / "manual.json",
            "reference_manifest": root / "reference.json",
            "reference_readiness_report": None,
            "engine_manifest": root / "engine.json",
            "regression_report": None,
            "output_root": root / "out",
            "sanity_cer_cap": 0.70,
        })()

    def parse_required_args(self, *extra_args):
        return gate.parse_args([
            "--benchmark-run-manifest",
            "/tmp/benchmark.json",
            "--metric-summary",
            "/tmp/metric.json",
            "--manual-review-manifest",
            "/tmp/manual.json",
            "--reference-manifest",
            "/tmp/reference.json",
            "--output-root",
            "/tmp/out",
            *extra_args,
        ])

    def write_inputs(
        self,
        root,
        benchmark=None,
        metric=None,
        manual=None,
        reference=None,
        readiness=None,
        engine=None,
    ):
        payloads = {
            "benchmark.json": benchmark or self.load("minimal_benchmark_run_manifest.json"),
            "metric.json": metric or self.load("minimal_metric_summary.json"),
            "manual.json": manual or self.load("minimal_manual_review_manifest.json"),
            "reference.json": reference or self.load("minimal_reference_manifest.json"),
            "engine.json": engine or self.load("minimal_engine_manifest.json"),
        }
        for name, payload in payloads.items():
            (root / name).write_text(json.dumps(payload), encoding="utf-8")
        if readiness:
            (root / "readiness.json").write_text(json.dumps(readiness), encoding="utf-8")

    def build(self, **overrides):
        benchmark = overrides.get("benchmark") or self.load("minimal_benchmark_run_manifest.json")
        metric = overrides.get("metric") or self.load("minimal_metric_summary.json")
        manual = overrides.get("manual") or self.load("minimal_manual_review_manifest.json")
        reference = overrides.get("reference") or self.load("minimal_reference_manifest.json")
        readiness = overrides.get("readiness")
        engine = overrides.get("engine") or self.load("minimal_engine_manifest.json")
        regression = overrides.get("regression")
        return gate.build_manifest(
            benchmark,
            metric,
            manual,
            reference,
            readiness,
            engine,
            regression,
            type("Args", (), {
                "benchmark_run_manifest": Path("/tmp/benchmark.json"),
                "metric_summary": Path("/tmp/metric.json"),
                "manual_review_manifest": Path("/tmp/manual.json"),
                "reference_manifest": Path("/tmp/reference.json"),
                "reference_readiness_report": Path("/tmp/readiness.json") if readiness else None,
                "engine_manifest": Path("/tmp/engine.json"),
                "regression_report": Path("/tmp/regression.json") if regression else None,
                "sanity_cer_cap": 0.70,
            })(),
        )

    def test_boundary_issue_becomes_experimental_flag_only(self):
        manifest = self.build()

        self.assertEqual(manifest["decision_state"], "experimental_flag_only")
        self.assertIn("boundary_slicing_issue", manifest["blocking_gates"])
        self.assertEqual(validator.validate_manifest(manifest), [])

    def test_reference_issue_blocks_before_boundary_decision(self):
        manual = self.load("minimal_manual_review_manifest.json")
        manual["next_bucket_counts"]["reference_quality_issue"] = 2

        manifest = self.build(manual=manual)

        self.assertEqual(manifest["decision_state"], "blocked_reference_quality")
        self.assertIn("reference_quality_issue", manifest["blocking_gates"])
        self.assertIn("boundary_slicing_issue", manifest["blocking_gates"])
        self.assertEqual(validator.validate_manifest(manifest), [])

    def test_unreviewed_reference_blocks_before_default_decision(self):
        benchmark = self.load("minimal_benchmark_run_manifest.json")
        benchmark["benchmark_kind"] = "product_path_final"
        benchmark["product_path"] = True
        metric = self.load("complete_user_impact_metric_summary.json")
        manual = self.load("minimal_manual_review_manifest.json")
        manual["next_bucket_counts"] = {}
        reference = self.load("minimal_reference_manifest.json")
        reference["review_status"] = "unreviewed"

        manifest = self.build(
            benchmark=benchmark,
            metric=metric,
            manual=manual,
            reference=reference,
        )

        self.assertEqual(manifest["decision_state"], "blocked_reference_quality")
        self.assertIn("reference_unreviewed", manifest["blocking_gates"])
        self.assertEqual(validator.validate_manifest(manifest), [])

    def test_stale_reference_version_blocks_before_default_decision(self):
        benchmark = self.load("minimal_benchmark_run_manifest.json")
        benchmark["benchmark_kind"] = "product_path_final"
        benchmark["product_path"] = True
        metric = self.load("complete_user_impact_metric_summary.json")
        manual = self.load("minimal_manual_review_manifest.json")
        manual["next_bucket_counts"] = {}
        reference = self.load("minimal_reference_manifest.json")
        reference["reference_version"] = "new-reviewed-reference-v2"

        manifest = self.build(
            benchmark=benchmark,
            metric=metric,
            manual=manual,
            reference=reference,
        )

        self.assertEqual(manifest["decision_state"], "blocked_reference_quality")
        self.assertIn("stale_reference_version", manifest["blocking_gates"])
        self.assertEqual(validator.validate_manifest(manifest), [])

    def test_incomplete_manual_review_blocks(self):
        manual = self.load("minimal_manual_review_manifest.json")
        manual["complete"] = False

        manifest = self.build(manual=manual)

        self.assertEqual(manifest["decision_state"], "blocked_manual_review")
        self.assertEqual(validator.validate_manifest(manifest), [])

    def test_quality_sanity_failure_is_rejected(self):
        metric = self.load("minimal_metric_summary.json")
        metric["weighted_cer"] = 0.71
        manual = self.load("minimal_manual_review_manifest.json")
        manual["next_bucket_counts"] = {}

        manifest = self.build(metric=metric, manual=manual)

        self.assertEqual(manifest["decision_state"], "rejected")
        self.assertIn("quality_sanity_failed", manifest["blocking_gates"])
        self.assertIn("sanity ceiling", " ".join(manifest["reasons"]))
        self.assertEqual(validator.validate_manifest(manifest), [])

    def test_default_sanity_cap_allows_mid_cer_for_regression_gate(self):
        benchmark = self.load("minimal_benchmark_run_manifest.json")
        benchmark["benchmark_kind"] = "product_path_final"
        benchmark["product_path"] = True
        metric = self.load("complete_user_impact_metric_summary.json")
        metric["weighted_cer"] = 0.58
        manual = self.load("minimal_manual_review_manifest.json")
        manual["next_bucket_counts"] = {}
        readiness = self.reference_readiness_report()
        regression = self.regression_report()

        manifest = self.build(
            benchmark=benchmark,
            metric=metric,
            manual=manual,
            readiness=readiness,
            regression=regression,
        )

        self.assertEqual(manifest["decision_state"], "default_allowed")
        self.assertNotIn("quality_sanity_failed", manifest["blocking_gates"])
        self.assertEqual(validator.validate_manifest(manifest), [])

    def test_cli_sanity_cer_cap_override_rejects_mid_cer(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            metric = self.load("minimal_metric_summary.json")
            metric["weighted_cer"] = 0.58
            manual = self.load("minimal_manual_review_manifest.json")
            manual["next_bucket_counts"] = {}
            self.write_inputs(root, metric=metric, manual=manual)
            args = self.args(root)
            args.sanity_cer_cap = 0.55

            result = gate.run(args)

            written = json.loads(result["output_path"].read_text(encoding="utf-8"))
            self.assertEqual(written["decision_state"], "rejected")
            self.assertIn("quality_sanity_failed", written["blocking_gates"])
            self.assertIn("sanity ceiling=0.5500", " ".join(written["reasons"]))
            self.assertEqual(validator.validate_manifest(written), [])

    def test_parse_args_accepts_sanity_cap_and_deprecated_alias(self):
        args = self.parse_required_args("--sanity-cer-cap", "0.58")
        legacy_args = self.parse_required_args("--weighted-cer-threshold", "0.66")

        self.assertEqual(args.sanity_cer_cap, 0.58)
        self.assertEqual(legacy_args.sanity_cer_cap, 0.66)

    def test_explicit_sanity_cap_wins_over_deprecated_alias(self):
        # 둘 다 주면 명시적 --sanity-cer-cap이 deprecated alias를 이겨야 한다
        # (deprecated가 덮어쓰던 회귀 방지).
        args = self.parse_required_args(
            "--sanity-cer-cap", "0.80", "--weighted-cer-threshold", "0.60"
        )
        self.assertEqual(args.sanity_cer_cap, 0.80)

    def test_sidecar_unavailable_stays_research_only(self):
        engine = self.load("minimal_engine_manifest.json")
        engine["engine_id"] = "nemotron_mlx_sidecar"
        engine["requires_sidecar"] = True
        metric = self.load("minimal_metric_summary.json")
        metric["sidecar_unavailable_count"] = 1
        manual = self.load("minimal_manual_review_manifest.json")
        manual["next_bucket_counts"] = {}

        manifest = self.build(engine=engine, metric=metric, manual=manual)

        self.assertEqual(manifest["decision_state"], "research_only")
        self.assertIn("sidecar_unavailable", manifest["blocking_gates"])
        self.assertEqual(validator.validate_manifest(manifest), [])

    def test_unavailable_engine_stays_research_only(self):
        benchmark = self.load("minimal_benchmark_run_manifest.json")
        benchmark["benchmark_kind"] = "product_path_final"
        benchmark["product_path"] = True
        metric = self.load("complete_user_impact_metric_summary.json")
        manual = self.load("minimal_manual_review_manifest.json")
        manual["next_bucket_counts"] = {}
        readiness = self.reference_readiness_report()
        engine = self.load("minimal_engine_manifest.json")
        engine["health_status"] = "skipped_unavailable"

        manifest = self.build(
            benchmark=benchmark,
            metric=metric,
            manual=manual,
            readiness=readiness,
            engine=engine,
        )

        self.assertEqual(manifest["decision_state"], "research_only")
        self.assertIn("engine_unavailable", manifest["blocking_gates"])
        self.assertFalse(manifest["eligible_for_default"])
        self.assertEqual(validator.validate_manifest(manifest), [])

    def test_healthy_sidecar_without_product_path_is_sidecar_candidate(self):
        engine = self.load("minimal_engine_manifest.json")
        engine["engine_id"] = "nemotron_mlx_sidecar"
        engine["requires_sidecar"] = True
        manual = self.load("minimal_manual_review_manifest.json")
        manual["next_bucket_counts"] = {}

        manifest = self.build(engine=engine, manual=manual)

        self.assertEqual(manifest["decision_state"], "sidecar_candidate")
        self.assertIn("product_path_missing", manifest["blocking_gates"])
        self.assertEqual(validator.validate_manifest(manifest), [])

    def test_product_path_without_user_impact_stays_experimental(self):
        benchmark = self.load("minimal_benchmark_run_manifest.json")
        benchmark["benchmark_kind"] = "product_path_final"
        benchmark["product_path"] = True
        manual = self.load("minimal_manual_review_manifest.json")
        manual["next_bucket_counts"] = {}

        manifest = self.build(benchmark=benchmark, manual=manual)

        self.assertEqual(manifest["decision_state"], "experimental_flag_only")
        self.assertIn("missing_user_impact_metric", manifest["blocking_gates"])
        self.assertEqual(validator.validate_manifest(manifest), [])

    def test_product_path_with_user_impact_requires_reference_readiness(self):
        benchmark = self.load("minimal_benchmark_run_manifest.json")
        benchmark["benchmark_kind"] = "product_path_final"
        benchmark["product_path"] = True
        metric = self.load("complete_user_impact_metric_summary.json")
        manual = self.load("minimal_manual_review_manifest.json")
        manual["next_bucket_counts"] = {}

        manifest = self.build(benchmark=benchmark, metric=metric, manual=manual)

        self.assertEqual(manifest["decision_state"], "blocked_reference_quality")
        self.assertIn("missing_reference_readiness_report", manifest["blocking_gates"])
        self.assertEqual(validator.validate_manifest(manifest), [])

    def test_product_path_with_user_impact_requires_regression_report(self):
        benchmark = self.load("minimal_benchmark_run_manifest.json")
        benchmark["benchmark_kind"] = "product_path_final"
        benchmark["product_path"] = True
        metric = self.load("complete_user_impact_metric_summary.json")
        manual = self.load("minimal_manual_review_manifest.json")
        manual["next_bucket_counts"] = {}
        readiness = self.reference_readiness_report()

        manifest = self.build(
            benchmark=benchmark,
            metric=metric,
            manual=manual,
            readiness=readiness,
        )

        self.assertEqual(manifest["decision_state"], "experimental_flag_only")
        self.assertIn("missing_regression_report", manifest["blocking_gates"])
        self.assertFalse(manifest["eligible_for_default"])
        self.assertEqual(validator.validate_manifest(manifest), [])

    def test_product_path_dry_run_cannot_be_default_allowed(self):
        benchmark = self.load("minimal_benchmark_run_manifest.json")
        benchmark["benchmark_kind"] = "product_path_final"
        benchmark["product_path"] = True
        benchmark["runner_contract"]["dry_run"] = True
        metric = self.load("complete_user_impact_metric_summary.json")
        manual = self.load("minimal_manual_review_manifest.json")
        manual["next_bucket_counts"] = {}
        readiness = self.reference_readiness_report()
        regression = self.regression_report()

        manifest = self.build(
            benchmark=benchmark,
            metric=metric,
            manual=manual,
            readiness=readiness,
            regression=regression,
        )

        self.assertEqual(manifest["decision_state"], "experimental_flag_only")
        self.assertIn("product_path_dry_run", manifest["blocking_gates"])
        self.assertFalse(manifest["eligible_for_default"])
        self.assertEqual(validator.validate_manifest(manifest), [])

    def test_product_path_with_user_impact_and_regression_can_be_default_allowed(self):
        benchmark = self.load("minimal_benchmark_run_manifest.json")
        benchmark["benchmark_kind"] = "product_path_final"
        benchmark["product_path"] = True
        metric = self.load("complete_user_impact_metric_summary.json")
        manual = self.load("minimal_manual_review_manifest.json")
        manual["next_bucket_counts"] = {}
        readiness = self.reference_readiness_report()
        regression = self.regression_report()

        manifest = self.build(
            benchmark=benchmark,
            metric=metric,
            manual=manual,
            readiness=readiness,
            regression=regression,
        )

        self.assertEqual(manifest["decision_state"], "default_allowed")
        self.assertTrue(manifest["eligible_for_default"])
        self.assertIn("reference_readiness_report", manifest)
        self.assertIn("regression_report", manifest)
        self.assertEqual(validator.validate_manifest(manifest), [])

    def _product_path_inputs(self):
        benchmark = self.load("minimal_benchmark_run_manifest.json")
        benchmark["benchmark_kind"] = "product_path_final"
        benchmark["product_path"] = True
        metric = self.load("complete_user_impact_metric_summary.json")
        manual = self.load("minimal_manual_review_manifest.json")
        manual["next_bucket_counts"] = {}
        return benchmark, metric, manual, self.reference_readiness_report()

    def test_tie_improvement_signal_is_experimental_only(self):
        # ADR 0004: CI 무승부면 regression 통과해도 제품 default 교체 안 함(현 default 유지).
        benchmark, metric, manual, readiness = self._product_path_inputs()
        regression = self.regression_report()
        regression["improvement_signal"] = "tie"
        manifest = self.build(
            benchmark=benchmark, metric=metric, manual=manual, readiness=readiness, regression=regression
        )
        self.assertEqual(manifest["decision_state"], "experimental_flag_only")
        self.assertIn("not_confident_improvement", manifest["blocking_gates"])

    def test_significant_improvement_signal_is_default_allowed(self):
        # CI 기준 확실한 개선이면 채택(default_allowed).
        benchmark, metric, manual, readiness = self._product_path_inputs()
        regression = self.regression_report()
        regression["improvement_signal"] = "significant_improvement"
        manifest = self.build(
            benchmark=benchmark, metric=metric, manual=manual, readiness=readiness, regression=regression
        )
        self.assertEqual(manifest["decision_state"], "default_allowed")

    def test_significant_regression_signal_is_rejected(self):
        # 확실한 악화(CI 분리)는 2pp 통과해도 rejected — 채택도 실험도 불가.
        benchmark, metric, manual, readiness = self._product_path_inputs()
        regression = self.regression_report()
        regression["improvement_signal"] = "significant_regression"
        manifest = self.build(
            benchmark=benchmark, metric=metric, manual=manual, readiness=readiness, regression=regression
        )
        self.assertEqual(manifest["decision_state"], "rejected")
        self.assertIn("candidate_regressed", manifest["blocking_gates"])

    def test_unknown_ci_signal_falls_back_to_default_allowed(self):
        # CI 없으면(unknown_ci) 기존 2pp 통과로 fallback → 채택(D-a2).
        benchmark, metric, manual, readiness = self._product_path_inputs()
        regression = self.regression_report()
        regression["improvement_signal"] = "unknown_ci"
        manifest = self.build(
            benchmark=benchmark, metric=metric, manual=manual, readiness=readiness, regression=regression
        )
        self.assertEqual(manifest["decision_state"], "default_allowed")

    def test_failed_regression_rejects_default_decision(self):
        benchmark = self.load("minimal_benchmark_run_manifest.json")
        benchmark["benchmark_kind"] = "product_path_final"
        benchmark["product_path"] = True
        metric = self.load("complete_user_impact_metric_summary.json")
        manual = self.load("minimal_manual_review_manifest.json")
        manual["next_bucket_counts"] = {}
        readiness = self.reference_readiness_report()
        regression = self.regression_report(regression_state="failed")
        regression["eligible_for_default_gate"] = False
        regression["blocking_gates"] = ["weighted_cer_regression"]
        regression["reasons"] = ["weighted CER delta exceeded threshold"]

        manifest = self.build(
            benchmark=benchmark,
            metric=metric,
            manual=manual,
            readiness=readiness,
            regression=regression,
        )

        self.assertEqual(manifest["decision_state"], "rejected")
        self.assertIn("regression_not_passed", manifest["blocking_gates"])
        self.assertIn("weighted_cer_regression", manifest["blocking_gates"])
        self.assertEqual(validator.validate_manifest(manifest), [])

    def test_not_ready_reference_readiness_blocks_default_decision(self):
        benchmark = self.load("minimal_benchmark_run_manifest.json")
        benchmark["benchmark_kind"] = "product_path_final"
        benchmark["product_path"] = True
        metric = self.load("complete_user_impact_metric_summary.json")
        manual = self.load("minimal_manual_review_manifest.json")
        manual["next_bucket_counts"] = {}
        readiness = self.reference_readiness_report(readiness_state="blocked_reference_review")
        readiness["eligible_for_default_gate"] = False
        readiness["blocking_gates"] = ["reference_unreviewed"]
        readiness["reasons"] = ["reference review is incomplete"]

        manifest = self.build(
            benchmark=benchmark,
            metric=metric,
            manual=manual,
            readiness=readiness,
        )

        self.assertEqual(manifest["decision_state"], "blocked_reference_quality")
        self.assertIn("reference_readiness_not_ready", manifest["blocking_gates"])
        self.assertIn("reference_unreviewed", manifest["blocking_gates"])
        self.assertEqual(validator.validate_manifest(manifest), [])

    def test_cli_writes_valid_decision_manifest(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self.write_inputs(root)

            result = gate.run(self.args(root))

            self.assertTrue(result["output_path"].exists())
            written = json.loads(result["output_path"].read_text(encoding="utf-8"))
            self.assertEqual(written["decision_state"], "experimental_flag_only")
            self.assertEqual(validator.validate_manifest(written), [])

    def reference_readiness_report(self, readiness_state="ready_for_default_gate"):
        return {
            "manifest_type": "reference_readiness_report",
            "schema_version": 1,
            "reference_version": "seed-smi-2026-06-12",
            "reference_manifest_path": "/tmp/reference.json",
            "readiness_state": readiness_state,
            "eligible_for_default_gate": readiness_state == "ready_for_default_gate",
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

    def regression_report(self, regression_state="passed"):
        return {
            "manifest_type": "regression_report",
            "schema_version": 1,
            "reference_version": "seed-smi-2026-06-12",
            "candidate_run_id": "candidate-run",
            "baseline_run_id": "baseline-run",
            "regression_state": regression_state,
            "eligible_for_default_gate": regression_state == "passed",
            "blocking_gates": [] if regression_state == "passed" else ["regression_not_passed"],
            "reasons": ["candidate is within regression thresholds"],
            "next_actions": ["Use this regression report as default-change evidence."],
            "thresholds": {
                "weighted_cer_regression_pp": 2.0,
                "empty_final_count_delta": 0.0,
                "timeout_count_delta": 0.0,
                "crash_count_delta": 0.0,
                "sidecar_unavailable_count_delta": 0.0,
                "permission_asset_failure_count_delta": 0.0,
            },
            "deltas": {
                "weighted_cer_pp": 0.0,
                "empty_final_count": 0.0,
                "timeout_count": 0.0,
                "crash_count": 0.0,
                "sidecar_unavailable_count": 0.0,
                "permission_asset_failure_count": 0.0,
            },
            "evidence_paths": [
                "/tmp/candidate_benchmark.json",
                "/tmp/candidate_metric.json",
                "/tmp/baseline_benchmark.json",
                "/tmp/baseline_metric.json",
            ],
        }


if __name__ == "__main__":
    unittest.main()
