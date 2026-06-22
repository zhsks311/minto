import importlib
import json
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "lib"
sys.path.insert(0, str(SCRIPTS))

report = importlib.import_module("render_stt_official_benchmark_report")


class STTOfficialReportTests(unittest.TestCase):

    def decision_manifest(self):
        return json.loads(
            (ROOT / "fixtures/minimal_decision_manifest.json")
            .read_text(encoding="utf-8")
        )

    def test_markdown_includes_decision_blockers_and_scorecard(self):
        markdown = report.render_markdown(self.decision_manifest())

        self.assertIn("decision_state: `experimental_flag_only`", markdown)
        self.assertIn("default_change: `not_allowed`", markdown)
        self.assertIn("`boundary_slicing_issue`", markdown)
        self.assertIn("| Weighted CER | `0.3069935450775873` |", markdown)
        self.assertIn("| Time to first visible text | `n/a` |", markdown)

    def test_markdown_includes_user_impact_metrics_when_present(self):
        payload = self.decision_manifest()
        payload["metric_summary"] = json.loads(
            (ROOT / "fixtures/complete_user_impact_metric_summary.json")
            .read_text(encoding="utf-8")
        )

        markdown = report.render_markdown(payload)

        self.assertIn("| Time to first visible text | `0.4` |", markdown)
        self.assertIn("| Unstable partial ratio | `0.1` |", markdown)
        self.assertIn("| Sidecar startup failure count | `0` |", markdown)
        self.assertIn("| Cold start seconds | `1.2` |", markdown)

    def test_markdown_includes_regression_result_when_present(self):
        payload = self.decision_manifest()
        regression = json.loads(
            (ROOT / "fixtures/minimal_regression_report.json")
            .read_text(encoding="utf-8")
        )
        regression.pop("manifest_type")
        payload["regression_report"] = regression

        markdown = report.render_markdown(payload)

        self.assertIn("| Regression state | `passed` |", markdown)
        self.assertIn("| Regression weighted CER delta pp | `0.0` |", markdown)
        self.assertIn("| Regression empty final delta | `0.0` |", markdown)

    def test_html_escapes_and_shows_decision(self):
        html = report.render_html(self.decision_manifest(), report.render_markdown(self.decision_manifest()))

        self.assertIn("Official STT Benchmark Report", html)
        self.assertIn("experimental_flag_only", html)
        self.assertIn("default_change", html)

    def test_cli_writes_markdown_and_html(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            manifest = root / "decision.json"
            manifest.write_text(
                json.dumps(self.decision_manifest(), ensure_ascii=False),
                encoding="utf-8",
            )

            result = report.run(type("Args", (), {
                "decision_manifest": manifest,
                "output_root": root / "out",
            })())

            self.assertTrue(result["md_path"].exists())
            self.assertTrue(result["html_path"].exists())
            self.assertIn("experimental_flag_only", result["md_path"].read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
