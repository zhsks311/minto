import importlib
import json
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "lib"
sys.path.insert(0, str(SCRIPTS))

matrix = importlib.import_module("build_stt_engine_lane_matrix")


class STTEngineLaneMatrixTests(unittest.TestCase):

    def test_engine_ranking_orders_by_weighted_cer_excluding_unmeasured(self):
        rows = [
            {"engine_id": "b", "weighted_cer": 0.40},
            {"engine_id": "a", "weighted_cer": 0.30},
            {"engine_id": "c", "weighted_cer": None},  # 측정 미완 → 순위 제외
            {"engine_id": "d", "weighted_cer": 0.30},  # a와 동률 → engine_id로 결정
        ]
        ranking = matrix.build_engine_ranking(rows)
        self.assertEqual(
            [(r["rank"], r["engine_id"]) for r in ranking],
            [(1, "a"), (2, "d"), (3, "b")],
        )

    def test_engine_ranking_dedups_multiple_rows_per_engine(self):
        # 같은 engine_id가 여러 lane으로 들어오면 최저(최선) weighted_cer 대표 1개만,
        # engine_id 빈값 row는 제외 → 엔진 단위 순위 보장(HIGH/LOW 회귀 방지).
        rows = [
            {"engine_id": "whisper", "weighted_cer": 0.25, "lane": "extended"},
            {"engine_id": "whisper", "weighted_cer": 0.20, "lane": "product"},
            {"engine_id": "nemotron", "weighted_cer": 0.22, "lane": "product"},
            {"engine_id": "", "weighted_cer": 0.10},
        ]
        ranking = matrix.build_engine_ranking(rows)
        self.assertEqual(
            [(r["rank"], r["engine_id"], r["weighted_cer"]) for r in ranking],
            [(1, "whisper", 0.20), (2, "nemotron", 0.22)],
        )

    def test_engine_ranking_uses_ci_for_ties_when_present(self):
        # 배선 검증: CI가 있으면 verdict의 무승부 판정이 ranking의 tie_group에 반영된다.
        # a(0.30±0.05=0.25~0.35), b(0.34±0.05=0.29~0.39) 겹침 → 무승부. c(0.60±0.02) 분리.
        rows = [
            {"engine_id": "a", "weighted_cer": 0.30, "cer_ci95_half_width": 0.05},
            {"engine_id": "b", "weighted_cer": 0.34, "cer_ci95_half_width": 0.05},
            {"engine_id": "c", "weighted_cer": 0.60, "cer_ci95_half_width": 0.02},
        ]
        ranking = matrix.build_engine_ranking(rows)
        groups = {r["engine_id"]: r["tie_group"] for r in ranking}
        self.assertEqual(groups["a"], groups["b"])  # CI 겹침 → 무승부
        self.assertNotEqual(groups["a"], groups["c"])  # 분리
        self.assertEqual(ranking[0]["weighted_cer"], 0.30)  # weighted_cer 보존

    def test_engine_ranking_without_ci_is_plain_order(self):
        # CI 없으면(단일 런) 무승부 없이 단순 순위 — 실측 전 호환.
        rows = [
            {"engine_id": "a", "weighted_cer": 0.30},
            {"engine_id": "b", "weighted_cer": 0.34},
        ]
        ranking = matrix.build_engine_ranking(rows)
        self.assertEqual([r["engine_id"] for r in ranking], ["a", "b"])
        self.assertNotEqual(ranking[0]["tie_group"], ranking[1]["tie_group"])

    def test_builds_lane_matrix_without_promoting_non_product_runs(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            offline = self.write_entry(root, "offline", self.benchmark(), self.metric(), self.engine())
            sidecar = self.write_entry(
                root,
                "sidecar",
                self.benchmark(engine_id="nemotron", benchmark_kind="sidecar_final", runtime="mlx_sidecar"),
                self.metric(weighted_cer=0.238),
                self.engine(engine_id="nemotron", runtime="mlx_sidecar", requires_sidecar=True, supports_streaming=True),
            )
            product = self.write_entry(
                root,
                "product",
                self.benchmark(engine_id="speech_analyzer", benchmark_kind="product_path_final", product_path=True),
                self.metric(user_impact_metric_complete=True),
                self.engine(),
            )

            result = matrix.run(type("Args", (), {
                "benchmark_run_manifest": [offline["benchmark"], sidecar["benchmark"], product["benchmark"]],
                "metric_summary": [offline["metric"], sidecar["metric"], product["metric"]],
                "engine_manifest": [offline["engine"], sidecar["engine"], product["engine"]],
                "output_root": root / "out",
            })())

            rows = result["payload"]["lanes"]
            by_engine_lane = {(row["engine_id"], row["lane"]): row for row in rows}

            self.assertEqual(result["payload"]["entry_count"], 3)
            self.assertFalse(by_engine_lane[("speech_analyzer", "offline_final")]["default_gate_input"])
            self.assertFalse(by_engine_lane[("nemotron", "sidecar_final")]["default_gate_input"])
            self.assertTrue(by_engine_lane[("speech_analyzer", "product_path_final")]["default_gate_input"])
            self.assertEqual(matrix.validator.validate_manifest(result["payload"]), [])
            self.assertTrue(result["json_path"].exists())
            self.assertIn("sidecar_final", result["md_path"].read_text(encoding="utf-8"))

    def test_builds_lane_matrix_from_run_bundle_manifest(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            offline = self.write_entry(root, "offline", self.benchmark(), self.metric(), self.engine())
            product = self.write_entry(
                root,
                "product",
                self.benchmark(engine_id="speech_analyzer", benchmark_kind="product_path_final", product_path=True),
                self.metric(user_impact_metric_complete=True),
                self.engine(),
            )
            bundle_path = root / "run_bundle.json"
            bundle_path.write_text(json.dumps({
                "manifest_type": "engine_run_bundle_manifest",
                "schema_version": 1,
                "reference_version": "fixture-reference-v1",
                "bundle_count": 2,
                "runs": [
                    {
                        "engine_id": "speech_analyzer",
                        "benchmark_run_manifest": str(offline["benchmark"].relative_to(root)),
                        "metric_summary": str(offline["metric"].relative_to(root)),
                        "engine_manifest": str(offline["engine"].relative_to(root)),
                    },
                    {
                        "engine_id": "speech_analyzer",
                        "benchmark_run_manifest": str(product["benchmark"].relative_to(root)),
                        "metric_summary": str(product["metric"].relative_to(root)),
                        "engine_manifest": str(product["engine"].relative_to(root)),
                    },
                ],
            }), encoding="utf-8")

            result = matrix.run(type("Args", (), {
                "run_bundle_manifest": [bundle_path],
                "benchmark_run_manifest": [],
                "metric_summary": [],
                "engine_manifest": [],
                "output_root": root / "out",
            })())

            rows = result["payload"]["lanes"]
            by_lane = {row["lane"]: row for row in rows}

            self.assertEqual(result["payload"]["entry_count"], 2)
            self.assertFalse(by_lane["offline_final"]["default_gate_input"])
            self.assertTrue(by_lane["product_path_final"]["default_gate_input"])
            self.assertIn("run_bundle_manifest", rows[0]["source_paths"])
            self.assertEqual(matrix.validator.validate_manifest(result["payload"]), [])

    def test_rejects_mixed_reference_versions(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            first = self.write_entry(root, "first", self.benchmark(), self.metric(), self.engine())
            second = self.write_entry(
                root,
                "second",
                self.benchmark(engine_id="whisperkit", reference_version="other-reference-v1"),
                self.metric(),
                self.engine(engine_id="whisperkit"),
            )

            with self.assertRaises(SystemExit) as context:
                matrix.build_matrix(type("Args", (), {
                    "benchmark_run_manifest": [first["benchmark"], second["benchmark"]],
                    "metric_summary": [first["metric"], second["metric"]],
                    "engine_manifest": [first["engine"], second["engine"]],
                    "output_root": root / "out",
                })())

            self.assertIn("exactly one reference version", str(context.exception))

    def test_unavailable_engine_is_not_default_gate_input(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            product = self.write_entry(
                root,
                "product",
                self.benchmark(engine_id="speech_analyzer", benchmark_kind="product_path_final", product_path=True),
                self.metric(user_impact_metric_complete=True),
                self.engine(health_status="skipped_unavailable"),
            )

            result = matrix.run(type("Args", (), {
                "benchmark_run_manifest": [product["benchmark"]],
                "metric_summary": [product["metric"]],
                "engine_manifest": [product["engine"]],
                "output_root": root / "out",
            })())

            row = result["payload"]["lanes"][0]
            self.assertEqual(row["health_status"], "skipped_unavailable")
            self.assertFalse(row["default_gate_input"])
            self.assertEqual(matrix.validator.validate_manifest(result["payload"]), [])

    def test_product_path_dry_run_is_not_default_gate_input(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            benchmark = self.benchmark(
                engine_id="speech_analyzer",
                benchmark_kind="product_path_final",
                product_path=True,
            )
            benchmark["runner_contract"]["dry_run"] = True
            product = self.write_entry(
                root,
                "product",
                benchmark,
                self.metric(user_impact_metric_complete=True),
                self.engine(),
            )

            result = matrix.run(type("Args", (), {
                "benchmark_run_manifest": [product["benchmark"]],
                "metric_summary": [product["metric"]],
                "engine_manifest": [product["engine"]],
                "output_root": root / "out",
            })())

            row = result["payload"]["lanes"][0]
            self.assertEqual(row["lane"], "product_path_final")
            self.assertFalse(row["default_gate_input"])
            self.assertEqual(matrix.validator.validate_manifest(result["payload"]), [])

    def test_rejects_bundle_reference_version_mismatch(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            entry = self.write_entry(root, "offline", self.benchmark(), self.metric(), self.engine())
            bundle_path = root / "run_bundle.json"
            bundle_path.write_text(json.dumps({
                "manifest_type": "engine_run_bundle_manifest",
                "schema_version": 1,
                "reference_version": "other-reference-v1",
                "bundle_count": 1,
                "runs": [
                    {
                        "engine_id": "speech_analyzer",
                        "benchmark_run_manifest": str(entry["benchmark"].relative_to(root)),
                        "metric_summary": str(entry["metric"].relative_to(root)),
                        "engine_manifest": str(entry["engine"].relative_to(root)),
                    },
                ],
            }), encoding="utf-8")

            with self.assertRaises(SystemExit) as context:
                matrix.build_matrix(type("Args", (), {
                    "run_bundle_manifest": [bundle_path],
                    "benchmark_run_manifest": [],
                    "metric_summary": [],
                    "engine_manifest": [],
                    "output_root": root / "out",
                })())

            self.assertIn("bundle reference_version", str(context.exception))

    def test_rejects_benchmark_and_engine_manifest_id_mismatch(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            entry = self.write_entry(
                root,
                "offline",
                self.benchmark(engine_id="speech_analyzer"),
                self.metric(),
                self.engine(engine_id="whisperkit"),
            )

            with self.assertRaises(SystemExit) as context:
                matrix.build_matrix(type("Args", (), {
                    "benchmark_run_manifest": [entry["benchmark"]],
                    "metric_summary": [entry["metric"]],
                    "engine_manifest": [entry["engine"]],
                    "output_root": root / "out",
                })())

            self.assertIn("engine_id mismatch", str(context.exception))

    def test_manifest_counts_must_match(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            entry = self.write_entry(root, "offline", self.benchmark(), self.metric(), self.engine())

            with self.assertRaises(SystemExit) as context:
                matrix.build_matrix(type("Args", (), {
                    "benchmark_run_manifest": [entry["benchmark"]],
                    "metric_summary": [],
                    "engine_manifest": [entry["engine"]],
                    "output_root": root / "out",
                })())

            self.assertIn("counts must match", str(context.exception))

    def write_entry(self, root, name, benchmark, metric, engine):
        directory = root / name
        directory.mkdir()
        paths = {
            "benchmark": directory / "benchmark.json",
            "metric": directory / "metric.json",
            "engine": directory / "engine.json",
        }
        paths["benchmark"].write_text(json.dumps(benchmark), encoding="utf-8")
        paths["metric"].write_text(json.dumps(metric), encoding="utf-8")
        paths["engine"].write_text(json.dumps(engine), encoding="utf-8")
        return paths

    def benchmark(
        self,
        engine_id="speech_analyzer",
        benchmark_kind="offline_final",
        product_path=False,
        runtime="apple_speech",
        reference_version="fixture-reference-v1",
    ):
        return {
            "manifest_type": "benchmark_run_manifest",
            "schema_version": 1,
            "run_id": f"{engine_id}-{benchmark_kind}",
            "created_at": "2026-06-12T00:00:00+09:00",
            "benchmark_kind": benchmark_kind,
            "product_path": product_path,
            "engine_id": engine_id,
            "engine_label": engine_id,
            "model_id": f"{engine_id}-model",
            "model_version": "fixture",
            "model_hash": "",
            "runtime": runtime,
            "os_version": "fixture-os",
            "hardware": "fixture-hardware",
            "reference_version": reference_version,
            "sample_set": "fixture-set",
            "input_contract": {},
            "runner_contract": {},
            "output_paths": [],
        }

    def metric(self, weighted_cer=0.307, user_impact_metric_complete=False):
        payload = {
            "manifest_type": "metric_summary",
            "schema_version": 1,
            "sample_count": 7,
            "weighted_cer": weighted_cer,
            "macro_cer": weighted_cer,
            "empty_final_count": 0,
            "timeout_count": 0,
            "crash_count": 0,
            "user_impact_metric_complete": user_impact_metric_complete,
        }
        if user_impact_metric_complete:
            payload["user_impact_metrics"] = {
                "cold_start_seconds": 1.0,
                "empty_visible_transcript_count": 0,
                "final_transcript_delay_seconds": 0.8,
                "peak_memory_mb": 512.0,
                "permission_asset_failure_count": 0,
                "preview_revision_count": 2,
                "sidecar_startup_failure_count": 0,
                "time_to_first_visible_text_seconds": 0.4,
                "unstable_partial_ratio": 0.1,
                "user_visible_fallback_event_count": 0,
            }
        return payload

    def engine(
        self,
        engine_id="speech_analyzer",
        runtime="apple_speech",
        requires_sidecar=False,
        supports_streaming=False,
        health_status="ready",
    ):
        return {
            "manifest_type": "engine_manifest",
            "schema_version": 1,
            "engine_id": engine_id,
            "model_id": f"{engine_id}-model",
            "runtime": runtime,
            "supports_offline": True,
            "supports_streaming": supports_streaming,
            "requires_network": False,
            "requires_sidecar": requires_sidecar,
            "requires_os_version": "fixture-os",
            "requires_user_permission": False,
            "health_status": health_status,
            "failure_modes": [],
        }


if __name__ == "__main__":
    unittest.main()
