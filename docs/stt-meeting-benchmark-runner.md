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
segment_buckets.md
segment_buckets.csv
```

The summary groups metric files by `engine_id` and reports weighted CER, sample macro CER, RTF, peak memory, empty finals, and false-positive transcript characters.

The segment diagnostics include `Dur`, `Ref cps`, `Hyp cps`, `VAD overlap`, `VAD gap`, and `VAD chunks`.
Use high `Ref cps` empty rows to find windows where the subtitle/reference is dense but the engine returned no final text.
Use low `VAD overlap` to identify segmentation misses, and high `VAD overlap` with empty output to identify decode/model failures.

To inspect fixed empty-output probes with WhisperKit diagnostics:

```bash
RUN_STT_TESTS=1 \
WHISPER_DIAG_PROBE_SET=sileroFullDuration \
WHISPER_DIAG_PATH=service \
WHISPER_MODEL_FOLDER=/Users/d66hjkxwt9/Documents/huggingface/models/argmaxinc/whisperkit-coreml/openai_whisper-large-v3-v20240930_turbo \
swift test --filter WhisperEmptyClipDiagnosticsTests/rawWhisperKitOutput
```

Useful knobs:

- `WHISPER_DIAG_PATH=direct|service|both`: direct WhisperKit CPU-only path, app `STTService` path, or both.
- `WHISPER_DIAG_LABELS=a,b,c`: run only specific fixed probe labels.
- `WHISPER_DIAG_MAX_CLIPS=1`: smoke a subset before a full diagnostic run.
- `WHISPER_DIAG_VARIANT=logProbNil`: compare decode variants without changing production defaults.

To run the fixed service-empty probes as a matrix and write a manifest, logs, CSV, and Markdown summary:

```bash
scripts/run_whisper_empty_probe_matrix.py \
  --output-root /private/tmp/minto2-whisper-empty-probe-matrix-20260608 \
  --model-folder /Users/d66hjkxwt9/Documents/huggingface/models/argmaxinc/whisperkit-coreml/openai_whisper-large-v3-v20240930_turbo \
  --paths direct,service \
  --variants baseline,logProbNil,tempFallback0,windowClip0 \
  --repeats 1
```

For baseline nondeterminism checks, use repeated baseline runs:

```bash
scripts/run_whisper_empty_probe_matrix.py \
  --output-root /private/tmp/minto2-whisper-empty-probe-baseline-repeat-20260608 \
  --model-folder /Users/d66hjkxwt9/Documents/huggingface/models/argmaxinc/whisperkit-coreml/openai_whisper-large-v3-v20240930_turbo \
  --paths direct,service \
  --variants baseline \
  --repeats 3
```

## VAD benchmark run

Run Energy VAD over every `sample/meeting` pair:

```bash
scripts/run_meeting_vad_benchmarks.py \
  --engines energy \
  --max-seconds 120
```

Output goes to:

```text
tmp/vad-meeting-benchmarks/<timestamp>/
```

Summarize VAD recall and false-positive metrics:

```bash
scripts/summarize_vad_benchmarks.py tmp/vad-meeting-benchmarks/<timestamp> --write
```

This writes:

```text
vad_summary.md
vad_summary.csv
```

Use `--max-seconds 0` for full meeting duration. The default is `120` seconds so regular smoke runs stay short.
Use `--sort duration` when running full-duration benchmarks across all samples. This processes shorter meetings first and avoids waiting on the longest files before getting any full-run evidence.

For full-duration VAD chunk STT runs, the runner sets `VAD_SKIP_SWIFT_GLOBAL_CER=1` by default through `--skip-swift-global-cer auto`.
Reason: concatenated global Levenshtein can become very expensive on 1-3 hour meetings. The metric files still keep per-chunk CER, macro CER, micro CER, RTF, peak memory, empty finals, and false-positive transcript characters.
Use `--skip-swift-global-cer never` only for short full files where the reference and hypothesis text sizes are known to be safe.

Compare Energy and Silero only after FluidAudio/Silero assets are available:

```bash
scripts/run_meeting_vad_benchmarks.py \
  --engines energy,silero \
  --max-seconds 120 \
  --merge-gap-sec 1.1
```

Run an Energy threshold sweep by changing the noise offset. The production default is `10`:

```bash
scripts/run_meeting_vad_benchmarks.py \
  --engines energy \
  --max-seconds 120 \
  --energy-noise-offset-db 6
```

## VAD chunk STT run

To measure whether a VAD policy improves actual WhisperKit chunk CER, run VAD chunk STT mode:

```bash
scripts/run_meeting_vad_benchmarks.py \
  --mode stt \
  --engines energy \
  --stt-engine whisper_accurate \
  --vad-stt-max-chunks 0
```

This mode loads the selected STT engine, so model availability and memory limits apply.
For WhisperKit/CoreML runs, prefer a local model folder and run outside the sandbox when CoreML needs to write E5RT cache files:

```bash
WHISPER_MODEL_FOLDER=/path/to/openai_whisper-large-v3-v20240930_turbo \
scripts/run_meeting_vad_benchmarks.py \
  --mode stt \
  --samples haengan_20260526 \
  --engines energy \
  --stt-engine whisper_accurate \
  --max-seconds 60 \
  --vad-stt-max-chunks 0
```

Summarize the generated STT metric files with the same STT summary script:

```bash
scripts/summarize_stt_benchmarks.py tmp/vad-meeting-benchmarks/<timestamp> --write
```

When the metric files include VAD metadata, the summary groups by VAD config instead of merging every result into the same STT engine row.

For VAD chunk STT comparisons, use `Full Global CER` as the primary VAD decision metric.
The regular `Global CER` is computed only from references inside emitted VAD chunks, so missed speech outside those chunks is not counted as deletion.
`Full Global CER` compares the whole benchmark-window reference against the concatenated VAD chunk hypotheses.

To sweep Silero candidates, keep the same sample scope and change one variable at a time:

```bash
WHISPER_MODEL_FOLDER=/path/to/openai_whisper-large-v3-v20240930_turbo \
scripts/run_meeting_vad_benchmarks.py \
  --mode stt \
  --engines silero \
  --stt-engine whisper_accurate \
  --max-seconds 120 \
  --vad-stt-max-chunks 0 \
  --silero-threshold 0.6 \
  --merge-gap-sec 1.1
```
