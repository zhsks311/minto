# STT PoC summary

## Goal

Find a free or local-first Korean STT path for meeting transcription. Paid cloud STT is intentionally out of scope for this round.

## Current decision

- Try Apple SpeechAnalyzer first on supported macOS because the current local probe now resolves `ko-KR` to `ko_KR` and the 120s meeting CER is best.
- Keep the current app path on WhisperKit `openai_whisper-large-v3-v20240930_turbo` after live-check rollback; retain the 626MB result rows as measured PoC baselines.
- Keep MLX Nemotron as a research candidate because the 120s CER is better than WhisperKit, but integration requires a Python/MLX sidecar or a larger native port.
- Keep sherpa-onnx Korean Zipformer as a latency-first experimental path only.
- Revisit BatiSay only when downloadable CT2/GGML/CoreML/MLX files or a local export are available.

## Measured candidates

| Candidate | Status | 120s meeting CER | Latency / RTF | Decision |
| --- | --- | ---: | --- | --- |
| Apple SpeechAnalyzer final | measured | `12.3%` | RTF `0.006` | first integration PoC, gated by macOS support |
| MLX Nemotron 8-bit offline | measured | `16.4%` | RTF `0.030` | research candidate |
| MLX Nemotron bf16 offline | measured | `16.4%` | RTF `0.036` | research candidate |
| WhisperKit large-v3 626MB rolling preview/final | measured | `25.1%` | preview RTF p50/p95 `0.12 / 0.14`, final RTF p50/p95 `0.17 / 0.19` | measured baseline |
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

## 외부 참고 벤치마크 — 한국어 콜센터 ASR (mz-moonzoo)

출처: https://mz-moonzoo.tistory.com/133

> **주의: 우리 "Measured candidates" 표와 같은 줄에 합치지 말 것.** 측정 데이터셋·정규화·파인튜닝 여부가 모두 달라 CER 숫자가 직접 비교되지 않는다. 아래는 *콜센터 도메인에서 모델 계열별 경향*을 참고하기 위한 외부 데이터다.

| 모델 | 파라미터 | 구분 | CER |
| --- | --- | --- | ---: |
| Qwen3-ASR-1.7B | 1.7B | Base | `22.72%` |
| Qwen3-ASR-0.6B | 0.6B | Base | `26.49%` |
| Faster-whisper-large-v3-turbo | large-v3-turbo | Base | `27.70%` |
| Qwen3-ASR-1.7B | 1.7B | Fine-tuned | `7.41%` |
| Faster-whisper-large-v3-turbo | large-v3-turbo | Fine-tuned | `11.53%` |

측정 조건(우리와 다른 점):

- **데이터셋**: 실제 콜센터 상담 녹취 약 10,000건(겹치는 발화·배경 노이즈 포함). 우리는 회의 WAV 120초 윈도우.
- **레퍼런스 정규화**: 숫자/영어를 한글로 변환(예: `123` → `일이삼`), 한글 발음 표준화 수동 전사. 우리 SMI 레퍼런스와 정규화 규칙이 달라 CER 절대값 비교 불가.
- **메트릭**: CER만. **추론 속도(RTF) 미측정**(GPU 리소스 경쟁). 우리 표의 RTF/latency에 해당하는 값 없음.
- **파인튜닝 포함**: Base와 Fine-tuned를 함께 보고. 우리 후보는 모두 파인튜닝 없는 off-the-shelf.

참고 포인트:

- `Faster-whisper-large-v3-turbo`는 우리가 쓰는 WhisperKit `openai_whisper-large-v3-v20240930_turbo`와 **같은 large-v3-turbo 계열**이다. 콜센터 도메인 base CER `27.70%`는 우리 회의 도메인 weighted CER `31.4%`와 자릿수가 비슷하나, 위 정규화 차이로 직접 비교는 금물.
- **Qwen3-ASR**(1.7B/0.6B)는 우리가 측정한 적 없는 신규 후보다. Base에서도 large-v3-turbo보다 낮은 CER를 보였고, 파인튜닝 시 `7.41%`까지 개선 — 향후 한국어 도메인 후보로 검토할 가치가 있으나, on-device(CoreML/MLX) 변환 가능성과 RTF는 미확인이다.

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
