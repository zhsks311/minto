#!/usr/bin/env python3
import argparse
import csv
import json
import unicodedata
from collections import defaultdict
from pathlib import Path


def parse_args():
    parser = argparse.ArgumentParser(description="Summarize Minto STT benchmark metric JSON files.")
    parser.add_argument("benchmark_root", type=Path)
    parser.add_argument("--write", action="store_true", help="Write summary.md and summary.csv into benchmark_root.")
    parser.add_argument(
        "--compute-missing-global-cer",
        action="store_true",
        help="Compute missing global_cer from sibling *_ref.txt and *_hyp.txt files when bounded by safety limits.",
    )
    parser.add_argument(
        "--global-char-limit",
        type=int,
        default=20_000,
        help="Maximum combined reference+hypothesis characters for computed global CER.",
    )
    parser.add_argument(
        "--global-cell-limit",
        type=int,
        default=50_000_000,
        help="Maximum edit-distance DP cells for computed global CER.",
    )
    parser.add_argument(
        "--write-segments",
        action="store_true",
        help="Write segments.md and segments.csv with empty or high-CER segments.",
    )
    parser.add_argument(
        "--segment-limit",
        type=int,
        default=40,
        help="Maximum segment diagnostics to print/write.",
    )
    parser.add_argument(
        "--segment-min-cer",
        type=float,
        default=0.8,
        help="Include non-empty segments at or above this CER.",
    )
    return parser.parse_args()


def load_metrics(root, compute_missing_global_cer=False, global_char_limit=20_000, global_cell_limit=50_000_000):
    metrics = []
    for path in sorted(root.glob("**/*_metrics.json")):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            continue
        if data.get("schema_version") != 1 or "engine_id" not in data:
            continue
        data["_path"] = str(path)
        if compute_missing_global_cer and data.get("global_cer") is None:
            compute_missing_global(data, path, global_char_limit, global_cell_limit)
        metrics.append(data)
    return metrics


def compute_missing_global(metric, metric_path, global_char_limit, global_cell_limit):
    if not metric_path.name.endswith("_metrics.json"):
        metric["_global_cer_skip_reason"] = "unexpected_metric_filename"
        return

    sample_name = metric_path.name.removesuffix("_metrics.json")
    ref_path = metric_path.with_name(f"{sample_name}_ref.txt")
    hyp_path = metric_path.with_name(f"{sample_name}_hyp.txt")
    if not ref_path.exists() or not hyp_path.exists():
        metric["_global_cer_skip_reason"] = "missing_ref_or_hyp"
        return

    try:
        if ref_path.stat().st_size + hyp_path.stat().st_size > global_char_limit * 4:
            metric["_global_cer_skip_reason"] = "byte_limit"
            return
        reference = ref_path.read_text(encoding="utf-8")
        hypothesis = hyp_path.read_text(encoding="utf-8")
    except OSError as error:
        metric["_global_cer_skip_reason"] = f"read_error:{error.__class__.__name__}"
        return

    if len(reference) + len(hypothesis) > global_char_limit:
        metric["_global_cer_skip_reason"] = "char_limit"
        return

    ref_chars = strip_for_cer(reference)
    hyp_chars = strip_for_cer(hypothesis)
    if len(ref_chars) * len(hyp_chars) > global_cell_limit:
        metric["_global_cer_skip_reason"] = "cell_limit"
        return

    ref_len = len(ref_chars)
    distance = edit_distance(ref_chars, hyp_chars)
    metric["global_distance"] = distance
    metric["global_reference_length"] = ref_len
    metric["global_cer"] = distance / ref_len if ref_len else None
    metric["_global_cer_source"] = "computed_ref_hyp"


def strip_for_cer(text):
    normalized = unicodedata.normalize("NFC", text)
    return [
        char
        for char in normalized
        if not char.isspace() and not unicodedata.category(char).startswith("P")
    ]


def edit_distance(left, right):
    if not left:
        return len(right)
    if not right:
        return len(left)
    if len(right) > len(left):
        left, right = right, left

    previous = list(range(len(right) + 1))
    for left_index, left_value in enumerate(left, start=1):
        current = [left_index]
        for right_index, right_value in enumerate(right, start=1):
            substitution = previous[right_index - 1] + (left_value != right_value)
            insertion = current[right_index - 1] + 1
            deletion = previous[right_index] + 1
            current.append(min(substitution, insertion, deletion))
        previous = current
    return previous[-1]


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


