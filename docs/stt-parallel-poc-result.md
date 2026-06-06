# STT parallel PoC result

## Goal

무료 또는 local-first 한국어 STT 후보를 병렬로 검증하고, 다음 앱 통합 후보를 고른다.

## Test sample

- Audio: `sample/meeting/raw/본회의_20260508_full.wav`
- Reference: `sample/meeting/raw/본회의_20260508_smi.json`
- Main comparison window: first 120 seconds
- Full caption span check: 1069 seconds

## Summary

| Candidate | Status | 120s CER | RTF | Streaming signal | Decision |
| --- | --- | ---: | ---: | --- | --- |
| Apple SpeechAnalyzer final | measured | `12.3%` | `0.006` | native API, but preview assembly needs work | first integration PoC |
| MLX Nemotron bf16 offline | measured | `16.4%` | `0.036` | `stream_generate` exists | research candidate |
| MLX Nemotron 8-bit offline | measured | `16.4%` | `0.030` | not yet stream-measured | research candidate |
| WhisperKit large-v3 626MB rolling | measured | `25.1%` | final p50/p95 `0.17 / 0.19` | measured WhisperKit path | PoC baseline |
| sherpa-onnx Zipformer chunk 64 | measured | `26.3%` | `0.023` | true streaming, first partial `10.24s` | latency experiment only |
| sherpa-onnx Zipformer chunk 32 | measured | `27.2%` | `0.028` | true streaming, first partial `8.96s` | not default |
| sherpa-onnx Zipformer chunk 16 | measured | `27.5%` | `0.040` | true streaming, first partial `8.32s` | not default |
| BatiSay ko base | blocked | n/a | n/a | no current model artifacts | wait for files/export |

## Expanded meeting sample batch

The initial common sample was `본회의_20260508_full.wav`. To check whether the result generalizes, every `sample/meeting/raw/*_full.wav` pair with a matching SMI file was measured on the first 120 seconds.

| Sample | Ref chars | SpeechAnalyzer CER | Nemotron 8-bit CER | sherpa64 CER | WhisperKit 626MB CER | Winner |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| `haengan_20260526` | 258 | `20.2%` | `26.4%` | `33.7%` | `26.0%` | SpeechAnalyzer |
| `본회의_20260423` | 435 | `14.9%` | `21.6%` | `31.3%` | `33.6%` | SpeechAnalyzer |
| `본회의_20260428` | 448 | `8.3%` | `17.9%` | `31.5%` | `31.9%` | SpeechAnalyzer |
| `본회의_20260508` | 415 | `12.3%` | `16.4%` | `26.3%` | `25.1%` | SpeechAnalyzer |
| `외교통일위원회_20260520` | 378 | `25.1%` | `33.9%` | `46.6%` | `30.4%` | SpeechAnalyzer |
| `재정경제기획위원회_20260429` | 477 | `15.5%` | `23.3%` | `42.3%` | `33.8%` | SpeechAnalyzer |
| `재정경제기획위원회_20260430` | 438 | `19.2%` | `29.2%` | `49.3%` | `36.1%` | SpeechAnalyzer |

| Aggregate | SpeechAnalyzer | Nemotron 8-bit | sherpa64 | WhisperKit 626MB |
| --- | ---: | ---: | ---: | ---: |
| Weighted CER | `16.1%` | `23.8%` | `37.5%` | `31.4%` |
| Macro CER | `16.5%` | `24.1%` | `37.3%` | `31.0%` |
| Mean RTF / final p50 | `0.006` | `0.023` | `0.014` | `0.20` |

Notes:

- SpeechAnalyzer won all seven first-120s samples.
- Nemotron 8-bit remained second by aggregate CER, but WhisperKit beat Nemotron on `외교통일위원회_20260520`.
- WhisperKit latency is shown as final-window p50 RTF because it was measured through the app's rolling preview/final harness; the other rows use whole-clip or streaming runner RTF.
- sherpa64 stayed fast but had the weakest CER on this corpus.

## BatiSay

`batiai/batisay-ko-base` is not currently reproducible from the public HuggingFace repo.

Observed public files:

- `.gitattributes`
- `README.md`
- `sanity_check.py`

Failed checks:

- `AutoModel.from_pretrained("batiai/batisay-ko-base", dtype="auto")`
- `pipeline("automatic-speech-recognition", model="batiai/batisay-ko-base")`
- direct checks for `config.json`, `model.safetensors`, `tokenizer.json`, `ggml/*`, and `ct2/*`

