import importlib
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "lib"
sys.path.insert(0, str(SCRIPTS))

verdict = importlib.import_module("stt_engine_verdict")


class RankWithTiesTests(unittest.TestCase):

    def test_clear_separation_no_ties(self):
        # CI가 안 겹치면 각자 다른 tie_group(확실한 우열).
        entries = [
            {"engine_id": "a", "cer_mean": 0.30, "cer_ci95_half_width": 0.01},
            {"engine_id": "b", "cer_mean": 0.40, "cer_ci95_half_width": 0.01},
            {"engine_id": "c", "cer_mean": 0.50, "cer_ci95_half_width": 0.01},
        ]
        ranked = verdict.rank_with_ties(entries)
        self.assertEqual([r["engine_id"] for r in ranked], ["a", "b", "c"])
        self.assertEqual([r["tie_group"] for r in ranked], [1, 2, 3])

    def test_overlapping_ci_are_tied(self):
        # a(0.30±0.05=0.25~0.35), b(0.34±0.05=0.29~0.39) → 겹침 → 무승부.
        # c(0.60±0.02) → 분리.
        entries = [
            {"engine_id": "a", "cer_mean": 0.30, "cer_ci95_half_width": 0.05},
            {"engine_id": "b", "cer_mean": 0.34, "cer_ci95_half_width": 0.05},
            {"engine_id": "c", "cer_mean": 0.60, "cer_ci95_half_width": 0.02},
        ]
        ranked = verdict.rank_with_ties(entries)
        groups = {r["engine_id"]: r["tie_group"] for r in ranked}
        self.assertEqual(groups["a"], groups["b"])  # 무승부
        self.assertNotEqual(groups["a"], groups["c"])  # c는 분리

    def test_transitive_tie_grouping(self):
        # a~b 겹치고 b~c 겹치면 a,b,c 모두 같은 그룹(전이적).
        entries = [
            {"engine_id": "a", "cer_mean": 0.30, "cer_ci95_half_width": 0.03},
            {"engine_id": "b", "cer_mean": 0.34, "cer_ci95_half_width": 0.03},
            {"engine_id": "c", "cer_mean": 0.38, "cer_ci95_half_width": 0.03},
        ]
        ranked = verdict.rank_with_ties(entries)
        self.assertEqual(len({r["tie_group"] for r in ranked}), 1)

    def test_mixed_ci_present_and_absent_can_tie(self):
        # CI 없는 엔진(점구간)이 CI 있는 엔진의 구간과 겹치면 무승부로 묶인다.
        # 의도: CI 없는(불확실한) 엔진은 확실한 우위를 주장할 수 없으므로 보수적으로 무승부.
        entries = [
            {"engine_id": "x", "cer_mean": 0.30},  # CI 없음 → 점구간 0.30
            {"engine_id": "y", "cer_mean": 0.31, "cer_ci95_half_width": 0.02},  # 0.29~0.33, x 포함
        ]
        ranking = verdict.rank_with_ties(entries)
        groups = {r["engine_id"]: r["tie_group"] for r in ranking}
        self.assertEqual(groups["x"], groups["y"])

    def test_excludes_missing_mean(self):
        entries = [
            {"engine_id": "a", "cer_mean": 0.30, "cer_ci95_half_width": 0.01},
            {"engine_id": "b", "cer_mean": None, "cer_ci95_half_width": 0.01},
        ]
        ranked = verdict.rank_with_ties(entries)
        self.assertEqual([r["engine_id"] for r in ranked], ["a"])

    def test_overlap_detected_when_later_engine_has_wide_ci(self):
        # lower 역전: b.mean이 더 크지만 half가 커서 b.lower(0.22) < a.lower(0.29).
        # cer_mean 정렬 하에서는 lower<=group_upper 단일 조건으로도 겹침을 놓치지 않음.
        entries = [
            {"engine_id": "a", "cer_mean": 0.30, "cer_ci95_half_width": 0.01},
            {"engine_id": "b", "cer_mean": 0.34, "cer_ci95_half_width": 0.12},
        ]
        ranked = verdict.rank_with_ties(entries)
        self.assertEqual(ranked[0]["tie_group"], ranked[1]["tie_group"])

    def test_empty_entries(self):
        self.assertEqual(verdict.rank_with_ties([]), [])

    def test_single_engine(self):
        ranked = verdict.rank_with_ties(
            [{"engine_id": "a", "cer_mean": 0.30, "cer_ci95_half_width": 0.01}]
        )
        self.assertEqual(ranked[0]["rank"], 1)
        self.assertEqual(ranked[0]["tie_group"], 1)


class SignificantImprovementTests(unittest.TestCase):

    def test_clear_improvement_true(self):
        # 후보 0.30±0.02(상단 0.32) < 기준 0.40±0.02(하단 0.38) → 확실히 우수.
        candidate = {"cer_mean": 0.30, "cer_ci95_half_width": 0.02}
        baseline = {"cer_mean": 0.40, "cer_ci95_half_width": 0.02}
        self.assertTrue(verdict.is_significant_improvement(candidate, baseline))

    def test_overlapping_ci_not_significant(self):
        # 후보 0.34±0.05(상단 0.39) vs 기준 0.36±0.05(하단 0.31) → 겹침 → 교체 안 함.
        candidate = {"cer_mean": 0.34, "cer_ci95_half_width": 0.05}
        baseline = {"cer_mean": 0.36, "cer_ci95_half_width": 0.05}
        self.assertFalse(verdict.is_significant_improvement(candidate, baseline))

    def test_missing_ci_is_conservative_false(self):
        # CI 없으면(단일 측정 등) 확실하지 않으므로 교체 안 함(후보 쪽 None).
        candidate = {"cer_mean": 0.30, "cer_ci95_half_width": None}
        baseline = {"cer_mean": 0.40, "cer_ci95_half_width": 0.02}
        self.assertFalse(verdict.is_significant_improvement(candidate, baseline))

    def test_missing_baseline_ci_is_conservative_false(self):
        # 기준 쪽 CI가 None이어도 보수적으로 False.
        candidate = {"cer_mean": 0.30, "cer_ci95_half_width": 0.02}
        baseline = {"cer_mean": 0.40, "cer_ci95_half_width": None}
        self.assertFalse(verdict.is_significant_improvement(candidate, baseline))

    def test_touching_ci_not_significant(self):
        # 상단 == 하단(맞닿음)은 엄격 부등호라 False(완전 분리만 인정).
        # 0.2+0.1 과 0.4-0.1 은 둘 다 0.30000000000000004 로 동일(부동소수점 일치).
        candidate = {"cer_mean": 0.2, "cer_ci95_half_width": 0.1}  # 상단 0.2+0.1
        baseline = {"cer_mean": 0.4, "cer_ci95_half_width": 0.1}  # 하단 0.4-0.1
        self.assertEqual(candidate["cer_mean"] + candidate["cer_ci95_half_width"],
                         baseline["cer_mean"] - baseline["cer_ci95_half_width"])
        self.assertFalse(verdict.is_significant_improvement(candidate, baseline))


if __name__ == "__main__":
    unittest.main()
