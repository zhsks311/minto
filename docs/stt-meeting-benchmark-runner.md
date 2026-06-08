# STT meeting benchmark runner

`scripts/run_meeting_stt_benchmarks.py` runs `MeetingCorpusTests` across the meeting samples and selected engines.

The runner is intentionally sequential. It favors reproducibility and memory safety over speed.

## List samples

```bash
scripts/run_meeting_stt_benchmarks.py --list-samples
```

## Dry run

```bash
scripts/run_meeting_stt_benchmarks.py \
  --dry-run \
  --samples haengan_20260526 \
  --engines whisper_accurate
```

## Full meeting run

```bash
scripts/run_meeting_stt_benchmarks.py \
  --engines whisper_accurate,speech_analyzer,sf_speech_on_device \
  --max-windows 0
```

Output goes to:

```text
tmp/stt-meeting-benchmarks/<timestamp>/
```

Each engine gets its own output directory so metric files do not overwrite each other.

## Smoke run

```bash
scripts/run_meeting_stt_benchmarks.py \
  --engines whisper_accurate \
  --max-windows 3
```

## Global CER note

For full-duration runs, the runner sets `MEETING_SKIP_SWIFT_GLOBAL_CER=1` by default.

Reason: full-meeting Levenshtein over concatenated text can become very expensive. The common schema still records:

- `micro_cer`
- `macro_cer`
- `rtf`
- `aggregate_rtf`
- `peak_memory_mb`
- per-segment CER

Use `--skip-swift-global-cer never` only for short runs or when the global text size is known to be safe.

## Summarize results

```bash
scripts/summarize_stt_benchmarks.py tmp/stt-meeting-benchmarks/<timestamp> --write
```

This writes:

```text
summary.md
summary.csv
```

If a full-duration run skipped Swift global CER, compute it from saved `*_ref.txt` / `*_hyp.txt` files when the text is small enough:

```bash
scripts/summarize_stt_benchmarks.py tmp/stt-meeting-benchmarks/<timestamp> \
  --compute-missing-global-cer \
  --write
```

To inspect empty final and high-CER windows with duration and text density:

```bash
scripts/summarize_stt_benchmarks.py tmp/stt-meeting-benchmarks/<timestamp> \
  --write-segments \
  --segment-min-cer 0.8
```

If VAD benchmark metrics are available, add overlap columns:

```bash
scripts/summarize_stt_benchmarks.py tmp/stt-meeting-benchmarks/<timestamp> \
  --write-segments \
  --vad-root /private/tmp/minto2-vad-full-smoke \
  --vad-engine energy
```

This writes:

```text
segments.md
segments.csv
```

The summary groups metric files by `engine_id` and reports weighted CER, sample macro CER, RTF, peak memory, empty finals, and false-positive transcript characters.

The segment diagnostics include `Dur`, `Ref cps`, `Hyp cps`, `VAD overlap`, `VAD gap`, and `VAD chunks`.
Use high `Ref cps` empty rows to find windows where the subtitle/reference is dense but the engine returned no final text.
Use low `VAD overlap` to identify segmentation misses, and high `VAD overlap` with empty output to identify decode/model failures.