The failure is at config/model discovery, before inference:

```text
ValueError: Unrecognized model in batiai/batisay-ko-base.
Should have a `model_type` key in its config.json.
```

Conclusion: BatiSay remains interesting on paper, but this repo cannot produce CER or RTF until real weights or a local CT2/GGML/CoreML/MLX export is available.

## Apple SpeechAnalyzer

The old local probe saying Korean was unsupported is stale for this environment.

Current locale probe:

- `SpeechTranscriber.isAvailable`: `true`
- `supportedLocale(equivalentTo: "ko-KR")`: `ko_KR`
- installed locales include `ko_KR`
- supported locale count: `30`

Measured final transcription:

| Scope | CER | RTF | Elapsed | Events |
| --- | ---: | ---: | ---: | ---: |
| first 30s clipped WAV | `29.2%` | `0.011` | `0.34s` | `2` |
| first 120s clipped WAV | `12.3%` | `0.006` | `0.77s` | `11` |
| full caption span | `4.6%` | `0.006` | `6.07s` | `76` |

Streaming input with `AnalyzerInput` also runs, but volatile results need assembly policy before it can become the live preview path:

- 120s input, 0.64s PCM16 chunks
- partial events: `505`
- partial revisions: `501`
- elapsed: `0.77s`
- reported range was `0.0-120.0` for early events, so first partial audio-time is not trustworthy yet
- latest text was a volatile suffix, not a complete transcript

Conclusion: SpeechAnalyzer is the best next integration PoC, behind a macOS availability gate with WhisperKit fallback.

## MLX Nemotron

Model: `mlx-community/nemotron-3.5-asr-streaming-0.6b`

The model is not WhisperKit-compatible. It requires `mlx-audio` from GitHub main, not just `mlx-whisper`.

Measured 120s results:

| Variant | Mode | CER | RTF | Elapsed | Notes |
| --- | --- | ---: | ---: | ---: | --- |
| bf16 | offline `generate` | `16.4%` | `0.036` | `4.28s` | 1.28GB weights |
| 8-bit | offline `generate` | `16.4%` | `0.030` | `3.60s` | 756MB weights |
| bf16 | `stream_generate`, native chunk | `16.4%` | `0.086` | `10.37s` | 108 events, 79 revisions |
| bf16 | `stream_generate`, chunk 4 | `17.6%` | `0.222` | `26.64s` | 376 events, 184 revisions |
| bf16 | `stream_generate`, chunk 1 | `23.1%` | `0.808` | `96.91s` | too slow/noisy |

Conclusion: Nemotron is a strong research candidate, but it is a Python/MLX sidecar or future Swift MLX integration, not a direct WhisperKit model.

## sherpa-onnx

Model: `kangkyu/icefall-asr-ko-streaming-zipformer-72m`

120s results:

| Chunk | CER | RTF | Elapsed | First partial | Partial revisions |
| --- | ---: | ---: | ---: | ---: | ---: |
| 16 / 0.64s | `27.5%` | `0.040` | `4.80s` | `8.32s` | `124 / 188` |
| 32 / 1.28s | `27.2%` | `0.031` | `3.77s` | `8.96s` | `71 / 94` |
| 64 / 2.56s | `26.3%` | `0.025` | `3.04s` | `10.24s` | `38 / 47` |

Conclusion: true streaming and fast, but this sample does not justify replacing WhisperKit or SpeechAnalyzer.

## STT engine structure

Separate structure PoC completed in `/private/tmp/minto2-stt-engine-structure-poc.lQQtGK`.

Validated:

- `swift build`: passed
- `swift test --filter TranscriptionStateTests`: passed, 8 tests

Recommended first main commit:

- Add an `STTEngine` protocol seam.
- Make `STTService` conform to it.
- Inject the engine into `TranscriptionViewModel`.
- Keep default construction on WhisperKit.
- Add fake engine tests for preview vs final request purpose.

Do not add external Python or streaming adapters in the first commit.

## Decision

1. Build `SpeechAnalyzerSTTEngine` first.
2. Keep WhisperKit as fallback/default for macOS versions where SpeechAnalyzer is unavailable.
3. Keep Nemotron MLX as a sidecar research lane because its 120s CER is better than WhisperKit, but integration risk is higher.
4. Keep sherpa-onnx as a latency-only experiment.
5. Do not spend more time on BatiSay until model artifacts become downloadable.
