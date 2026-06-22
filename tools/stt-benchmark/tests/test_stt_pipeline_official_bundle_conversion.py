import csv
import importlib
import json
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "lib"
sys.path.insert(0, str(SCRIPTS))

converter = importlib.import_module("convert_stt_pipeline_to_official_bundle")
lane_matrix = importlib.import_module("build_stt_engine_lane_matrix")
product_path_readiness = importlib.import_module("check_stt_product_path_readiness")
validator = importlib.import_module("validate_stt_benchmark_manifest")


class STTPipelineOfficialBundleConversionTests(unittest.TestCase):

    def test_converts_pipeline_summary_to_official_bundle(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            pipeline_path = self.write_pipeline(
                root,
                engines=["speech_analyzer"],
                rows=[self.summary_row("speech_analyzer", weighted_micro_cer="0.31")],
                runs=[self.run_row("speech_analyzer", "sample_a", "passed")],
            )

            result = converter.run(self.args(root, pipeline_path))

            bundle = result["payload"]
            self.assertEqual(bundle["bundle_count"], 1)
            self.assertEqual(validator.validate_manifest(bundle), [])

            benchmark, metric, engine = self.load_bundle_entry(root / "official", bundle["runs"][0])
            self.assertEqual(benchmark["benchmark_kind"], "offline_final")
            self.assertFalse(benchmark["product_path"])
            self.assertEqual(metric["weighted_cer"], 0.31)
            self.assertFalse(metric["user_impact_metric_complete"])
            self.assertEqual(engine["health_status"], "ready")

            matrix_result = lane_matrix.run(type("Args", (), {
                "run_bundle_manifest": [result["output_path"]],
                "benchmark_run_manifest": [],
                "metric_summary": [],
                "engine_manifest": [],
                "output_root": root / "matrix",
            })())
            self.assertEqual(matrix_result["payload"]["entry_count"], 1)
            self.assertEqual(validator.validate_manifest(matrix_result["payload"]), [])

    def test_product_path_flag_writes_product_path_final_contract(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            pipeline_path = self.write_pipeline(
                root,
                engines=["speech_analyzer"],
                rows=[self.summary_row("speech_analyzer")],
                runs=[self.run_row("speech_analyzer", "sample_a", "passed")],
                dry_run=True,
            )

            result = converter.run(self.args(root, pipeline_path, product_path=True))

            benchmark, _metric, _engine = self.load_bundle_entry(root / "official", result["payload"]["runs"][0])
            self.assertEqual(benchmark["benchmark_kind"], "product_path_final")
            self.assertTrue(benchmark["product_path"])
            self.assertTrue(benchmark["runner_contract"]["dry_run"])
            self.assertEqual(validator.validate_manifest(benchmark), [])

    def test_product_path_user_impact_summary_can_enter_readiness_gate(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            pipeline_path = self.write_pipeline(
                root,
                engines=["speech_analyzer"],
                rows=[self.summary_row("speech_analyzer", user_impact=True)],
                runs=[self.run_row("speech_analyzer", "sample_a", "passed")],
            )

            result = converter.run(self.args(root, pipeline_path, product_path=True))

            benchmark, metric, engine = self.load_bundle_entry(
                root / "official",
                result["payload"]["runs"][0],
            )
            self.assertEqual(benchmark["benchmark_kind"], "product_path_final")
            self.assertTrue(benchmark["product_path"])
            self.assertFalse(benchmark["runner_contract"]["dry_run"])
            self.assertTrue(metric["user_impact_metric_complete"])
            self.assertEqual(
                metric["user_impact_metrics"]["time_to_first_visible_text_seconds"],
                1.2,
            )
            self.assertEqual(
                metric["user_impact_metrics"]["preview_revision_count"],
                3,
            )
            self.assertEqual(engine["health_status"], "ready")
            self.assertEqual(validator.validate_manifest(metric), [])

            matrix_result = lane_matrix.run(type("Args", (), {
                "run_bundle_manifest": [result["output_path"]],
                "benchmark_run_manifest": [],
                "metric_summary": [],
                "engine_manifest": [],
                "output_root": root / "matrix",
            })())
            readiness_result = product_path_readiness.run(type("Args", (), {
                "engine_lane_matrix": matrix_result["json_path"],
                "output_root": root / "readiness",
            })())
            self.assertEqual(
                readiness_result["payload"]["readiness_state"],
                "ready_for_product_path_default_gate",
            )
            self.assertTrue(readiness_result["payload"]["eligible_for_default_gate"])

    def test_unavailable_engine_without_summary_row_stays_present_but_not_ready(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            pipeline_path = self.write_pipeline(
                root,
                engines=["speech_analyzer", "sf_speech_on_device"],
                rows=[self.summary_row("speech_analyzer")],
                runs=[
                    self.run_row("speech_analyzer", "sample_a", "passed"),
                    self.run_row(
                        "sf_speech_on_device",
                        "sample_a",
                        "skipped_unavailable",
                        skip_reason="Siri and Dictation are disabled",
                    ),
                ],
                status="passed_with_skips",
            )

            result = converter.run(self.args(root, pipeline_path))
            by_engine = {
                run["engine_id"]: self.load_bundle_entry(root / "official", run)
                for run in result["payload"]["runs"]
            }

            _benchmark, metric, engine = by_engine["sf_speech_on_device"]
            self.assertEqual(engine["health_status"], "skipped_unavailable")
            self.assertIn("skip_reason:Siri and Dictation are disabled", engine["failure_modes"])
            self.assertEqual(metric["sample_count"], 0)
            self.assertEqual(metric["sidecar_unavailable_count"], 1)
            self.assertTrue(metric["metric_placeholder"])
            self.assertEqual(validator.validate_manifest(metric), [])

            matrix_result = lane_matrix.run(type("Args", (), {
                "run_bundle_manifest": [result["output_path"]],
                "benchmark_run_manifest": [],
                "metric_summary": [],
                "engine_manifest": [],
                "output_root": root / "matrix",
            })())
            rows = {row["engine_id"]: row for row in matrix_result["payload"]["lanes"]}
            self.assertIn("sf_speech_on_device", rows)
            self.assertFalse(rows["sf_speech_on_device"]["default_gate_input"])

    def test_duplicate_engine_rows_get_distinct_manifest_paths(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            pipeline_path = self.write_pipeline(
                root,
                engines=["speech_analyzer"],
                rows=[
                    self.summary_row("speech_analyzer", weighted_micro_cer="0.25"),
                    self.summary_row("speech_analyzer", weighted_micro_cer="0.35"),
                ],
                runs=[self.run_row("speech_analyzer", "sample_a", "passed")],
            )

            result = converter.run(self.args(root, pipeline_path))

            bundle = result["payload"]
            benchmark_paths = [
                run["benchmark_run_manifest"]
                for run in bundle["runs"]
            ]
            self.assertEqual(bundle["bundle_count"], 2)
            self.assertEqual(len(set(benchmark_paths)), 2)
            for run in bundle["runs"]:
                benchmark, metric, engine = self.load_bundle_entry(root / "official", run)
                self.assertEqual(validator.validate_manifest(benchmark), [])
                self.assertEqual(validator.validate_manifest(metric), [])
                self.assertEqual(validator.validate_manifest(engine), [])

    def test_engine_id_alias_maps_model_specific_runner_to_official_engine_id(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            raw_engine_id = "sherpa_onnx_ko_streaming_zipformer"
            pipeline_path = self.write_pipeline(
                root,
                engines=[raw_engine_id],
                rows=[self.summary_row(raw_engine_id, weighted_micro_cer="0.79")],
                runs=[self.run_row(raw_engine_id, "sample_a", "passed")],
            )

            args = self.args(root, pipeline_path)
            args.engine_id_alias = [f"{raw_engine_id}=sherpa"]
            args.official_benchmark_kind = "true_streaming"
            result = converter.run(args)

            bundle = result["payload"]
            self.assertEqual(bundle["runs"][0]["engine_id"], "sherpa")
            benchmark, metric, engine = self.load_bundle_entry(root / "official", bundle["runs"][0])
            self.assertEqual(benchmark["engine_id"], "sherpa")
            self.assertEqual(benchmark["model_id"], f"{raw_engine_id}-model")
            self.assertEqual(benchmark["benchmark_kind"], "true_streaming")
            self.assertEqual(metric["weighted_cer"], 0.79)
            self.assertEqual(engine["engine_id"], "sherpa")
            self.assertEqual(engine["runtime"], "sherpa_onnx")
            self.assertEqual(engine["health_status"], "ready")
            self.assertTrue(engine["supports_streaming"])
            self.assertEqual(validator.validate_manifest(bundle), [])
            self.assertEqual(validator.validate_manifest(benchmark), [])
            self.assertEqual(validator.validate_manifest(metric), [])
            self.assertEqual(validator.validate_manifest(engine), [])

    def args(self, root, pipeline_path, product_path=False):
        return type("Args", (), {
            "pipeline_manifest": [pipeline_path],
            "reference_version": "official-reference-v1",
            "sample_set": None,
            "official_benchmark_kind": None,
            "engine_id_alias": [],
            "product_path": product_path,
            "output_root": root / "official",
        })()

    def write_pipeline(self, root, engines, rows, runs, status="passed", dry_run=False):
        benchmark_root = root / "pipeline" / "benchmark"
        benchmark_root.mkdir(parents=True)
        self.write_summary_csv(benchmark_root / "summary.csv", rows)
        (benchmark_root / "run_manifest.json").write_text(json.dumps({
            "schema_version": 1,
            "started_at": "2026-06-12T00:00:00",
            "finished_at": "2026-06-12T00:10:00",
            "status": status,
            "raw_dir": "/tmp/raw",
            "output_root": str(benchmark_root),
            "engines": engines,
            "sample_count": 1,
            "window_sec": 30.0,
            "min_window_sec": 0.0,
            "max_gap_sec": 3.0,
            "audio_pad_sec": 0.5,
            "max_captions_per_window": 0,
            "max_windows": 0,
            "skip_swift_global_cer": "auto",
            "configuration": "release",
            "skip_build": False,
            "timeout_sec": 1200.0,
            "sort": "name",
            "dry_run": dry_run,
            "include_unavailable_engines": False,
            "runs": runs,
        }), encoding="utf-8")
        pipeline_path = root / "pipeline" / "pipeline_manifest.json"
        pipeline_path.write_text(json.dumps({
            "schema_version": 1,
            "started_at": "2026-06-12T00:00:00",
            "finished_at": "2026-06-12T00:10:00",
            "status": status,
            "raw_dir": "/tmp/raw",
            "output_root": str(root / "pipeline"),
            "benchmark_root": str(benchmark_root),
            "engines": ",".join(engines),
            "samples": "",
            "window_sec": 30.0,
            "min_window_sec": 0.0,
            "max_gap_sec": 3.0,
            "audio_pad_sec": 0.5,
            "max_captions_per_window": 0,
            "max_windows": 0,
            "skip_build": False,
            "timeout_sec": 1200.0,
            "dry_run": dry_run,
            "include_unavailable_engines": False,
            "benchmark_summary": {
                "status": status,
                "run_count": len(runs),
                "passed_count": sum(1 for run in runs if run["status"] == "passed"),
                "failed_count": sum(1 for run in runs if run["status"] == "failed"),
                "timeout_count": sum(1 for run in runs if run["status"] == "timeout"),
                "dry_run_count": sum(1 for run in runs if run["status"] == "dry_run"),
                "skipped_unavailable_count": sum(
                    1 for run in runs if run["status"] == "skipped_unavailable"
                ),
            },
        }), encoding="utf-8")
        return pipeline_path

    def write_summary_csv(self, path, rows):
        fieldnames = [
            "engine_id",
            "engine_label",
            "model_id",
            "benchmark_kind",
            "sample_count",
            "weighted_micro_cer",
            "sample_macro_cer",
            "global_cer_mean",
            "full_reference_global_cer",
            "empty_final_count",
            "false_positive_chars",
            "rtf",
            "peak_memory_mb",
            "time_to_first_visible_text_seconds",
            "final_transcript_delay_seconds",
            "preview_revision_count",
            "unstable_partial_ratio",
            "empty_visible_transcript_count",
            "permission_asset_failure_count",
            "sidecar_startup_failure_count",
            "cold_start_seconds",
            "user_visible_fallback_event_count",
        ]
        with path.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(rows)

    def summary_row(
        self,
        engine_id,
        weighted_micro_cer="0.25",
        benchmark_kind="vad_chunk_stt",
        user_impact=False,
    ):
        row = {
            "engine_id": engine_id,
            "engine_label": engine_id,
            "model_id": f"{engine_id}-model",
            "benchmark_kind": benchmark_kind,
            "sample_count": "1",
            "weighted_micro_cer": weighted_micro_cer,
            "sample_macro_cer": "0.27",
            "global_cer_mean": "0.29",
            "full_reference_global_cer": "",
            "empty_final_count": "0",
            "false_positive_chars": "0",
            "rtf": "0.1",
            "peak_memory_mb": "512",
        }
        if user_impact:
            row.update({
                "time_to_first_visible_text_seconds": "1.2",
                "final_transcript_delay_seconds": "0.8",
                "preview_revision_count": "3",
                "unstable_partial_ratio": "0.25",
                "empty_visible_transcript_count": "0",
                "permission_asset_failure_count": "0",
                "sidecar_startup_failure_count": "0",
                "cold_start_seconds": "2.5",
                "user_visible_fallback_event_count": "0",
            })
        return row

    def run_row(self, engine, sample_id, status, skip_reason=None):
        payload = {
            "engine": engine,
            "sample_id": sample_id,
            "status": status,
            "returncode": 0 if status == "passed" else None,
            "elapsed_seconds": 1.0,
            "metrics_file": f"/tmp/{engine}_{sample_id}_metrics.json",
            "log_file": f"/tmp/{engine}_{sample_id}.log",
        }
        if skip_reason:
            payload["skip_reason"] = skip_reason
        return payload

    def load_bundle_entry(self, output_root, run):
        benchmark = json.loads((output_root / run["benchmark_run_manifest"]).read_text(encoding="utf-8"))
        metric = json.loads((output_root / run["metric_summary"]).read_text(encoding="utf-8"))
        engine = json.loads((output_root / run["engine_manifest"]).read_text(encoding="utf-8"))
        return benchmark, metric, engine


if __name__ == "__main__":
    unittest.main()
