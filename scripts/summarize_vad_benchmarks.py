#!/usr/bin/env python3
import argparse
import csv
import json
from collections import defaultdict
from pathlib import Path


def parse_args():
    parser = argparse.ArgumentParser(description="Summarize Minto VAD benchmark metric JSON files.")
    parser.add_argument("benchmark_root", type=Path)
    parser.add_argument("--write", action="store_true", help="Write vad_summary.md and vad_summary.csv.")
    return parser.parse_args()


def load_metrics(root):
    metrics = []
    for path in sorted(root.expanduser().resolve().glob("**/*_vad_*_metrics.json")):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            continue
        if "vad" not in data or "sample" not in data or "chunks" not in data:
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


def summarize_by_vad(metrics):
    groups = defaultdict(list)
    for metric in metrics:
        groups[group_key(metric)].append(metric)

    rows = []
    for key, items in sorted(groups.items()):
        vad, merge_gap_seconds, merge_max_seconds = key
        total_seconds = sum(float(item.get("seconds") or 0) for item in items)
        total_reference = sum(float(item.get("reference_speech_seconds") or 0) for item in items)
        total_covered = sum(float(item.get("covered_speech_seconds") or 0) for item in items)
        total_final_speech = sum(float(item.get("final_speech_seconds") or 0) for item in items)
        total_false_positive = sum(float(item.get("false_positive_seconds") or 0) for item in items)
        total_short_reference = sum(int(item.get("short_reference_count") or 0) for item in items)
        total_short_covered = sum(int(item.get("short_covered_count") or 0) for item in items)
        total_chunks = sum(int(item.get("chunk_count") or 0) for item in items)
        total_raw_chunks = sum(int(item.get("raw_chunk_count") or 0) for item in items)
        recall_values = [
            float(item["speech_recall"])
            for item in items
            if item.get("speech_recall") is not None
        ]
        short_recall_values = [
            float(item["short_recall"])
            for item in items
            if item.get("short_recall") is not None
        ]
        rows.append({
            "vad": vad,
            "merge_gap_seconds": merge_gap_seconds,
            "merge_max_seconds": merge_max_seconds,
            "sample_count": len(items),
            "available_count": sum(1 for item in items if item.get("available") is True),
            "error_count": sum(1 for item in items if item.get("available") is False),
            "seconds": total_seconds,
            "chunk_count": total_chunks,
            "raw_chunk_count": total_raw_chunks,
            "chunks_per_minute": total_chunks / (total_seconds / 60) if total_seconds else None,
            "weighted_speech_recall": total_covered / total_reference if total_reference else None,
            "macro_speech_recall": sum(recall_values) / len(recall_values) if recall_values else None,
            "weighted_short_recall": (
                total_short_covered / total_short_reference
                if total_short_reference else None
            ),
            "macro_short_recall": (
                sum(short_recall_values) / len(short_recall_values)
                if short_recall_values else None
            ),
            "missed_speech_seconds": max(0, total_reference - total_covered),
            "false_positive_seconds": total_false_positive,
            "false_positive_ratio": (
                total_false_positive / total_final_speech
                if total_final_speech else None
            ),
        })
    return rows


def group_key(metric):
    config = metric.get("config") or {}
    return (
        metric["vad"],
        config.get("chunk_merge_gap_seconds"),
        config.get("chunk_merge_max_seconds"),
    )


def markdown_table(rows):
    lines = [
        "| VAD | Merge gap | Merge max | Samples | Available | Chunks | Raw chunks | Chunks/min | Speech recall | Short recall | Missed sec | FP sec | FP ratio |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for row in rows:
        lines.append(
            "| {vad} | {merge_gap} | {merge_max} | {samples} | {available} | {chunks} | {raw_chunks} | {chunks_per_minute} | {speech_recall} | {short_recall} | {missed} | {fp_sec} | {fp_ratio} |".format(
                vad=row["vad"],
                merge_gap=fmt_float(row["merge_gap_seconds"]),
                merge_max=fmt_float(row["merge_max_seconds"]),
                samples=row["sample_count"],
                available=row["available_count"],
                chunks=row["chunk_count"],
                raw_chunks=row["raw_chunk_count"],
                chunks_per_minute=fmt_float(row["chunks_per_minute"]),
                speech_recall=fmt_percent(row["weighted_speech_recall"]),
                short_recall=fmt_percent(row["weighted_short_recall"]),
                missed=fmt_float(row["missed_speech_seconds"]),
                fp_sec=fmt_float(row["false_positive_seconds"]),
                fp_ratio=fmt_percent(row["false_positive_ratio"]),
            )
        )
    return "\n".join(lines)


def write_csv(path, rows):
    fieldnames = [
        "vad",
        "merge_gap_seconds",
        "merge_max_seconds",
        "sample_count",
        "available_count",
        "error_count",
        "seconds",
        "chunk_count",
        "raw_chunk_count",
        "chunks_per_minute",
        "weighted_speech_recall",
        "macro_speech_recall",
        "weighted_short_recall",
        "macro_short_recall",
        "missed_speech_seconds",
        "false_positive_seconds",
        "false_positive_ratio",
    ]
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def main():
    args = parse_args()
    root = args.benchmark_root.expanduser().resolve()
    metrics = load_metrics(root)
    rows = summarize_by_vad(metrics)
    table = markdown_table(rows)

    print(table)
    print(f"\nmetrics: {len(metrics)}")

    if args.write:
        (root / "vad_summary.md").write_text(table + "\n", encoding="utf-8")
        write_csv(root / "vad_summary.csv", rows)
        print(f"wrote: {root / 'vad_summary.md'}")
        print(f"wrote: {root / 'vad_summary.csv'}")

    return 0 if metrics else 1


if __name__ == "__main__":
    raise SystemExit(main())
