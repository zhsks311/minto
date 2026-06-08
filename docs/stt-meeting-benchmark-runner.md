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
  --max-windows 0 \
  --sort duration
```

Output goes to:

```text
tmp/stt-meeting-benchmarks/<timestamp>/
```

Each engine gets its own output directory so metric files do not overwrite each other.
Use `--sort duration` for full-duration runs across all samples. This processes shorter meetings first and avoids waiting on the longest files before getting any full-run evidence.

WhisperKit/CoreML full-duration runs need write access to the E5RT cache under `~/Library/Caches/swiftpm-testing-helper`.
If the process cannot write there, WhisperKit can load the model and still fail on the first decode with `.pixelBufferFailed`.

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

The segment diagnostics include `Dur`, `dB`, `Ref cps`, `Hyp cps`, `VAD overlap`, `VAD gap`, and `VAD chunks`.
Use high `Ref cps` empty rows to find windows where the subtitle/reference is dense but the engine returned no final text.
Use low `VAD overlap` to identify segmentation misses, and high `VAD overlap` with empty output to identify decode/model failures.
When `--vad-stt-repair-pad-sec` is enabled, segment diagnostics also include `Repair`, `Repair dur`, `Repair dB`, `Repair ref`, and `Repair FP`.
Use these columns to separate useful empty-final repair from accepted repair chunks that only add false-positive text.

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

The service-path summary also records `service_skip_count`, `service_skip_reasons`, and `service_skip_details`.
Use these fields to separate raw WhisperKit empty output from app-side filters such as `energy_gate`, `avg_logprob`, `compression_ratio`, and `low_energy_short_phantom`.
The Markdown summary includes empty counts by run and by label, so repeated probes can show whether a clip always fails or only fails intermittently.
Use `--pad-seconds 0.5` to expand each fixed probe clip by 0.5s on both sides when checking whether empty output is caused by a tight chunk boundary.

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

To test targeted empty-final boundary repair in VAD chunk STT mode, retry only empty STT chunks with a wider source-audio boundary:

```bash
WHISPER_MODEL_FOLDER=/path/to/openai_whisper-large-v3-v20240930_turbo \
scripts/run_meeting_vad_benchmarks.py \
  --mode stt \
  --engines silero \
  --stt-engine whisper_accurate \
  --max-seconds 120 \
  --vad-stt-max-chunks 0 \
  --silero-threshold 0.6 \
  --merge-gap-sec 1.1 \
  --vad-stt-repair-pad-sec 1.0
```

This is a benchmark-only knob. It does not change the normal product path unless product code later adds the same retry policy behind explicit safety conditions.
Judge it with `Full Global CER`, empty final count, false-positive transcript chars, RTF, and peak memory.

To test a narrower benchmark-only repair guard, skip retry for very short or very low-energy empty chunks:

```bash
WHISPER_MODEL_FOLDER=/path/to/openai_whisper-large-v3-v20240930_turbo \
scripts/run_meeting_vad_benchmarks.py \
  --mode stt \
  --engines silero \
  --stt-engine whisper_accurate \
  --max-seconds 120 \
  --vad-stt-max-chunks 0 \
  --silero-threshold 0.6 \
  --merge-gap-sec 1.1 \
  --vad-stt-repair-pad-sec 1.0 \
  --vad-stt-repair-min-chunk-sec 2.0 \
  --vad-stt-repair-min-audio-db -35
