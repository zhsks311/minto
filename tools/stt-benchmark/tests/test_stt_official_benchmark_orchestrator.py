import importlib
import json
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "lib"
sys.path.insert(0, str(SCRIPTS))

orchestrator = importlib.import_module("run_stt_official_benchmark")


def make_config(tmp, **overrides):
    base = [
        "--engines", "whisper_accurate,speech_analyzer",
        "--baseline-engine", "whisper_accurate",
        "--reference-version", "seed-smi-2026-06-12",
        "--reference-manifest", str(tmp / "reference_manifest.json"),
        "--manual-review-manifest", str(tmp / "manual_review.json"),
        "--output-root", str(tmp / "out"),
        "--repeats", "3",
        "--transcribe-cmd", "python3 /fake/transcribe.py",
    ]
    argv = list(base)
    for key, value in overrides.items():
        # 값이 ""이면 store_true 같은 무인자 플래그로 취급한다.
        argv += [key] if value == "" else [key, value]
    return orchestrator.Config(orchestrator.parse_args(argv))


def flag_value(command, name):
    for index, token in enumerate(command):
        if token == name:
            return command[index + 1]
    return None


def flag_values(command, name):
    return [command[i + 1] for i, token in enumerate(command) if token == name]


class CandidateResolutionTests(unittest.TestCase):

    def test_auto_selects_single_non_baseline(self):
        engine = orchestrator.resolve_candidate_engine(
            ["whisper_accurate", "speech_analyzer"], "whisper_accurate", None
        )
        self.assertEqual(engine, "speech_analyzer")

    def test_explicit_must_be_in_engines(self):
        with self.assertRaises(SystemExit):
            orchestrator.resolve_candidate_engine(["a", "b"], "a", "c")

    def test_ambiguous_requires_explicit(self):
        with self.assertRaises(SystemExit):
            orchestrator.resolve_candidate_engine(["a", "b", "c"], "a", None)


