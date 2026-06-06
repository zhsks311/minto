# STT PoC summary

## Goal

Find a free or local-first Korean STT path for meeting transcription. Paid cloud STT is intentionally out of scope for this round.

## Current decision

- Try Apple SpeechAnalyzer first on supported macOS because the current local probe now resolves `ko-KR` to `ko_KR` and the 120s meeting CER is best.
- Keep WhisperKit `openai_whisper-large-v3-v20240930_626MB` as the fallback/default for older macOS and the current app path.
- Keep MLX Nemotron as a research candidate because the 120s CER is better than WhisperKit, but integration requires a Python/MLX sidecar or a larger native port.
- Keep sherpa-onnx Korean Zipformer as a latency-first experimental path only.
- Revisit BatiSay only when downloadable CT2/GGML/CoreML/MLX files or a local export are available.

## Measured candidates

| Candidate | Status | 120s meeting CER | Latency / RTF | Decision |
| --- | --- | ---: | --- | --- |
| Apple SpeechAnalyzer final | measured | `12.3%` | RTF `0.006` | first integration PoC, gated by macOS support |
| MLX Nemotron 8-bit offline | measured | `16.4%` | RTF `0.030` | research candidate |
| MLX Nemotron bf16 offline | measured | `16.4%` | RTF `0.036` | research candidate |
| WhisperKit large-v3 626MB rolling preview/final | measured | `25.1%` | preview RTF p50/p95 `0.12 / 0.14`, final RTF p50/p95 `0.17 / 0.19` | fallback/default |
| sherpa-onnx Korean Zipformer chunk 16 | measured | `27.5%` | RTF `0.040`, first partial `8.32s` | latency experiment |
| sherpa-onnx Korean Zipformer chunk 32 | measured | `27.2%` | RTF `0.031`, first partial `8.96s` | latency experiment |
| sherpa-onnx Korean Zipformer chunk 64 | measured | `26.3%` | RTF `0.025`, first partial `10.24s` | latency experiment |
| BatiSay ko base | blocked | n/a | n/a | model files not exposed |

## Expanded 7-sample check

Every `sample/meeting/raw/*_full.wav` file with a matching SMI reference was measured on the first 120 seconds.

| Candidate | Weighted CER | Macro CER | Latency metric |
| --- | ---: | ---: | --- |
| Apple SpeechAnalyzer final | `16.1%` | `16.5%` | mean RTF `0.006` |
| MLX Nemotron 8-bit offline | `23.8%` | `24.1%` | mean RTF `0.023` |
| WhisperKit large-v3 626MB rolling preview/final | `31.4%` | `31.0%` | final RTF p50 mean `0.20` |
| sherpa-onnx Korean Zipformer chunk 64 | `37.5%` | `37.3%` | mean RTF `0.014` |

SpeechAnalyzer had the lowest CER on all seven samples. The expanded batch strengthens the current decision rather than changing it.

## Notes

- These current numbers are from `sample/meeting/raw/본회의_20260508_full.wav` and its SMI reference. Older rows used `haengan_20260526_full.wav`.
- The expanded 7-sample check uses the same first-120s window for each available meeting WAV/SMI pair.
- Apple SpeechAnalyzer final transcription is the best current result, but volatile streaming results need assembly/debounce before replacing live preview.
- WhisperKit preview is fast enough on this machine but unstable: `96` preview revisions across `120` preview events.
- sherpa-onnx is a true streaming recognizer and is fast, but this meeting sample CER is worse than SpeechAnalyzer, Nemotron, and WhisperKit.
- MLX Nemotron is not WhisperKit-compatible. It requires `mlx-audio` GitHub main and should be treated as a sidecar/native-port research lane.
- BatiSay's HuggingFace repository currently exposes only `.gitattributes`, `README.md`, and `sanity_check.py` through `huggingface_hub.list_repo_files("batiai/batisay-ko-base")`.
- The current local SpeechAnalyzer probe resolves `ko-KR` to `ko_KR`; the earlier unsupported-locale result is stale in this environment.

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