```

Recent 120s segmentation sweep, all with `threshold=0.6` and `merge gap=1.1`:

| Candidate | Weighted CER | Full Global CER | Empty | FP chars | RTF | Peak MB | Result |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| baseline: padding 0.12, min speech 0.25, merge max 15 | 36.9% | 19.9% | 9 | 41 | 0.107 | 849.0 | current candidate |
| speech padding 0.30 | 40.5% | 24.0% | 10 | 41 | 0.109 | 802.8 | reject |
| speech padding 1.00 mean of 3 | 38.2% | 20.4% | 7.7 | 18 | 0.105 | 1143.1 | reject as default; targeted repair candidate |
| padding 0.12 + empty repair 1.00 mean of 3 | 34.0% | 16.6% | 5.3 | 41 | 0.123 | 1018.5 | short3 full candidate |
| min speech 0.50 | 37.0% | 20.1% | 8 | 41 | 0.111 | 719.0 | weak, not default |
| merge max 20 | 34.0% | 19.5% | 9 | 41 | 0.097 | 687.3 | repeat check required |

`merge max 20` repeat check, same 7 samples and 120s scope:

| Run | Weighted CER | Full Global CER | Empty | FP chars | RTF | Peak MB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| repeat1 | 34.0% | 19.5% | 9 | 41 | 0.097 | 687.3 |
| repeat2 | 36.0% | 21.6% | 10 | 41 | 0.099 | 930.2 |
| repeat3 | 34.1% | 19.5% | 9 | 41 | 0.124 | 911.4 |

Decision: do not promote `merge max 20` and do not spend a full-duration short3 run on it yet.
Weighted CER improved in all three repeats, but `Full Global CER` did not improve consistently and empty finals did not drop.
For VAD policy selection, prefer `Full Global CER` over chunk-only weighted CER because missed speech outside emitted chunks is counted only in the full-reference comparison.

120s repair pad repeat check, same 7 samples and 120s scope:

| Candidate | Weighted CER mean | Full Global CER mean | Empty mean | FP chars mean | RTF mean | Peak MB mean | Result |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| repair off | 36.9% | 19.9% | 9.0 | 41.0 | 0.107 | 849.0 | baseline |
| empty repair 1.00 mean of 3 | 34.0% | 16.6% | 5.3 | 41.0 | 0.123 | 1018.5 | short3/all7 checked, not default |
| empty repair 0.75 mean of 3 | 34.3% | 17.1% | 4.7 | 44.3 | 0.123 | 1171.6 | reject; not safer than 1.00 |

Decision: do not promote `empty repair 0.75`.
It reduced empty finals slightly versus `1.00`, but had worse `Full Global CER`, higher false-positive text, and higher peak memory.
Next inspect accepted repair chunks and test stricter guard conditions instead of shrinking the pad again.

Repair telemetry smoke:

- Scope: `재정경제기획위원회_20260430`, first 120s, Silero `threshold=0.6`, `merge gap=1.1`, `repair pad=1.0`.
- Result root: `/private/tmp/minto2-vad-stt-telemetry-smoke`.
- Result: 11 chunks, repair attempted 3, accepted 2, repair false positives 0, empty final 1.
- `segments.md` now shows per-chunk source `dB`, repair status, repair duration, repair `dB`, whether the repair chunk had reference text, and whether the accepted repair was a false positive.

Repair guard candidate check:

Scope: all seven `sample/meeting` samples, first 120s, Silero `threshold=0.6`, `merge gap=1.1`, `repair pad=1.0`, guard `min chunk=2.0s`, `min audio=-35dB`.

| Run | Weighted CER | Full Global CER | Empty | FP chars | RTF | Peak MB | Repair attempted | Accepted | Guard skipped |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| guard repeat1 | 33.9% | 17.1% | 5 | 41 | 0.166 | 526.1 | 5 | 5 | 5 |
| guard repeat2 | 34.4% | 15.5% | 7 | 41 | 0.258 | 520.6 | 4 | 2 | 5 |
| guard repeat3 | 34.3% | 15.6% | 7 | 41 | 0.160 | 751.0 | 6 | 4 | 5 |
| guard mean | 34.2% | 16.1% | 6.3 | 41 | 0.194 | 599.2 | 5.0 | 3.7 | 5.0 |

Decision: keep this as a candidate, but do not promote it to short3 yet.
It consistently skips five obvious low-energy/short retries and keeps repair false positives at zero in the 120s runs.
However, compared with the previous no-guard `repair pad=1.0` mean, empty finals are slightly worse and RTF is not clearly better, so this guard needs either another threshold candidate or a controlled repeat against no-guard in the same run batch.

Weaker guard candidate A:

Scope: all seven `sample/meeting` samples, first 120s, Silero `threshold=0.6`, `merge gap=1.1`, `repair pad=1.0`, guard `min chunk=1.0s`, `min audio=-45dB`.

| Candidate | Weighted CER | Full Global CER | Empty | FP chars | RTF | Peak MB | Repair attempted | Accepted | Guard skipped | Result |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| no-guard reference run | 36.4% | 18.9% | 7 | 41 | 0.174 | 729.1 | 11 | 4 | 0 | reference only |
| guard `2.0s/-35dB` repeat1 | 33.9% | 17.1% | 5 | 41 | 0.166 | 526.1 | 5 | 5 | 5 | stronger guard |
| guard `1.0s/-45dB` repeat1 | 36.0% | 18.4% | 7 | 41 | 0.158 | 605.3 | 9 | 6 | 4 | prune |

Decision: prune `1.0s/-45dB` for now.
It is less aggressive, but it keeps too many retry attempts while not reducing empty finals in the first run.
Do not spend repeat2/repeat3 on this candidate unless a later no-guard control batch shows the comparison was unfair.

Full-duration short3 repair check:

Scope: `본회의_20260428`, `본회의_20260508`, `재정경제기획위원회_20260430`, full duration, Silero `threshold=0.6`, `merge gap=1.1`, `merge max=15`, WhisperKit turbo.

| Candidate | Weighted CER | Macro CER | Global CER | Full Global CER | Empty | FP chars | RTF | Peak MB | Result |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| final-only 20s window | 56.5% | 52.9% | 48.4% | n/a | 75 | 0 | 0.135 | 300.0 | comparison baseline |
| repair off | 37.9% | 35.1% | 28.8% | 21.9% | 42 | 22 | 0.113 | 419.3 | baseline |
| empty repair 1.00 | 30.7% | 29.3% | 22.4% | 14.8% | 9 | 35 | 0.140 | 420.8 | promote to all7 full check |

Final-only short3 sample-level result:

| Sample | CER | Global CER | Empty | RTF | Peak MB |
| --- | ---: | ---: | ---: | ---: | ---: |
| 본회의_20260428 | 48.4% | 45.5% | 12 | 0.120 | 232.5 |
| 본회의_20260508 | 44.3% | 41.0% | 22 | 0.121 | 255.3 |
| 재정경제기획위원회_20260430 | 66.0% | 58.7% | 41 | 0.150 | 300.0 |

Decision: keep the final-only 20s window path as a comparison baseline only.
On the same short3 set, Silero VAD chunk STT beats it on CER, global CER, and empty finals even before repair.

Sample-level `Full Global CER`:

| Sample | Repair off | Empty repair 1.00 | Empty off -> repair | Repair accepted |
| --- | ---: | ---: | ---: | ---: |
| 본회의_20260428 | 17.2% | 13.0% | 8 -> 2 | 4/6 |
| 본회의_20260508 | 8.2% | 6.8% | 5 -> 1 | 4/5 |
| 재정경제기획위원회_20260430 | 30.8% | 19.6% | 29 -> 6 | 21/27 |

Decision: `empty repair 1.00` is not a product default yet. It passed short3 on CER and empty finals, but RTF rose from `0.113` to `0.140` and false-positive text rose from `22` to `35` chars.
Next run it on all seven full-duration samples with memory-safe sequential execution.

Full-duration all7 repair check:

Scope: all seven `sample/meeting` samples, full duration, Silero `threshold=0.6`, `merge gap=1.1`, `merge max=15`, WhisperKit turbo, Swift global CER skipped.

| Candidate | Weighted CER | Macro CER | Empty | FP chars | RTF | Peak MB | Result |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| repair off | 46.1% | 42.0% | 329 | 508 | 0.121 | 1120.4 | baseline |
| empty repair 1.00 | 42.6% | 37.9% | 133 | 628 | 0.129 | 1673.3 | improves CER/empty, not default |

Sample-level all7 comparison:

| Sample | Repair off CER | Repair CER | Empty off -> repair | FP off -> repair | Repair accepted |
| --- | ---: | ---: | ---: | ---: | ---: |
| 본회의_20260428 | 34.7% | 29.4% | 8 -> 3 | 9 -> 9 | 5/8 |
| 본회의_20260508 | 24.5% | 22.6% | 5 -> 1 | 0 -> 2 | 3/4 |
| 재정경제기획위원회_20260430 | 46.3% | 37.4% | 29 -> 9 | 13 -> 24 | 19/28 |
| 재정경제기획위원회_20260429 | 49.3% | 44.3% | 87 -> 33 | 103 -> 175 | 63/96 |
| haengan_20260526 | 40.3% | 39.0% | 55 -> 29 | 149 -> 156 | 30/59 |
| 외교통일위원회_20260520 | 53.8% | 50.4% | 75 -> 19 | 9 -> 9 | 50/69 |
| 본회의_20260423 | 45.5% | 42.6% | 70 -> 39 | 225 -> 253 | 34/73 |

Decision: do not promote `empty repair 1.00` to default.
It improved weighted CER for all seven samples and cut empty finals by `196`, but increased false-positive text by `120` chars, RTF by `0.008`, and peak memory by about `553MB`.
Next test a smaller repair pad or narrower guard before product wiring.
