#!/usr/bin/env python3
import argparse
import html
import json
from pathlib import Path

import validate_stt_benchmark_manifest as validator


def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        description="Render official STT benchmark decision manifest as Markdown and HTML reports."
    )
    parser.add_argument("--decision-manifest", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    return parser.parse_args(argv)


def read_json(path):
    with path.expanduser().open(encoding="utf-8") as handle:
        return json.load(handle)


def write_text(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def validate_decision_manifest(payload):
    errors = validator.validate_manifest(payload)
    if errors:
        raise SystemExit("decision manifest is invalid: " + "; ".join(errors))
    if payload.get("manifest_type") != "decision_manifest":
        raise SystemExit("decision manifest must have manifest_type=decision_manifest")


def render_markdown(payload):
    benchmark = payload.get("benchmark_run_manifest") or {}
    metric = payload.get("metric_summary") or {}
    user_impact = metric.get("user_impact_metrics") or {}
    manual = payload.get("manual_review_manifest") or {}
    reference = payload.get("reference_manifest") or {}
    engine = payload.get("engine_manifest") or {}
    regression = payload.get("regression_report") or {}
    regression_deltas = regression.get("deltas") or {}

    lines = [
        "# Official STT Benchmark Report",
        "",
        "## Decision",
        "",
        f"- decision_state: `{payload.get('decision_state', '')}`",
        f"- default_change: `{payload.get('default_change', '')}`",
        f"- eligible_for_default: `{str(payload.get('eligible_for_default')).lower()}`",
        f"- engine_id: `{benchmark.get('engine_id', '')}`",
        f"- benchmark_kind: `{benchmark.get('benchmark_kind', '')}`",
        f"- product_path: `{str(benchmark.get('product_path')).lower()}`",
        "",
        "## Blocking Gates",
        "",
    ]
    lines.extend(list_items(payload.get("blocking_gates") or []))
    lines.extend([
        "",
        "## Reasons",
        "",
    ])
    lines.extend(list_items(payload.get("reasons") or []))
    lines.extend([
        "",
        "## Next Actions",
        "",
    ])
    lines.extend(list_items(payload.get("next_actions") or []))
    lines.extend([
        "",
        "## Scorecard",
        "",
        "| Area | Value |",
        "| --- | --- |",
        f"| Weighted CER | `{metric.get('weighted_cer', 'n/a')}` |",
        f"| Macro CER | `{metric.get('macro_cer', 'n/a')}` |",
        f"| Empty final count | `{metric.get('empty_final_count', 'n/a')}` |",
        f"| Timeout count | `{metric.get('timeout_count', 'n/a')}` |",
        f"| Crash count | `{metric.get('crash_count', 'n/a')}` |",
        f"| User impact complete | `{str(metric.get('user_impact_metric_complete', False)).lower()}` |",
        f"| Time to first visible text | `{user_impact.get('time_to_first_visible_text_seconds', 'n/a')}` |",
        f"| Final transcript delay | `{user_impact.get('final_transcript_delay_seconds', 'n/a')}` |",
        f"| Preview revision count | `{user_impact.get('preview_revision_count', 'n/a')}` |",
        f"| Unstable partial ratio | `{user_impact.get('unstable_partial_ratio', 'n/a')}` |",
        f"| Empty visible transcript count | `{user_impact.get('empty_visible_transcript_count', 'n/a')}` |",
        f"| Permission/asset failure count | `{user_impact.get('permission_asset_failure_count', 'n/a')}` |",
        f"| Sidecar startup failure count | `{user_impact.get('sidecar_startup_failure_count', 'n/a')}` |",
        f"| User-visible fallback event count | `{user_impact.get('user_visible_fallback_event_count', 'n/a')}` |",
        f"| Peak memory MB | `{user_impact.get('peak_memory_mb', 'n/a')}` |",
        f"| Cold start seconds | `{user_impact.get('cold_start_seconds', 'n/a')}` |",
        f"| Manual review complete | `{str(manual.get('complete')).lower()}` |",
        f"| Manual follow-up count | `{manual.get('manual_followup_count', 'n/a')}` |",
        f"| Reference version | `{reference.get('reference_version', '')}` |",
        f"| Reference issue count | `{reference.get('reference_quality_issue_count', 'n/a')}` |",
        f"| Engine runtime | `{engine.get('runtime', benchmark.get('runtime', ''))}` |",
        f"| Requires sidecar | `{str(engine.get('requires_sidecar', False)).lower()}` |",
        f"| Regression state | `{regression.get('regression_state', 'n/a')}` |",
        f"| Regression weighted CER delta pp | `{regression_deltas.get('weighted_cer_pp', 'n/a')}` |",
        f"| Regression empty final delta | `{regression_deltas.get('empty_final_count', 'n/a')}` |",
        f"| Regression timeout delta | `{regression_deltas.get('timeout_count', 'n/a')}` |",
        f"| Regression crash delta | `{regression_deltas.get('crash_count', 'n/a')}` |",
        "",
        "## Evidence",
        "",
    ])
    lines.extend(list_items(payload.get("evidence_paths") or []))
    lines.append("")
    return "\n".join(lines)


def list_items(items):
    if not items:
        return ["- none"]
    return [f"- `{item}`" for item in items]


def render_html(payload, markdown):
    decision = html.escape(str(payload.get("decision_state", "")))
    default_change = html.escape(str(payload.get("default_change", "")))
    markdown_html = markdown_to_simple_html(markdown)
    return f"""<!doctype html>
<html lang="ko">
<head>
  <meta charset="utf-8">
  <title>Official STT Benchmark Report</title>
  <style>
    body {{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 32px; color: #17202a; }}
    header {{ border-bottom: 1px solid #d8dee4; margin-bottom: 24px; padding-bottom: 16px; }}
    .state {{ display: inline-block; padding: 4px 8px; border: 1px solid #8c959f; border-radius: 6px; font-weight: 700; }}
    .grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 12px; margin: 16px 0 24px; }}
    .panel {{ border: 1px solid #d8dee4; border-radius: 8px; padding: 12px; }}
    h1, h2 {{ line-height: 1.2; }}
    table {{ border-collapse: collapse; width: 100%; }}
    th, td {{ border: 1px solid #d8dee4; padding: 6px 8px; text-align: left; }}
    code {{ background: #f6f8fa; padding: 1px 4px; border-radius: 4px; }}
  </style>
</head>
<body>
  <header>
    <h1>Official STT Benchmark Report</h1>
    <div class="grid">
      <div class="panel"><strong>Decision</strong><br><span class="state">{decision}</span></div>
      <div class="panel"><strong>Default change</strong><br><code>{default_change}</code></div>
    </div>
  </header>
  <main>
{markdown_html}
  </main>
</body>
</html>
"""


def markdown_to_simple_html(markdown):
    result = []
    in_table = False
    for line in markdown.splitlines():
        if line.startswith("# "):
            result.append(f"    <h1>{html.escape(line[2:])}</h1>")
        elif line.startswith("## "):
            if in_table:
                result.append("    </tbody></table>")
                in_table = False
            result.append(f"    <h2>{html.escape(line[3:])}</h2>")
        elif line.startswith("| "):
            cells = [html.escape(cell.strip().strip("`")) for cell in line.strip("|").split("|")]
            if all(set(cell) <= {"-", " "} for cell in cells):
                continue
            if not in_table:
                result.append("    <table><tbody>")
                in_table = True
            tag = "th" if cells and cells[0] == "Area" else "td"
            result.append("      <tr>" + "".join(f"<{tag}>{cell}</{tag}>" for cell in cells) + "</tr>")
        elif line.startswith("- "):
            if in_table:
                result.append("    </tbody></table>")
                in_table = False
            result.append(f"    <p>{html.escape(line)}</p>")
        elif line.strip():
            if in_table:
                result.append("    </tbody></table>")
                in_table = False
            result.append(f"    <p>{html.escape(line)}</p>")
    if in_table:
        result.append("    </tbody></table>")
    return "\n".join(result)


def run(args):
    payload = read_json(args.decision_manifest)
    validate_decision_manifest(payload)
    markdown = render_markdown(payload)
    html_text = render_html(payload, markdown)
    output_root = args.output_root.expanduser().resolve()
    md_path = output_root / "stt_official_benchmark_report.md"
    html_path = output_root / "stt_official_benchmark_report.html"
    write_text(md_path, markdown)
    write_text(html_path, html_text)
    print(f"wrote: {md_path}")
    print(f"wrote: {html_path}")
    print(f"decision_state: {payload.get('decision_state')}")
    print(f"default_change: {payload.get('default_change')}")
    return {"md_path": md_path, "html_path": html_path, "payload": payload}


def main(argv=None):
    return 0 if run(parse_args(argv)) else 1


if __name__ == "__main__":
    raise SystemExit(main())