def segment_diagnostics(metrics, min_cer, limit):
    rows = []
    for metric in metrics:
        for segment in metric.get("segments", []):
            cer = segment.get("cer")
            empty = bool(segment.get("empty"))
            if cer is None:
                continue
            if not empty and float(cer) < min_cer:
                continue

            rows.append({
                "engine_id": metric.get("engine_id", ""),
                "sample_id": metric.get("sample_id", ""),
                "index": int(segment.get("index") or 0),
                "start_seconds": float(segment.get("start_seconds") or 0),
                "end_seconds": float(segment.get("end_seconds") or 0),
                "duration_seconds": float(segment.get("duration_seconds") or 0),
                "cer": float(cer),
                "empty": empty,
                "reference_length": int(segment.get("reference_length") or 0),
                "hypothesis_length": int(segment.get("hypothesis_length") or 0),
                "distance": int(segment.get("distance") or 0),
                "reference": segment.get("reference") or "",
                "hypothesis": segment.get("hypothesis") or "",
                "metrics_file": metric.get("_path", ""),
            })

    for row in rows:
        duration = row["duration_seconds"]
        row["reference_chars_per_second"] = row["reference_length"] / duration if duration else None
        row["hypothesis_chars_per_second"] = row["hypothesis_length"] / duration if duration else None

    rows.sort(key=lambda row: (
        not row["empty"],
        -row["cer"],
        -row["reference_length"],
        row["sample_id"],
        row["index"],
    ))
    return rows[:max(0, limit)]


def compact_text(value, limit=90):
    text = " ".join(str(value).split())
    if len(text) <= limit:
        return text
    return text[:limit - 1] + "..."


def escape_markdown_cell(value):
    return compact_text(value).replace("|", "\\|")


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


def segment_markdown_table(rows):
    lines = [
        "| Engine | Sample | # | Time | Dur | CER | Empty | Ref len | Ref cps | Hyp len | Hyp cps | Reference | Hypothesis |",
        "| --- | --- | ---: | --- | ---: | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |",
    ]
    for row in rows:
        lines.append(
            "| {engine} | {sample} | {index} | {time} | {duration} | {cer} | {empty} | {ref_len} | {ref_cps} | {hyp_len} | {hyp_cps} | {reference} | {hypothesis} |".format(
                engine=row["engine_id"],
                sample=row["sample_id"],
                index=row["index"],
                time=f"{row['start_seconds']:.1f}-{row['end_seconds']:.1f}s",
                duration=fmt_float(row["duration_seconds"]),
                cer=fmt_percent(row["cer"]),
                empty="yes" if row["empty"] else "no",
                ref_len=row["reference_length"],
                ref_cps=fmt_float(row["reference_chars_per_second"]),
                hyp_len=row["hypothesis_length"],
                hyp_cps=fmt_float(row["hypothesis_chars_per_second"]),
                reference=escape_markdown_cell(row["reference"]),
                hypothesis=escape_markdown_cell(row["hypothesis"]),
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


def write_segment_csv(path, rows):
    fieldnames = [
        "engine_id",
        "sample_id",
        "index",
        "start_seconds",
        "end_seconds",
        "duration_seconds",
        "cer",
        "empty",
        "reference_length",
        "reference_chars_per_second",
        "hypothesis_length",
        "hypothesis_chars_per_second",
        "distance",
        "reference",
        "hypothesis",
        "metrics_file",
    ]
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def main():
    args = parse_args()
    root = args.benchmark_root.expanduser().resolve()
    metrics = load_metrics(
        root,
        compute_missing_global_cer=args.compute_missing_global_cer,
        global_char_limit=args.global_char_limit,
        global_cell_limit=args.global_cell_limit,
    )
    rows = summarize_by_engine(metrics)
    table = markdown_table(rows)
    segment_rows = segment_diagnostics(
        metrics,
        min_cer=args.segment_min_cer,
        limit=args.segment_limit,
    )
    segment_table = segment_markdown_table(segment_rows)
    computed_global_count = sum(
        1
        for metric in metrics
        if metric.get("_global_cer_source") == "computed_ref_hyp"
    )
    skipped_global_count = sum(
        1
        for metric in metrics
        if metric.get("_global_cer_skip_reason") is not None
    )

    print(table)
    print(f"\nmetrics: {len(metrics)}")
    if args.compute_missing_global_cer:
        print(f"computed missing global CER: {computed_global_count}")
        print(f"skipped missing global CER: {skipped_global_count}")
    if args.write_segments:
        print(f"segment diagnostics: {len(segment_rows)}")
        print()
        print(segment_table)

    if args.write:
        (root / "summary.md").write_text(table + "\n", encoding="utf-8")
        write_csv(root / "summary.csv", rows)
        print(f"wrote: {root / 'summary.md'}")
        print(f"wrote: {root / 'summary.csv'}")
    if args.write_segments:
        (root / "segments.md").write_text(segment_table + "\n", encoding="utf-8")
        write_segment_csv(root / "segments.csv", segment_rows)
        print(f"wrote: {root / 'segments.md'}")
        print(f"wrote: {root / 'segments.csv'}")

    return 0 if metrics else 1


if __name__ == "__main__":
    raise SystemExit(main())