class CommandBuilderTests(unittest.TestCase):

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name)
        self.config = make_config(self.tmp)

    def tearDown(self):
        self._tmp.cleanup()

    def test_pipeline_command_uses_transcribe_cmd_and_carries_dry_run(self):
        self.config.dry_run = True
        command = orchestrator.pipeline_command(self.config, "speech_analyzer", 2)
        # 외부 주입 러너가 명령 앞에 온다.
        self.assertEqual(command[:2], ["python3", "/fake/transcribe.py"])
        self.assertIn("--dry-run", command)
        self.assertEqual(flag_value(command, "--engines"), "speech_analyzer")
        self.assertTrue(flag_value(command, "--output-root").endswith("transcribe/speech_analyzer/rep2"))

    def test_pipeline_passes_samples_and_max_windows(self):
        config = make_config(self.tmp, **{"--samples": "본회의_20260428", "--max-windows": "5"})
        command = orchestrator.pipeline_command(config, "whisper_accurate", 1)
        self.assertEqual(flag_value(command, "--samples"), "본회의_20260428")
        self.assertEqual(flag_value(command, "--max-windows"), "5")

    def test_pipeline_omits_samples_and_max_windows_by_default(self):
        command = orchestrator.pipeline_command(self.config, "whisper_accurate", 1)
        self.assertIsNone(flag_value(command, "--samples"))
        self.assertIsNone(flag_value(command, "--max-windows"))

    def test_convert_omits_product_path_by_default(self):
        # 기본은 비교/랭킹(realistic CER) — product_path 미적용.
        baseline = orchestrator.convert_command(self.config, "whisper_accurate", 1)
        candidate = orchestrator.convert_command(self.config, "speech_analyzer", 1)
        self.assertNotIn("--product-path", baseline)
        self.assertNotIn("--product-path", candidate)
        self.assertNotIn("--product-path", orchestrator.pipeline_command(self.config, "whisper_accurate", 1))
        self.assertEqual(flag_value(baseline, "--reference-version"), "seed-smi-2026-06-12")

    def test_product_path_enables_for_all(self):
        # adoption opt-in: --product-path는 pipeline·convert 전 엔진에 적용.
        config = make_config(self.tmp, **{"--product-path": ""})
        baseline = orchestrator.convert_command(config, "whisper_accurate", 1)
        candidate = orchestrator.convert_command(config, "speech_analyzer", 1)
        self.assertIn("--product-path", baseline)
        self.assertIn("--product-path", candidate)
        self.assertIn("--product-path", orchestrator.pipeline_command(config, "whisper_accurate", 1))

    def test_aggregate_command_passes_all_metrics(self):
        metrics = [self.tmp / f"m{i}.json" for i in range(3)]
        command = orchestrator.aggregate_command(self.config, "speech_analyzer", metrics)
        self.assertEqual(len(flag_values(command, "--metric-summary")), 3)
        self.assertTrue(flag_value(command, "--output").endswith("aggregate/speech_analyzer/metric_summary.json"))

    def test_regression_command_wires_candidate_vs_baseline(self):
        candidate = {"benchmark": Path("cb"), "metric": Path("cm"), "engine": Path("ce")}
        baseline = {"benchmark": Path("bb"), "metric": Path("bm"), "engine": Path("be")}
        command = orchestrator.regression_command(self.config, candidate, baseline)
        self.assertEqual(flag_value(command, "--candidate-metric-summary"), "cm")
        self.assertEqual(flag_value(command, "--baseline-metric-summary"), "bm")

    def test_decision_command_uses_sanity_cap_and_regression_report(self):
        candidate = {"benchmark": Path("cb"), "metric": Path("cm"), "engine": Path("ce")}
        command = orchestrator.decision_command(self.config, candidate)
        self.assertEqual(flag_value(command, "--sanity-cer-cap"), "0.7")
        self.assertTrue(flag_value(command, "--regression-report").endswith("regression/regression_report.json"))


