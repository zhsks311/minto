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
    parser.add_argument(
        "--vad-root",
        type=Path,
        default=None,
        help="Optional root containing *_vad_*_metrics.json files for segment/VAD overlap diagnostics.",
    )
    parser.add_argument(
        "--vad-engine",
        default="energy",
        help="VAD engine id to use from --vad-root. Defaults to energy.",
    )
    parser.add_argument(
        "--vad-low-overlap",
        type=float,
        default=0.5,
        help="Segments below this VAD overlap ratio are treated as VAD/segmentation miss candidates.",
    )
    parser.add_argument(
        "--vad-high-overlap",
        type=float,
        default=0.8,
        help="Segments at or above this VAD overlap ratio are treated as ASR/decode failure candidates.",
    )
    return parser.parse_args()


def load_metrics(root, compute_missing_global_cer=False, global_char_limit=20_000, global_cell_limit=50_000_000):
    metrics = []
    for path in sorted(root.glob("**/*.json")):
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


def load_vad_metrics(root):
    if root is None:
        return {}

    metrics = {}
    for path in root.expanduser().resolve().glob("**/*_vad_*_metrics.json"):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            continue
        if "chunks" not in data or "sample" not in data or "vad" not in data:
            continue
        data["_path"] = str(path)
        key = (normalize_id(data["sample"]), str(data["vad"]))
        metrics[key] = data
    return metrics


def normalize_id(value):
    return unicodedata.normalize("NFC", str(value))


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


def segment_diagnostics(metrics, min_cer, vad_metrics=None, vad_engine="energy"):
    vad_metrics = vad_metrics or {}
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
        add_vad_overlap(row, vad_metrics, vad_engine)

    rows.sort(key=lambda row: (
        not row["empty"],
        -row["cer"],
        -row["reference_length"],
        row["sample_id"],
        row["index"],
    ))
    return rows


def annotate_segment_buckets(rows, enabled, low_overlap, high_overlap):
    for row in rows:
        row["vad_bucket"] = (
            classify_segment_bucket(row, low_overlap, high_overlap)
            if enabled else ""
        )


def classify_segment_bucket(row, low_overlap, high_overlap):
    prefix = "empty" if row["empty"] else "high_cer"
    overlap = row.get("vad_overlap_ratio")
    if overlap is None:
        return f"{prefix}_no_vad_data"
    if overlap < low_overlap:
        return f"{prefix}_low_vad_overlap"
    if overlap >= high_overlap:
        return f"{prefix}_high_vad_overlap"
    return f"{prefix}_mid_vad_overlap"


def bucket_interpretation(bucket):
    if bucket.endswith("_no_vad_data"):
        return "missing VAD metrics"
    if bucket.startswith("empty_low"):
        return "VAD or segmentation miss candidate"
    if bucket.startswith("empty_high"):
        return "ASR empty decode candidate"
    if bucket.startswith("high_cer_low"):
        return "boundary or segmentation candidate"
    if bucket.startswith("high_cer_high"):
        return "ASR quality candidate"
    return "mixed cause candidate"


def segment_bucket_summary(rows):
    groups = defaultdict(list)
    for row in rows:
        bucket = row.get("vad_bucket")
        if bucket:
            groups[bucket].append(row)

    summaries = []
    for bucket, bucket_rows in sorted(groups.items()):
        cer_values = [row["cer"] for row in bucket_rows if row.get("cer") is not None]
        vad_values = [
            row["vad_overlap_ratio"]
            for row in bucket_rows
            if row.get("vad_overlap_ratio") is not None
        ]
        summaries.append({
            "bucket": bucket,
            "interpretation": bucket_interpretation(bucket),
            "segment_count": len(bucket_rows),
            "sample_count": len({row["sample_id"] for row in bucket_rows}),
            "empty_count": sum(1 for row in bucket_rows if row["empty"]),
            "reference_length": sum(row["reference_length"] for row in bucket_rows),
            "hypothesis_length": sum(row["hypothesis_length"] for row in bucket_rows),
            "mean_cer": sum(cer_values) / len(cer_values) if cer_values else None,
            "mean_vad_overlap": sum(vad_values) / len(vad_values) if vad_values else None,
        })
    return summaries


def add_vad_overlap(row, vad_metrics, vad_engine):
    vad_metric = vad_metrics.get((normalize_id(row["sample_id"]), vad_engine))
    if vad_metric is None:
        row["vad_overlap_seconds"] = None
        row["vad_overlap_ratio"] = None
        row["vad_nearest_gap_seconds"] = None
        row["vad_chunk_count"] = 0
        row["vad_chunks"] = ""
        return

    chunks = sorted(vad_metric.get("chunks", []), key=lambda chunk: float(chunk.get("start_seconds") or 0))
    overlaps = []
    overlap_seconds = 0.0
    nearest_gap = None
    for chunk in chunks:
        start = float(chunk.get("start_seconds") or 0)
        end = float(chunk.get("end_seconds") or 0)
        overlap = max(0.0, min(row["end_seconds"], end) - max(row["start_seconds"], start))
        if overlap > 0:
            overlaps.append((start, end))
            overlap_seconds += overlap
        else:
            gap = min(abs(row["start_seconds"] - end), abs(start - row["end_seconds"]))
            nearest_gap = gap if nearest_gap is None else min(nearest_gap, gap)

    bounded_overlap = min(row["duration_seconds"], overlap_seconds)
    row["vad_overlap_seconds"] = bounded_overlap
    row["vad_overlap_ratio"] = bounded_overlap / row["duration_seconds"] if row["duration_seconds"] else None
    row["vad_nearest_gap_seconds"] = 0.0 if overlaps else nearest_gap
    row["vad_chunk_count"] = len(overlaps)
    row["vad_chunks"] = compact_ranges(overlaps)


