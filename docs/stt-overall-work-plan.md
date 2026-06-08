# STT 전체 작업 계획

작성일: 2026-06-08

## 목적

Minto의 전사 파이프라인을 비싼 회의록 앱 대체가 가능한 무료/로컬 우선 구조로 개선한다.

핵심 목표는 네 가지다.

- 한국어 회의 전사의 CER를 낮춘다.
- 사용 중에는 실시간처럼 보이고, 녹음 종료 시에는 final이 안정적으로 남게 한다.
- 모델별 메모리와 지연 시간을 숫자로 관리한다.
- 회의록 정리 단계는 개인 OAuth LLM 또는 로컬 LLM을 선택할 수 있게 하되, STT 정확도 평가와 섞지 않는다.

## 현재 구조 판단

현재 main 반영 이후 구조는 예전보다 좋아졌다. 그래서 다음 작업은 대수술보다 "측정 가능한 개선" 중심으로 가야 한다.

- `STTService`는 이미 facade 역할을 한다.
- `SpeechTranscriptionEngine` 경계가 있고, WhisperKit / SpeechAnalyzer / SFSpeech 구현이 분리되어 있다.
- WhisperKit turbo는 현재 기본 fallback으로 유지하는 것이 맞다.
- `VoiceActivityDetector` 경계와 `VADProcessor.flushPending()`이 이미 들어와 있다.
- `TranscriptionViewModel`은 preview와 final을 분리해 다루지만, true streaming session 구조는 아직 없다.
- Silero VAD는 테스트 타깃 PoC로만 보는 것이 맞다. 짧은 발화 recall은 좋아졌지만, chunk가 잘게 쪼개지면서 WhisperKit final CER가 나빠질 수 있다.
- SpeechAnalyzer는 macOS 26 이상에서 가장 유력한 Apple-native 후보지만, 지원 OS/asset/locale fallback이 제품 통합 비용이다.
- Nemotron MLX는 정확도 연구 후보이지, 지금 바로 앱 기본 엔진으로 넣을 후보는 아니다. Python sidecar, peak memory, crash isolation 검증이 먼저다.

## 중요한 전제

true streaming은 일부 streaming 지원 엔진에만 적용한다.

- WhisperKit, SFSpeech file/request, Nemotron offline sidecar는 기본적으로 one-shot final 엔진으로 취급한다.
- WhisperKit의 rolling preview는 "반복 재전사 기반 preview"이지 true streaming은 아니다.
- SpeechAnalyzer, sherpa streaming, FluidAudio StreamingEouAsrManager 같은 엔진만 `accept(samples:)`, `finish()`, `reset()` lifecycle 후보로 본다.
- 하나의 protocol에 모든 엔진을 억지로 맞추지 않는다. one-shot 경로와 streaming 경로를 분리해야 기존 안정성을 지킬 수 있다.

## 목표 아키텍처

현재 구조를 다음 형태로 확장한다.

> AudioSource
> → VAD/Segmenter
> → TranscriptionCoordinator
> → one-shot engine 또는 streaming engine
> → TranscriptAssembler
> → 원문 transcript store
> → normalizer / LLM correction / export

역할은 이렇게 나눈다.

- `STTService`: 앱이 보는 facade. 엔진 선택, 로딩 상태, fallback, cache recovery를 담당한다.
- `SpeechTranscriptionEngine`: 기존 one-shot final 전사 경계. WhisperKit, SFSpeech, Nemotron sidecar가 이쪽이다.
- `StreamingTranscriptionEngine`: 새로 추가할 streaming 전용 경계. true streaming 엔진만 구현한다.
- `VoiceActivityDetector`: 음성 구간 후보를 만드는 경계. Energy VAD와 Silero VAD를 비교한다.
- `TranscriptAssembler`: preview/final 전환, empty final, partial revision을 안정화한다.
- `TranscriptNormalizer`: 저장/export용 문단 정리. CER 개선과 별도로 평가한다.
- `MeetingNoteProcessor`: 개인 OAuth LLM 또는 로컬 LLM 후처리. STT 엔진과 분리한다.

## 우선순위

### P0. 현재 브랜치 안정화

**목표**

- 현재 작업트리를 컴파일 가능한 상태로 고정한다.
- WhisperKit turbo 기본 경로가 유지되는지 확인한다.
- VAD/STT benchmark에 per-chunk CER와 global CER를 모두 남긴다.

**작업**

