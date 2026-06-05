# WhisperKit rolling preview benchmark

## Command

```sh
env RUN_STT_TESTS=1 RUN_STREAMING_BENCH=1 STREAM_MAX_SECONDS=120 \
  CLANG_MODULE_CACHE_PATH=/private/tmp/minto2-preview-clang-cache \
  SWIFTPM_HOME=/private/tmp/minto2-preview-swiftpm-cache \
  swift test -c release --disable-sandbox \
  --scratch-path /private/tmp/minto2-preview-build-release \
  --filter StreamingChunkBenchmarkTests/rollingPreviewFinalBenchmark
```

## Result

- Model: `openai_whisper-large-v3-v20240930_626MB`
- Audio: `haengan_20260526_full.wav`
- Raw dir: package default `sample/meeting/raw`
- Duration: 120.0s
- Preview step/context: 1.0s / 8.0s
- Final window: 5.0s
- Preview events: 120
- Non-empty preview events: 97
- Preview revisions: 89
- Average preview revision edit distance: 13.6
- First preview latency: 6.0s audio-time
- Final events: 24
- Empty finals: 6
- Preview RTF p50/p95: 0.11 / 0.19
- Final RTF p50/p95: 0.16 / 0.20
- Last-preview final edit distance total: 300
- Global CER: 26.0% (distance 67 / ref 258)

## Interpretation

- Speed is sufficient for local preview on this machine: both preview and final RTF are far below 1.0.
- Preview is unstable: 89 revisions across 120 preview events is high.
- First non-empty preview appears late in this file segment because the opening audio is mostly silence/low-energy speech.
- The 120-second sample is a baseline, not a final product metric. Compare against SpeechAnalyzer and sherpa-onnx using the same output fields.