def compact_ranges(ranges, limit=3):
    if not ranges:
        return ""
    head = [f"{start:.1f}-{end:.1f}" for start, end in ranges[:limit]]
    if len(ranges) > limit:
        head.append(f"+{len(ranges) - limit}")
    return "; ".join(head)


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
        "| Engine | Sample | # | Time | Dur | CER | Empty | Ref len | Ref cps | Hyp len | Hyp cps | VAD overlap | Bucket | VAD gap | VAD chunks | Reference | Hypothesis |",
        "| --- | --- | ---: | --- | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | --- | ---: | --- | --- | --- |",
    ]
    for row in rows:
        lines.append(
            "| {engine} | {sample} | {index} | {time} | {duration} | {cer} | {empty} | {ref_len} | {ref_cps} | {hyp_len} | {hyp_cps} | {vad_overlap} | {bucket} | {vad_gap} | {vad_chunks} | {reference} | {hypothesis} |".format(
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
                vad_overlap=fmt_percent(row["vad_overlap_ratio"]),
                bucket=row.get("vad_bucket") or "",
                vad_gap=fmt_float(row["vad_nearest_gap_seconds"]),
                vad_chunks=escape_markdown_cell(row["vad_chunks"]),
                reference=escape_markdown_cell(row["reference"]),
                hypothesis=escape_markdown_cell(row["hypothesis"]),
            )
        )
    return "\n".join(lines)


def bucket_markdown_table(rows):
    lines = [
        "| Bucket | Meaning | Segments | Samples | Empty | Mean CER | Mean VAD overlap | Ref len | Hyp len |",
        "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for row in rows:
        lines.append(
            "| {bucket} | {meaning} | {segments} | {samples} | {empty} | {cer} | {vad_overlap} | {ref_len} | {hyp_len} |".format(
                bucket=row["bucket"],
                meaning=row["interpretation"],
                segments=row["segment_count"],
                samples=row["sample_count"],
                empty=row["empty_count"],
                cer=fmt_percent(row["mean_cer"]),
                vad_overlap=fmt_percent(row["mean_vad_overlap"]),
                ref_len=row["reference_length"],
                hyp_len=row["hypothesis_length"],
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
        "vad_overlap_seconds",
        "vad_overlap_ratio",
        "vad_bucket",
        "vad_nearest_gap_seconds",
        "vad_chunk_count",
        "vad_chunks",
        "reference",
        "hypothesis",
        "metrics_file",
    ]
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def write_bucket_csv(path, rows):
    fieldnames = [
        "bucket",
        "interpretation",
        "segment_count",
        "sample_count",
        "empty_count",
        "reference_length",
        "hypothesis_length",
        "mean_cer",
        "mean_vad_overlap",
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
    vad_metrics = load_vad_metrics(args.vad_root)
    rows = summarize_by_engine(metrics)
    table = markdown_table(rows)
    all_segment_rows = segment_diagnostics(
        metrics,
        min_cer=args.segment_min_cer,
        vad_metrics=vad_metrics,
        vad_engine=args.vad_engine,
    )
    annotate_segment_buckets(
        all_segment_rows,
        enabled=args.vad_root is not None,
        low_overlap=args.vad_low_overlap,
        high_overlap=args.vad_high_overlap,
    )
    segment_rows = all_segment_rows[:max(0, args.segment_limit)]
    segment_table = segment_markdown_table(segment_rows)
    bucket_rows = segment_bucket_summary(all_segment_rows)
    bucket_table = bucket_markdown_table(bucket_rows)
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
        print(f"segment diagnostics: {len(segment_rows)} shown / {len(all_segment_rows)} total")
        if args.vad_root is not None:
            print(f"vad metrics loaded: {len(vad_metrics)}")
        print()
        print(segment_table)
        if bucket_rows:
            print()
            print(bucket_table)

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
        if bucket_rows:
            (root / "segment_buckets.md").write_text(bucket_table + "\n", encoding="utf-8")
            write_bucket_csv(root / "segment_buckets.csv", bucket_rows)
            print(f"wrote: {root / 'segment_buckets.md'}")
            print(f"wrote: {root / 'segment_buckets.csv'}")

    return 0 if metrics else 1


if __name__ == "__main__":
    raise SystemExit(main())