- `VADBenchmarkTests`의 global CER 추가 변경을 마무리한다.
- 전체 테스트를 한 번 통과시킨다.
- benchmark JSON schema에 `cer`와 `global_cer`의 의미를 명시한다.
- 현재 미추적 보고서/디자인 파일은 별도 작업으로 남기고 섞지 않는다.

**검증**

- `swift test --disable-sandbox`
- `RUN_STT_TESTS=1 RUN_VAD_STT_BENCH=1 ... VAD_ENGINE=energy ... swift test --filter VADBenchmarkTests/vadChunkSTTCER --disable-sandbox`
- `RUN_STT_TESTS=1 RUN_VAD_STT_BENCH=1 ... VAD_ENGINE=silero ... swift test --filter VADBenchmarkTests/vadChunkSTTCER --disable-sandbox`

**성공 기준**

- 기존 기본 엔진이 `openai_whisper-large-v3-v20240930_turbo`로 유지된다.
- VAD별 결과가 같은 JSON schema로 저장된다.
- Silero가 좋거나 나쁘다는 결론을 per-chunk CER 하나로 내리지 않는다.

**현재 60초 smoke 결과**

- energy VAD + WhisperKit turbo: chunk CER 35.8%, global CER 31.2%, empty final 1, false-positive text 1 chunk / 13 chars.
- Silero VAD + gap merge 1.1초 + WhisperKit turbo: chunk CER 54.5%, global CER 31.8%, empty final 1, false-positive text 0.
- 해석: global CER를 같이 봐야 chunk 경계 페널티를 줄여 비교할 수 있다. 다만 WhisperKit/CoreML 출력 변동이 관찰되므로, 이 단일 smoke만으로 VAD 기본값을 바꾸지 않는다.

### P1. 측정 하니스 표준화

**목표**

- 엔진별 결과를 같은 조건에서 비교한다.
- 120초 샘플, 전체 샘플, streaming chunk 실험을 섞지 않는다.

**작업**

- 모든 STT benchmark output에 공통 필드를 둔다.
  - engine id
  - model id
  - sample id
  - reference length
  - hypothesis length
  - micro CER
  - macro CER
  - global CER
  - empty final count
  - false-positive text count
  - elapsed seconds
  - RTF
  - peak memory
- streaming 후보는 추가로 다음 필드를 둔다.
  - first partial latency
  - partial revision count
  - final latency
  - final CER
  - unstable partial ratio
- benchmark 결과는 `tmp/`에 저장하고, 요약만 `docs/`에 남긴다.

**검증**

- WhisperKit turbo, SpeechAnalyzer, SFSpeech on-device가 같은 schema를 생성한다.
- preview 미지원 엔진은 실패하지 않고 `supports_preview=false`로 기록된다.

**성공 기준**

- "이 모델이 낫다"는 판단을 같은 샘플, 같은 metric으로 재현할 수 있다.

### P2. VAD와 segmentation 개선

**목표**

- 짧은 발화와 stop 직전 발화 누락을 줄인다.
- 잡음 chunk 증가로 hallucination이 늘지 않게 한다.

**작업**

- Energy VAD를 현재 기본값으로 유지한다.
- Silero VAD는 후보 adapter로 유지하고, 기본값 변경은 보류한다.
- short utterance probe set을 만든다.
  - 0.5초 미만
  - 0.8초 전후
  - 짧은 대답
  - 말 끝이 바로 녹음 종료되는 케이스
- `flushPending()`이 stop 직전 발화를 보존하는지 테스트한다.
- chunk merge 정책을 분리한다.
  - min duration
  - max duration
  - merge gap
  - speech probability threshold
- ASR-aware segmentation을 실험한다. VAD recall이 좋아도 STT CER가 나빠지면 기본값으로 올리지 않는다.

**검증**

- short utterance recall
- false-positive chunk count
- false-positive transcript chars
- empty final count
- per-chunk CER
- global CER
- stop/drain 누락 여부

**성공 기준**

- 짧은 발화 recall이 올라간다.
- global CER가 악화되지 않는다.
- false-positive transcript가 늘지 않는다.

### P3. preview/final 상태 안정화

**목표**

- 사용자가 보던 preview가 final empty 때문에 조용히 사라지지 않게 한다.
- 녹음 종료 flow를 cancel-first가 아니라 drain-first로 만든다.

**작업**

- `TranscriptionViewModel`의 stop flow를 명시적으로 정리한다.
  - audio stop 요청
  - VAD `flushPending()`
  - final chunk drain
  - correction batch flush
  - summary flush
  - task cancel
