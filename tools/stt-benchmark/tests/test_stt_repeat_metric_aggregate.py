import importlib
import math
import statistics
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "lib"
sys.path.insert(0, str(SCRIPTS))

aggregate_module = importlib.import_module("aggregate_stt_repeat_metric")
validator = importlib.import_module("validate_stt_benchmark_manifest")


def metric(weighted_cer, *, placeholder=False, macro_cer=None):
    return {
        "manifest_type": "metric_summary",
        "schema_version": 1,
        "sample_count": 0 if placeholder else 3,
        "weighted_cer": weighted_cer,
        "macro_cer": macro_cer if macro_cer is not None else weighted_cer,
        "empty_final_count": 0,
        "timeout_count": 0,
        "crash_count": 0,
        "metric_placeholder": placeholder,
        "metric_status": "ready" if placeholder else "measured",
    }


class AggregateRepeatMetricTests(unittest.TestCase):

    def test_multiple_measured_injects_mean_and_ci(self):
        metrics = [metric(0.30), metric(0.34), metric(0.38)]
        result = aggregate_module.aggregate(metrics)
        self.assertEqual(result["run_count"], 3)
        self.assertAlmostEqual(result["weighted_cer"], 0.34)
        expected_std = statistics.stdev([0.30, 0.34, 0.38])
        self.assertAlmostEqual(result["cer_std"], expected_std)
        # df=2 → t=4.303 (정규 1.96 아님): t분포 임계값으로 CI를 검증해 회귀 차단.
        expected_ci = 4.303 * expected_std / math.sqrt(3)
        self.assertAlmostEqual(result["cer_ci95_half_width"], expected_ci)
        self.assertEqual(validator.validate_manifest(result), [])

    def test_single_measurement_has_no_ci(self):
        result = aggregate_module.aggregate([metric(0.30)])
        self.assertEqual(result["run_count"], 1)
        self.assertAlmostEqual(result["weighted_cer"], 0.30)
        self.assertNotIn("cer_std", result)
        self.assertNotIn("cer_ci95_half_width", result)
        self.assertEqual(validator.validate_manifest(result), [])

    def test_placeholder_runs_excluded_from_aggregation(self):
        # 실패 런(placeholder, CER=1.0)이 평균을 오염시키면 안 된다.
        metrics = [metric(0.30), metric(1.0, placeholder=True), metric(0.34)]
        result = aggregate_module.aggregate(metrics)
        self.assertEqual(result["run_count"], 2)
        self.assertAlmostEqual(result["weighted_cer"], 0.32)
        self.assertFalse(result.get("metric_placeholder"))

    def test_all_placeholder_keeps_placeholder_and_no_ci(self):
        metrics = [metric(1.0, placeholder=True), metric(1.0, placeholder=True)]
        result = aggregate_module.aggregate(metrics)
        self.assertEqual(result["run_count"], 0)
        self.assertTrue(result["metric_placeholder"])
        self.assertNotIn("cer_ci95_half_width", result)
        self.assertEqual(validator.validate_manifest(result), [])

    def test_ci_exceeding_unit_interval_is_suppressed(self):
        # N=2 고분산: t(df=1)=12.706 → CI 반너비가 1.0을 넘는다. clamp 금지, 보수적 강등.
        metrics = [metric(0.10), metric(0.90)]
        result = aggregate_module.aggregate(metrics)
        self.assertEqual(result["run_count"], 2)
        self.assertAlmostEqual(result["weighted_cer"], 0.50)
        self.assertNotIn("cer_ci95_half_width", result)
        self.assertEqual(result["ci_suppressed_reason"], "ci_half_width_exceeds_unit_interval")
        # 스키마(require_ratio)가 거부하지 않도록 CI 필드가 빠진 채로 유효해야 한다.
        self.assertEqual(validator.validate_manifest(result), [])

    def test_empty_metrics_raises(self):
        with self.assertRaises(ValueError):
            aggregate_module.aggregate([])


if __name__ == "__main__":
    unittest.main()
