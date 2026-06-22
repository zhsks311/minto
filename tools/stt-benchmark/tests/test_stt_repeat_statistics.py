import importlib
import math
import statistics
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "lib"
sys.path.insert(0, str(SCRIPTS))

stats = importlib.import_module("stt_repeat_statistics")


class STTRepeatStatisticsTests(unittest.TestCase):

    def test_empty_returns_all_none(self):
        result = stats.summarize_repeat_cers([])
        self.assertEqual(result["run_count"], 0)
        self.assertIsNone(result["cer_mean"])
        self.assertIsNone(result["cer_std"])
        self.assertIsNone(result["cer_ci95_half_width"])

    def test_single_measurement_has_no_variance(self):
        # 단일 측정은 분산을 알 수 없다(critic: 단일 측정 불신).
        result = stats.summarize_repeat_cers([0.30])
        self.assertEqual(result["run_count"], 1)
        self.assertAlmostEqual(result["cer_mean"], 0.30)
        self.assertIsNone(result["cer_std"])
        self.assertIsNone(result["cer_ci95_half_width"])

    def test_multiple_measurements_use_t_distribution_ci(self):
        values = [0.30, 0.34, 0.38]
        result = stats.summarize_repeat_cers(values)
        self.assertEqual(result["run_count"], 3)
        self.assertAlmostEqual(result["cer_mean"], 0.34)
        expected_std = statistics.stdev(values)
        self.assertAlmostEqual(result["cer_std"], expected_std)
        # df=2 → t=4.303 (정규 1.96 아님). CI 수치를 직접 검증해 회귀 차단.
        expected_ci = 4.303 * expected_std / math.sqrt(3)
        self.assertAlmostEqual(result["cer_ci95_half_width"], expected_ci, places=6)

    def test_n2_uses_high_t_critical(self):
        # N=2(df=1)는 t=12.706으로 극단적으로 넓은 CI를 정직하게 반환해야 한다.
        values = [0.30, 0.40]
        result = stats.summarize_repeat_cers(values)
        self.assertEqual(result["run_count"], 2)
        expected_ci = 12.706 * statistics.stdev(values) / math.sqrt(2)
        self.assertAlmostEqual(result["cer_ci95_half_width"], expected_ci, places=6)

    def test_non_numeric_and_bool_excluded(self):
        # None/bool/문자열은 측정 미완으로 제외(bool은 int 서브클래스 함정 방어).
        result = stats.summarize_repeat_cers([0.30, None, True, "x", 0.40])
        self.assertEqual(result["run_count"], 2)
        self.assertAlmostEqual(result["cer_mean"], 0.35)


if __name__ == "__main__":
    unittest.main()