- preview가 있고 final이 empty인 경우 상태 전이를 고정한다.
- final이 들어온 뒤에만 preview를 clear한다.
- empty final을 metric으로 남긴다.

**검증**

- stop 직전 0.5초 발화가 저장되는지 확인한다.
- preview-only 상태가 다음 final 또는 clear event까지 유지되는지 확인한다.
- 녹음 종료 후 correction/summary 누락이 없는지 확인한다.

**성공 기준**

- 짧은 마지막 말이 사라지지 않는다.
- final empty 때문에 UI가 비어 보이지 않는다.

### P4. SpeechAnalyzer 제품 통합 검증

**목표**

- macOS 26 이상에서는 SpeechAnalyzer를 가장 먼저 검증한다.
- 단, 기본값 변경은 전체 샘플 수치와 fallback 안정성을 본 뒤 결정한다.

**작업**

- SpeechAnalyzer engine을 final-only 경로로 먼저 안정화한다.
- availability gate를 제품 UX에 연결한다.
  - OS 버전
  - Korean locale 지원
  - language asset 설치 상태
  - 권한 상태
- volatile partial은 바로 UI 기본값으로 쓰지 않는다.
- unsupported 환경은 WhisperKit fallback으로 간다.

**검증**

- `sample/meeting` 전체 CER
- 10분 이상 긴 파일 batch
- asset 미설치 상태
- OS 미지원 상태
- 실제 앱 녹음 종료 flow

**성공 기준**

- 지원 환경에서 WhisperKit turbo보다 CER 또는 latency가 명확히 좋다.
- 미지원 환경에서 조용히 실패하지 않고 설명 가능한 fallback이 동작한다.

### P5. true streaming 경로 추가

**목표**

- streaming 지원 엔진만 session lifecycle을 사용한다.
- one-shot 엔진의 기존 경로를 흔들지 않는다.

**작업**

- `StreamingTranscriptionEngine` protocol을 추가한다.
  - `startSession()`
  - `accept(samples:)`
  - `finish()`
  - `resetSession()`
  - partial callback
  - final callback
- `STTService` 또는 별도 coordinator에서 engine capability에 따라 경로를 나눈다.
  - one-shot: VAD chunk final + optional rolling preview
  - streaming: continuous samples + engine partial/final event
- rolling preview metric과 true streaming metric을 분리한다.
- 참고 구현은 SpeechAnalyzer streaming, sherpa streaming, FluidAudio streaming 구조를 본다.

**검증**

- first partial latency
- partial revision count
- final latency
- final CER
- long session memory growth
- stop/drain 누락

**성공 기준**

- streaming-capable engine은 chunk 재전사 없이 partial/final을 낸다.
- one-shot engine은 기존 성능과 안정성을 유지한다.

### P6. Nemotron MLX sidecar 연구

**목표**

- Nemotron을 앱 기본 엔진이 아니라 고정확도 연구 엔진으로 검증한다.
- Python/MLX로 붙일 때의 현실성을 숫자로 판단한다.

**작업**

- Python sidecar를 앱 밖 프로세스로 둔다.
- Swift 앱은 localhost HTTP, stdin/stdout, 또는 Unix domain socket 중 하나로 요청한다.
- 처음에는 final chunk 전용으로만 붙인다.
- 8-bit 모델을 우선 검증한다.
- worker warm-up, queue limit, timeout, crash restart를 둔다.
- peak memory를 필수 metric으로 기록한다.

**검증**

- `sample/meeting` 전체 CER
- current VAD chunk CER
- 60초 offline chunk CER와 실제 앱 chunk CER 차이
- cold start latency
- warm start latency
- peak memory
- 30분 반복 실행

**성공 기준**

- WhisperKit/SpeechAnalyzer 대비 CER 이득이 실제 앱 chunk에서도 유지된다.
- 메모리 사용량이 사용자 Mac에서 안전하다.
- sidecar 장애가 앱 UI를 멈추지 않는다.

**중단 기준**

- peak memory가 과도하다.
- Python dependency 설치와 모델 관리가 사용자가 감당하기 어렵다.
- crash isolation이 안 된다.
- 정확도 이득이 전체 샘플에서 재현되지 않는다.

### P7. transcript normalization과 회의록 후처리

**목표**

- STT 원문과 사용자에게 보여줄 회의록 문단을 분리한다.
- 30초 처리 chunk가 그대로 회의록 줄이 되는 문제를 줄인다.

**작업**

