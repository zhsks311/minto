import importlib
import json
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "lib"
sys.path.insert(0, str(SCRIPTS))

regression = importlib.import_module("run_stt_regression_gate")
validator = importlib.import_module("validate_stt_benchmark_manifest")


class STTRegressionGateTests(unittest.TestCase):

    def test_improvement_signal_classifies_by_ci(self):
        # ADR 0004 배선: candidate/baseline CI로 개선확실/무승부/악화확실 분류, CI 없으면 unknown_ci.
        sig = regression.compute_improvement_signal
        self.assertEqual(
            sig({"weighted_cer": 0.30, "cer_ci95_half_width": 0.02},
                {"weighted_cer": 0.40, "cer_ci95_half_width": 0.02}),
            "significant_improvement",
        )
        self.assertEqual(
            sig({"weighted_cer": 0.34, "cer_ci95_half_width": 0.05},
                {"weighted_cer": 0.36, "cer_ci95_half_width": 0.05}),
            "tie",
        )
        self.assertEqual(
            sig({"weighted_cer": 0.40, "cer_ci95_half_width": 0.02},
                {"weighted_cer": 0.30, "cer_ci95_half_width": 0.02}),
            "significant_regression",
        )
        self.assertEqual(
            sig({"weighted_cer": 0.30}, {"weighted_cer": 0.40}),
            "unknown_ci",
        )

    def test_passes_when_candidate_is_within_thresholds(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            paths = self.write_inputs(root)

            result = regression.run(self.args(root, paths))

            report = result["payload"]
            self.assertEqual(report["regression_state"], "passed")
            self.assertTrue(report["eligible_for_default_gate"])
            self.assertAlmostEqual(report["deltas"]["weighted_cer_pp"], 1.0)
            self.assertEqual(validator.validate_manifest(report), [])

    def test_fails_when_weighted_cer_regresses_past_threshold(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            paths = self.write_inputs(root, candidate_metric=self.metric(weighted_cer=0.331))

            result = regression.run(self.args(root, paths))

            report = result["payload"]
            self.assertEqual(report["regression_state"], "failed")
            self.assertIn("weighted_cer_regression", report["blocking_gates"])
            self.assertFalse(report["eligible_for_default_gate"])
            self.assertEqual(validator.validate_manifest(report), [])

    def test_not_comparable_when_reference_version_differs(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            paths = self.write_inputs(
                root,
                baseline_benchmark=self.benchmark(run_id="baseline", reference_version="other-reference-v1"),
            )

            result = regression.run(self.args(root, paths))

            report = result["payload"]
            self.assertEqual(report["regression_state"], "not_comparable")
            self.assertIn("regression_not_comparable", report["blocking_gates"])
            self.assertFalse(report["eligible_for_default_gate"])
            self.assertEqual(validator.validate_manifest(report), [])

    def test_missing_baseline_blocks_default_gate(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            candidate_benchmark = root / "candidate_benchmark.json"
            candidate_metric = root / "candidate_metric.json"
            candidate_benchmark.write_text(json.dumps(self.benchmark(run_id="candidate")), encoding="utf-8")
            candidate_metric.write_text(json.dumps(self.metric(weighted_cer=0.31)), encoding="utf-8")

            result = regression.run(type("Args", (), {
                "candidate_benchmark_run_manifest": candidate_benchmark,
                "candidate_metric_summary": candidate_metric,
                "baseline_benchmark_run_manifest": None,
                "baseline_metric_summary": None,
                "output_root": root / "out",
                "weighted_cer_regression_pp": 2.0,
                "empty_final_count_delta": 0.0,
                "timeout_count_delta": 0.0,
                "crash_count_delta": 0.0,
                "sidecar_unavailable_count_delta": 0.0,
                "permission_asset_failure_count_delta": 0.0,
            })())

            report = result["payload"]
            self.assertEqual(report["regression_state"], "missing_baseline")
            self.assertIn("missing_regression_baseline", report["blocking_gates"])
            self.assertEqual(validator.validate_manifest(report), [])

    def write_inputs(
        self,
        root,
        candidate_benchmark=None,
        candidate_metric=None,
        baseline_benchmark=None,
        baseline_metric=None,
    ):
        paths = {
            "candidate_benchmark": root / "candidate_benchmark.json",
            "candidate_metric": root / "candidate_metric.json",
            "baseline_benchmark": root / "baseline_benchmark.json",
            "baseline_metric": root / "baseline_metric.json",
        }
        paths["candidate_benchmark"].write_text(
            json.dumps(candidate_benchmark or self.benchmark(run_id="candidate")),
            encoding="utf-8",
        )
        paths["candidate_metric"].write_text(
            json.dumps(candidate_metric or self.metric(weighted_cer=0.31)),
            encoding="utf-8",
        )
        paths["baseline_benchmark"].write_text(
            json.dumps(baseline_benchmark or self.benchmark(run_id="baseline")),
            encoding="utf-8",
        )
        paths["baseline_metric"].write_text(
            json.dumps(baseline_metric or self.metric(weighted_cer=0.30)),
            encoding="utf-8",
        )
        return paths

    def args(self, root, paths):
        return type("Args", (), {
            "candidate_benchmark_run_manifest": paths["candidate_benchmark"],
            "candidate_metric_summary": paths["candidate_metric"],
            "baseline_benchmark_run_manifest": paths["baseline_benchmark"],
            "baseline_metric_summary": paths["baseline_metric"],
            "output_root": root / "out",
            "weighted_cer_regression_pp": 2.0,
            "empty_final_count_delta": 0.0,
            "timeout_count_delta": 0.0,
            "crash_count_delta": 0.0,
            "sidecar_unavailable_count_delta": 0.0,
            "permission_asset_failure_count_delta": 0.0,
        })()

    def benchmark(self, run_id, reference_version="seed-smi-2026-06-12"):
        return {
            "manifest_type": "benchmark_run_manifest",
            "schema_version": 1,
            "run_id": run_id,
            "created_at": "2026-06-12T00:00:00+09:00",
            "benchmark_kind": "product_path_final",
            "product_path": True,
            "engine_id": "speech_analyzer",
            "engine_label": "SpeechAnalyzer",
            "model_id": "apple_speech_analyzer_ko_KR",
            "model_version": "fixture",
            "model_hash": "",
            "runtime": "apple_speech",
            "os_version": "fixture-os",
            "hardware": "fixture-hardware",
            "reference_version": reference_version,
            "sample_set": "fixture-set",
            "input_contract": {
                "sample_rate_hz": 16000,
                "channels": 1,
                "format": "wav",
            },
            "runner_contract": {
                "window_sec": 30.0,
                "max_gap_sec": 3.0,
                "audio_pad_sec": 0.5,
            },
            "output_paths": [],
        }

    def metric(self, weighted_cer):
        return {
            "manifest_type": "metric_summary",
            "schema_version": 1,
            "sample_count": 7,
            "weighted_cer": weighted_cer,
            "macro_cer": weighted_cer,
            "empty_final_count": 0,
            "timeout_count": 0,
            "crash_count": 0,
            "user_impact_metric_complete": False,
        }


if __name__ == "__main__":
    unittest.main()