def fake_invoke_factory(invoked_labels, alias_map=None):
    """convert/pipeline/... 산출물을 흉내 내 배선·순서만 검증하는 가짜 실행기.

    convert의 bundle engine_id는 경로(bundle/<engine>/rep<k>)에서 raw engine을 읽어
    alias_map으로 canonical 변환해 정한다 — 실제 convert가 alias를 적용하는 것과 같다.
    """
    alias_map = alias_map or {}

    def fake_invoke(command):
        out_root = flag_value(command, "--output-root") or ""
        # 전사 러너는 외부 주입(--transcribe-cmd)이라 스크립트명이 임의다. output-root의
        # /transcribe/로 식별한다.
        if "/transcribe/" in out_root:
            invoked_labels.append("transcribe")
            out = Path(out_root)
            out.mkdir(parents=True, exist_ok=True)
            (out / "pipeline_manifest.json").write_text("{}", encoding="utf-8")
            return
        script_name = Path(command[1]).name
        invoked_labels.append(script_name)
        if script_name == "convert_stt_pipeline_to_official_bundle.py":
            out = Path(flag_value(command, "--output-root"))
            raw_engine = out.parent.name  # bundle/<engine>/rep<k> → <engine>
            engine = alias_map.get(raw_engine, raw_engine)
            run_dir = out / f"{engine}_run1"
            run_dir.mkdir(parents=True, exist_ok=True)
            for fname in ["benchmark_run_manifest.json", "metric_summary.json", "engine_manifest.json"]:
                (run_dir / fname).write_text("{}", encoding="utf-8")
            manifest = {
                "runs": [{
                    "engine_id": engine,
                    "benchmark_run_manifest": f"{engine}_run1/benchmark_run_manifest.json",
                    "metric_summary": f"{engine}_run1/metric_summary.json",
                    "engine_manifest": f"{engine}_run1/engine_manifest.json",
                }]
            }
            (out / "engine_run_bundle_manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
        elif script_name == "aggregate_stt_repeat_metric.py":
            out = Path(flag_value(command, "--output"))
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_text("{}", encoding="utf-8")
        elif script_name == "build_stt_engine_lane_matrix.py":
            out = Path(flag_value(command, "--output-root"))
            out.mkdir(parents=True, exist_ok=True)
            (out / "engine_lane_matrix.json").write_text("{}", encoding="utf-8")
        elif script_name == "run_stt_regression_gate.py":
            out = Path(flag_value(command, "--output-root"))
            out.mkdir(parents=True, exist_ok=True)
            (out / "regression_report.json").write_text("{}", encoding="utf-8")
        elif script_name == "run_stt_benchmark_decision_gate.py":
            out = Path(flag_value(command, "--output-root"))
            out.mkdir(parents=True, exist_ok=True)
            (out / "official_stt_decision_manifest.json").write_text("{}", encoding="utf-8")
        elif script_name == "render_stt_official_benchmark_report.py":
            out = Path(flag_value(command, "--output-root"))
            out.mkdir(parents=True, exist_ok=True)
            (out / "stt_official_benchmark_report.md").write_text("#", encoding="utf-8")

    return fake_invoke


class OrchestrationFlowTests(unittest.TestCase):

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name)
        self.config = make_config(self.tmp)

    def tearDown(self):
        self._tmp.cleanup()

    def test_full_flow_invokes_every_stage_in_order(self):
        invoked = []
        orchestrator.orchestrate(self.config, fake_invoke_factory(invoked))
        # 2 engines x 3 repeats x (pipeline+convert) = 12, +2 aggregate, +1 lane, +1 reg, +1 dec, +1 report
        self.assertEqual(invoked.count("transcribe"), 6)
        self.assertEqual(invoked.count("convert_stt_pipeline_to_official_bundle.py"), 6)
        self.assertEqual(invoked.count("aggregate_stt_repeat_metric.py"), 2)
        # 판정 단계가 전사·집계 뒤에 온다.
        self.assertLess(invoked.index("build_stt_engine_lane_matrix.py"), invoked.index("run_stt_regression_gate.py"))
        self.assertLess(invoked.index("run_stt_regression_gate.py"), invoked.index("run_stt_benchmark_decision_gate.py"))
        self.assertEqual(invoked[-1], "render_stt_official_benchmark_report.py")

    def test_analysis_only_without_transcribe_cmd_requires_existing_manifests(self):
        # --transcribe-cmd 없이는 전사를 못 하므로, 미리 만든 pipeline manifest가 없으면 명확히 실패.
        argv = [
            "--engines", "whisper_accurate,speech_analyzer",
            "--baseline-engine", "whisper_accurate",
            "--reference-version", "seed-smi-2026-06-12",
            "--reference-manifest", str(self.tmp / "ref.json"),
            "--manual-review-manifest", str(self.tmp / "manual.json"),
            "--output-root", str(self.tmp / "analysis_out"),
            "--repeats", "2",
        ]
        config = orchestrator.Config(orchestrator.parse_args(argv))
        self.assertIsNone(config.transcribe_cmd)
        with self.assertRaises(SystemExit):
            orchestrator.orchestrate(config, fake_invoke_factory([]))

    def test_aggregate_receives_n_metrics(self):
        captured = {}
        labels = []
        fake = fake_invoke_factory(labels)

        def spy(command):
            if Path(command[1]).name == "aggregate_stt_repeat_metric.py":
                captured.setdefault("counts", []).append(len(flag_values(command, "--metric-summary")))
            fake(command)

        orchestrator.orchestrate(self.config, spy)
        # 각 엔진 집계가 repeats(=3)개 metric을 받는다.
        self.assertEqual(captured["counts"], [3, 3])

    def test_skip_existing_skips_completed_steps(self):
        invoked = []
        orchestrator.orchestrate(self.config, fake_invoke_factory(invoked))
        first_count = len(invoked)
        # 두 번째 실행: 모든 산출물이 존재 → 아무 단계도 다시 실행되지 않는다.
        second = []
        orchestrator.orchestrate(self.config, fake_invoke_factory(second))
        self.assertGreater(first_count, 0)
        self.assertEqual(second, [])

    def test_no_skip_existing_reruns(self):
        invoked = []
        orchestrator.orchestrate(self.config, fake_invoke_factory(invoked))
        self.config.skip_existing = False
        rerun = []
        orchestrator.orchestrate(self.config, fake_invoke_factory(rerun))
        self.assertGreater(len(rerun), 0)

    def test_resume_after_bundle_removed_regenerates_without_error(self):
        import shutil
        orchestrator.orchestrate(self.config, fake_invoke_factory([]))
        # 번들이 정리된 상태로 재개: convert(출력=bundle manifest)가 재실행으로 복원하므로
        # specs 빌드가 막히지 않고 에러 없이 완주한다(convert만 다시 돌고 transcribe는 skip).
        shutil.rmtree(self.config.output_root / "bundle")
        resumed = []
        orchestrator.orchestrate(self.config, fake_invoke_factory(resumed))
        self.assertEqual(resumed.count("convert_stt_pipeline_to_official_bundle.py"), 6)
        self.assertNotIn("transcribe", resumed)

    def test_repeats_one_runs_single_metric_aggregate(self):
        config = make_config(self.tmp, **{"--repeats": "1"})
        counts = []
        labels = []
        fake = fake_invoke_factory(labels)

        def spy(command):
            if Path(command[1]).name == "aggregate_stt_repeat_metric.py":
                counts.append(len(flag_values(command, "--metric-summary")))
            fake(command)

        orchestrator.orchestrate(config, spy)
        self.assertEqual(counts, [1, 1])
        self.assertEqual(labels.count("transcribe"), 2)
        self.assertEqual(labels[-1], "render_stt_official_benchmark_report.py")

    def test_engine_alias_matches_canonical_id(self):
        # raw engine과 다른 canonical id로 bundle이 만들어져도 매칭/집계가 깨지지 않는다.
        alias_map = {"whisper_large_v3": "whisper_accurate"}
        argv = [
            "--engines", "whisper_large_v3,speech_analyzer",
            "--baseline-engine", "whisper_large_v3",
            "--engine-id-alias", "whisper_large_v3=whisper_accurate",
            "--reference-version", "seed-smi-2026-06-12",
            "--reference-manifest", str(self.tmp / "ref.json"),
            "--manual-review-manifest", str(self.tmp / "manual.json"),
            "--output-root", str(self.tmp / "alias_out"),
            "--repeats", "2",
            "--transcribe-cmd", "python3 /fake/transcribe.py",
        ]
        config = orchestrator.Config(orchestrator.parse_args(argv))
        labels = []
        # alias_map을 fake에 넘겨 bundle engine_id를 canonical로 만든다.
        orchestrator.orchestrate(config, fake_invoke_factory(labels, alias_map))
        self.assertEqual(labels[-1], "render_stt_official_benchmark_report.py")
        self.assertTrue((self.tmp / "alias_out" / "decision" / "official_stt_decision_manifest.json").exists())

    def test_single_engine_baseline_equals_candidate_raises(self):
        argv = [
            "--engines", "whisper_accurate",
            "--baseline-engine", "whisper_accurate",
            "--reference-version", "seed-smi-2026-06-12",
            "--reference-manifest", str(self.tmp / "ref.json"),
            "--manual-review-manifest", str(self.tmp / "manual.json"),
            "--output-root", str(self.tmp / "single_out"),
        ]
        with self.assertRaises(SystemExit):
            orchestrator.Config(orchestrator.parse_args(argv))


if __name__ == "__main__":
    unittest.main()
