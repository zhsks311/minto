# STT PoC implementation plan

## Goal

무료 또는 개인 OAuth 기반 회의록 앱을 위해 로컬 STT 후보를 숫자로 비교한다. 유료 클라우드 STT는 기본 범위에서 제외한다.

## Tracks

- Benchmark harness: 모든 후보가 같은 sample/meeting, sample/you 기준으로 CER, RTF, latency, partial revision을 출력한다.
- Korean final STT: 앱 기본값은 `openai_whisper-large-v3-v20240930_turbo`로 두고, `openai_whisper-large-v3-v20240930_626MB`는 PoC 측정 기준선으로 비교한다.
- Streaming preview: 현재 WhisperKit rolling preview/final 구조를 먼저 계측하고, Apple SpeechAnalyzer와 sherpa-onnx는 별도 worktree에서 PoC한다.

## Acceptance

- 수동 STT 테스트는 `RUN_STT_TESTS=1`와 추가 flag 없이는 실행되지 않는다.
- 모델 후보는 `sample/meeting` global CER와 RTF를 모두 출력한다.
- streaming 후보는 preview revision count와 last-preview vs final edit distance를 출력한다.
- main 통합 전에는 `swift test --disable-sandbox`가 통과해야 한다.
