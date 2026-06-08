#!/usr/bin/env python3
import argparse
import csv
import json
from collections import defaultdict
from pathlib import Path


def parse_args():
    parser = argparse.ArgumentParser(description="Summarize Minto STT benchmark metric JSON files.")
    parser.add_argument("benchmark_root", type=Path)
    parser.add_argument("--write", action="store_true", help="Write summary.md and summary.csv into benchmark_root.")
    return parser.parse_args()


def load_metrics(root):
    metrics = []
    for path in sorted(root.glob("**/*_metrics.json")):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            continue
        if data.get("schema_version") != 1 or "engine_id" not in data:
            continue
        data["_path"] = str(path)
        metrics.append(data)
    return metrics


def fmt_percent(value):
    if value is None:
        return "n/a"
    return f"{value * 100:.1f}%"


def fmt_float(value):
    if value is None:
        return "n/a"
    return f"{value:.3f}"


def summarize_by_engine(metrics):
    groups = defaultdict(list)
    for metric in metrics:
        groups[metric["engine_id"]].append(metric)

    rows = []
    for engine_id, items in sorted(groups.items()):
        total_distance = sum(int(item.get("distance") or 0) for item in items)
        total_ref = sum(int(item.get("reference_length") or 0) for item in items)
        total_elapsed = sum(float(item.get("elapsed_seconds") or 0) for item in items)
        total_audio = sum(float(item.get("audio_seconds") or 0) for item in items)
        peak_values = [
            float(item["peak_memory_mb"])
            for item in items
            if item.get("peak_memory_mb") is not None
        ]
        macro_values = [
            float(item["micro_cer"])
            for item in items
            if item.get("micro_cer") is not None
        ]
        global_values = [
            float(item["global_cer"])
            for item in items
            if item.get("global_cer") is not None
        ]
        rows.append({
            "engine_id": engine_id,
            "engine_label": items[0].get("engine_label", engine_id),
            "model_id": items[0].get("model_id", ""),
            "sample_count": len(items),
            "weighted_micro_cer": total_distance / total_ref if total_ref else None,
            "sample_macro_cer": sum(macro_values) / len(macro_values) if macro_values else None,
            "global_cer_mean": sum(global_values) / len(global_values) if global_values else None,
            "empty_final_count": sum(int(item.get("empty_final_count") or 0) for item in items),
            "false_positive_chars": sum(int(item.get("false_positive_transcript_chars") or 0) for item in items),
            "rtf": total_elapsed / total_audio if total_audio else None,
            "peak_memory_mb": max(peak_values) if peak_values else None,
        })
    return rows


def markdown_table(rows):
    lines = [
        "| Engine | Samples | Weighted CER | Macro CER | Global CER | RTF | Peak MB | Empty | FP chars |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for row in rows:
        lines.append(
            "| {engine} | {samples} | {weighted} | {macro} | {global_cer} | {rtf} | {peak} | {empty} | {fp} |".format(
                engine=row["engine_id"],
                samples=row["sample_count"],
                weighted=fmt_percent(row["weighted_micro_cer"]),
                macro=fmt_percent(row["sample_macro_cer"]),
                global_cer=fmt_percent(row["global_cer_mean"]),
                rtf=fmt_float(row["rtf"]),
                peak=fmt_float(row["peak_memory_mb"]),
                empty=row["empty_final_count"],
                fp=row["false_positive_chars"],
            )
        )
    return "\n".join(lines)


def write_csv(path, rows):
    fieldnames = [
        "engine_id",
        "engine_label",
        "model_id",
        "sample_count",
        "weighted_micro_cer",
        "sample_macro_cer",
        "global_cer_mean",
        "empty_final_count",
        "false_positive_chars",
        "rtf",
        "peak_memory_mb",
    ]
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def main():
    args = parse_args()
    root = args.benchmark_root.expanduser().resolve()
    metrics = load_metrics(root)
    rows = summarize_by_engine(metrics)
    table = markdown_table(rows)

    print(table)
    print(f"\nmetrics: {len(metrics)}")

    if args.write:
        (root / "summary.md").write_text(table + "\n", encoding="utf-8")
        write_csv(root / "summary.csv", rows)
        print(f"wrote: {root / 'summary.md'}")
        print(f"wrote: {root / 'summary.csv'}")

    return 0 if metrics else 1


if __name__ == "__main__":
    raise SystemExit(main())