- `TranscriptNormalizer`를 pure function으로 둔다.
- 원문 segment는 그대로 보존한다.
- 저장/export 문단만 병합, 줄바꿈, 문장 정리를 적용한다.
- LLM correction은 별도 단계로 둔다.
- 개인 OAuth LLM과 로컬 LLM을 후처리 옵션으로 둔다.

**검증**

- 원문 보존 여부
- normalized paragraph 수
- 너무 긴 줄/너무 짧은 줄 비율
- export 수동 QA
- LLM 실패 시 원문 fallback

**성공 기준**

- CER는 그대로여도 읽기 좋은 회의록이 된다.
- STT 정확도 개선과 회의록 가독성 개선을 분리해 설명할 수 있다.

### P8. diarization PoC

**목표**

- 회의록 앱에서 중요한 "누가 말했는가"를 STT 다음 축으로 검증한다.

**작업**

- audio offset을 모든 segment에 보존한다.
- offline diarization을 먼저 붙인다.
- speaker timeline과 transcript segment를 overlap으로 매칭한다.
- streaming diarization은 후순위로 둔다.

**검증**

- speaker segment 수
- speaker switch 탐지
- transcript-speaker overlap matching
- 수동 label 샘플 품질

**성공 기준**

- speaker label이 틀려서 회의록을 망치지 않는다.
- 저장/export 단계에서 최소한 유용한 speaker 구분을 제공한다.

## 기본값 변경 기준

STT 기본값은 아래 조건을 모두 만족할 때만 바꾼다.

- `sample/meeting` 전체 micro CER가 WhisperKit turbo보다 명확히 낮다.
- 같은 샘플에서 global CER도 개선된다.
- first final latency와 RTF가 현재 UX를 해치지 않는다.
- peak memory가 장시간 회의에서 안전하다.
- 미지원 OS, 권한, 모델 오류에서 fallback이 확실하다.
- preview/final 상태가 흔들리지 않는다.
- 짧은 발화 누락률이 증가하지 않는다.

## 채택 판단표

| 후보 | 지금 역할 | 바로 default 가능 여부 | 다음 판단 기준 |
| --- | --- | --- | --- |
| WhisperKit turbo | 기본 fallback | 유지 | global CER/empty final baseline 고정 |
| SpeechAnalyzer | macOS 26+ 1순위 후보 | 아직 보류 | 전체 CER, asset/locale fallback, final-only 안정성 |
| SFSpeech on-device | Apple-native 보조 후보 | 보류 | 긴 파일 안정성, 권한/asset 상태, 정확도 |
| Silero VAD | VAD 후보 | 보류 | short recall 이득과 global CER 동시 개선 |
| Nemotron MLX | 연구 후보 | 불가 | peak memory, sidecar 안정성, 전체 CER 재현 |
| sherpa/FluidAudio streaming ASR | streaming 구조 참고 | 불가 | 한국어 CER와 실제 streaming 지표 |

## 다음 커밋 단위

1. `test: add global CER to VAD STT metrics`
2. `docs: record VAD global CER findings`
3. `test: standardize STT benchmark schema`
4. `test: add short utterance VAD probes`
5. `fix: drain pending VAD chunk before stopping recording`
6. `fix: stabilize preview state when final STT is empty`
7. `feat: add SpeechAnalyzer final-only integration guard`
8. `feat: add streaming transcription capability boundary`
9. `test: add Nemotron sidecar benchmark runner`
10. `feat: add transcript normalizer`
11. `test: add offline diarization PoC`

## 당장 하지 않을 것

- Silero VAD를 바로 기본값으로 바꾸지 않는다.
- Nemotron을 앱 내부 Swift 엔진처럼 바로 붙이지 않는다.
- WhisperKit을 true streaming 엔진처럼 포장하지 않는다.
- LLM correction 결과를 CER 개선으로 보고하지 않는다.
- 120초 샘플 결과만 보고 default를 바꾸지 않는다.

## 최종 제품 방향

가장 현실적인 제품 구조는 다음이다.

- macOS 26 이상: SpeechAnalyzer를 우선 후보로 제시하고, 실패하면 WhisperKit turbo fallback.
- macOS 14-25: WhisperKit turbo를 안정 기본값으로 유지하고, SFSpeech on-device는 선택지로 검증.
- 고정확도 실험 모드: Nemotron MLX sidecar를 사용자가 명시적으로 켤 수 있게 검토.
- 전사 이후: 원문 보존 + normalizer + 개인 OAuth LLM/로컬 LLM 회의록 정리.
- 장기 목표: true streaming 엔진이 충분히 정확해질 때만 session 기반 실시간 경로를 제품 기본 경험으로 승격.
