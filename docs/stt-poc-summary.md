# STT PoC summary

## Goal

Find a free or local-first Korean STT path for meeting transcription. Paid cloud STT is intentionally out of scope for this round.

## Current decision

- Keep WhisperKit `openai_whisper-large-v3-v20240930_626MB` as the accuracy-first default.
- Keep sherpa-onnx Korean Zipformer as a latency-first experimental path.
- Revisit BatiSay only when downloadable CT2/GGML/CoreML/MLX files or a local export are available.
- Revisit Apple SpeechAnalyzer only when Korean locale support is available on the target OS/device.

## Measured candidates

| Candidate | Status | 120s meeting CER | Latency / RTF | Decision |
| --- | --- | ---: | --- | --- |
| WhisperKit large-v3 626MB rolling preview/final | measured | `26.0%` | preview RTF p50/p95 `0.11 / 0.19`, final RTF p50/p95 `0.16 / 0.20` | keep default |
| sherpa-onnx Korean Zipformer chunk 16 | measured | `33.3%` | RTF `0.024`, first partial `6.4s` | latency experiment |
| sherpa-onnx Korean Zipformer chunk 32 | measured | `34.5%` | RTF `0.017`, first partial `7.68s` | latency experiment |
| sherpa-onnx Korean Zipformer chunk 64 | measured | `33.7%` | RTF `0.013`, first partial `7.68s` | latency experiment |
| BatiSay ko base | blocked | n/a | n/a | model files not exposed |
| Apple SpeechAnalyzer | blocked for Korean | n/a | n/a | `ko-KR` not supported in local probe |

## Notes

- WhisperKit preview is fast enough on this machine but unstable: `89` preview revisions across `120` preview events.
- sherpa-onnx is a true streaming recognizer and is much faster than rolling Whisper windows, but this meeting sample CER is worse than WhisperKit.
- BatiSay's HuggingFace repository currently exposes only `.gitattributes`, `README.md`, and `sanity_check.py` through `huggingface_hub.list_repo_files("batiai/batisay-ko-base")`.
- SpeechAnalyzer API compiles with Xcode 26.5, but `SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "ko-KR"))` returned `nil` in the local probe.

## Main-ready work

- `StreamingChunkBenchmarkTests` adds a manual, gated measurement harness:
  - requires `RUN_STT_TESTS=1`
  - requires `RUN_STREAMING_BENCH=1`
  - defaults to `sample/meeting/raw`
  - prints CER, RTF, first preview latency, preview revision count, empty final count, and last-preview/final edit distance

## Experimental branches

- `poc-batisay-final`: faster-whisper runner and current CT2 availability blocker.
- `poc-speechanalyzer`: SpeechAnalyzer compile/locale support probe.
- `poc-sherpa-stream`: sherpa-onnx Korean streaming runner and chunk 16/32/64 results.
