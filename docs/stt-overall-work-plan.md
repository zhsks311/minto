# STT overall work plan

## 목적

비싼 회의록 앱을 대체할 수 있도록, Minto의 전사 파이프라인을 무료/로컬 우선 구조로 개선한다.

핵심 목표는 네 가지다.

- 한국어 회의 CER를 낮춘다.
- 실시간처럼 보이는 preview/final 경험을 안정화한다.
- 로컬 실행 비용과 메모리 폭주를 통제한다.
- 사용자가 원하면 개인 OAuth 또는 로컬 LLM으로 회의록 후처리를 붙일 수 있게 한다.

## 현재 판단

- 기본값은 당장 바꾸지 않는다.
- WhisperKit turbo는 안정 fallback으로 유지한다.
- SpeechAnalyzer는 macOS 26 이상에서 가장 먼저 제품 통합을 검증할 후보다.
- Nemotron MLX는 정확도 후보지만, Python sidecar와 메모리 관리가 먼저 검증돼야 한다.
- sherpa 계열은 true streaming 구조 참고용이다. 현재 한국어 CER 기준으로 기본 엔진 후보는 아니다.
- true streaming은 모든 모델에 억지로 적용하지 않는다. 내부 cache/session을 유지하는 엔진에만 `accept`, `finish`, `reset` lifecycle을 붙인다.

## 원칙

1. 정확도 개선과 가독성 개선을 분리한다.
   - CER 개선: STT 엔진, VAD, chunking 문제다.
   - 읽기 좋은 회의록: normalization, LLM correction, paragraph merge 문제다.

2. one-shot 엔진과 true streaming 엔진을 분리한다.
   - one-shot: WhisperKit, SFSpeech file/request 방식, Nemotron offline sidecar.
   - streaming: SpeechAnalyzer, sherpa streaming, FluidAudio streaming ASR처럼 session 상태를 유지하는 엔진.

3. 기본값 변경은 숫자로 결정한다.
   - `sample/meeting` 전체 CER
   - first partial latency
   - final latency / RTF
   - partial revision count
   - empty final count
   - short utterance recall
   - peak memory
   - crash-free long run

4. 제품 구조는 fallback 가능한 형태로 둔다.
   - 새 엔진이 실패하면 WhisperKit으로 돌아갈 수 있어야 한다.
   - 모델 다운로드, 권한, OS availability 실패가 UI에서 설명돼야 한다.

## Phase 0. 현재 작업트리 안정화

### 목표

현재 `experiment/stt-engine-poc` 브랜치에 걸려 있는 STT 엔진 분리 WIP를 컴파일 가능한 상태로 마무리한다.

### 작업

- `STTService`를 facade로 정리한다.
- `SpeechTranscriptionEngine` protocol을 실제 엔진 구현의 공통 경계로 둔다.
- `WhisperKitSTTEngine`, `SpeechAnalyzerSTTEngine`, `SFSpeechOnDeviceSTTEngine`이 각자 load/transcribe를 책임지게 한다.
- `STTService` 안에 남은 옛 WhisperKit/SpeechAnalyzer/SFSpeech 구현 중복을 제거한다.
- `WHISPER_MODEL_FOLDER` 로컬 모델 override는 유지한다.

### 검증

- `swift test --disable-sandbox`
- `RUN_STT_TESTS=1 STT_ENGINE=whisper_accurate WHISPER_MODEL_FOLDER=... MEETING_MAX_WINDOWS=1 swift test --filter MeetingCorpusTests/meetingCorpusCER --disable-sandbox`
- 기존 default engine이 `openai_whisper-large-v3-v20240930_turbo`로 유지되는지 확인

### 성공 기준

- 앱 호출부는 `STTService`를 그대로 사용한다.
- 기본 WhisperKit 전사 결과가 1-window smoke에서 기존 baseline과 크게 어긋나지 않는다.
- 새 엔진 추가가 `STTService` 대수술 없이 가능해진다.

## Phase 1. 측정 하니스 표준화

### 목표

엔진마다 다른 방식으로 나온 숫자를 같은 표로 비교할 수 있게 만든다.

### 작업

- `STT_ENGINE` 기반 테스트 선택을 유지한다.
- `sample/meeting` 전체를 대상으로 engine별 결과 JSON을 같은 schema로 저장한다.
- 각 window마다 다음 값을 저장한다.
  - reference text
  - hypothesis text
  - CER
  - elapsed seconds
  - RTF
  - empty 여부
  - engine id
  - model id
- streaming 후보는 추가로 다음 값을 저장한다.
  - first partial latency
  - partial revision count
  - final latency
  - final CER
- peak memory는 별도 runner에서 수집한다.

### 검증

- WhisperKit turbo, SpeechAnalyzer, SFSpeech on-device가 같은 output schema를 생성한다.
- 일부 engine이 preview를 지원하지 않아도 테스트가 실패하지 않고 `supports_preview=false`로 기록된다.

### 성공 기준

- "이 엔진이 낫다"는 말을 숫자와 파일로 재현할 수 있다.
- 전체 샘플, 120초 샘플, streaming chunk 실험이 서로 섞이지 않는다.

## Phase 2. SpeechAnalyzer 제품 통합 검증

### 목표

macOS 26 이상에서 SpeechAnalyzer를 실제 후보로 쓸 수 있는지 검증한다.

### 작업

- SpeechAnalyzer engine을 `STTService` 선택지로 완성한다.
- availability gate를 명확히 한다.
  - OS 버전
  - 한국어 locale 지원
  - language asset availability
  - 권한/설정 실패 메시지
- preview 정책을 별도로 둔다.
  - 처음에는 final-only로 붙인다.
  - volatile partial은 바로 UI에 넣지 않는다.
  - partial을 쓸 경우 debounce와 revision 안정화 규칙을 둔다.

### 검증

- `sample/meeting` 전체 CER
- 10분 이상 긴 파일 batch
- 실제 앱 녹음 종료 drain
- OS 미지원 환경 fallback

### 성공 기준

- 지원되는 Mac에서는 WhisperKit보다 CER 또는 latency가 명확히 좋다.
- 지원되지 않는 Mac에서는 조용히 WhisperKit fallback으로 돌아간다.
- preview/final 전환에서 텍스트가 사라지지 않는다.

## Phase 3. VAD 개선과 짧은 발화 누락 방지

### 목표

STT 모델 이전에 "무엇을 전사에 넣을지"를 개선한다.

### 작업

- `VoiceActivityDetector` protocol을 만든다.
- 기존 `VADProcessor`를 `EnergyVADProcessor` 역할로 유지한다.
- FluidAudio Silero VAD는 별도 adapter로 PoC한다.
- `flushPending()` 계약을 테스트로 고정한다.
- 0.8초 / 0.5초 미만 발화 probe set을 만든다.
- threshold 변경은 바로 제품 기본값으로 넣지 않고 A/B한다.

### 검증

- short utterance recall
- false positive chunk count
- hallucination 증가 여부
- final empty count
- stop 직전 발화 보존 여부
- 전체 CER 변화

### 성공 기준

- 짧은 대답과 stop 직전 발화 누락이 줄어든다.
- 잡음 chunk 증가로 hallucination이 늘어나지 않는다.

## Phase 4. true streaming 구조 도입

### 목표

streaming 지원 엔진만 session 기반 lifecycle로 다룰 수 있게 한다.

### 작업

- `SpeechTranscriptionEngine` 옆에 streaming 전용 protocol을 추가한다.
  - `startSession`
  - `accept(samples:)`
  - `finish()`
  - `resetSession()`
  - partial callback
  - final callback
- one-shot 엔진은 이 protocol을 구현하지 않는다.
- `TranscriptionViewModel`은 engine capability에 따라 경로를 나눈다.
  - one-shot: 현재 VAD final chunk + optional preview
  - streaming: continuous samples + engine final event
- rolling window preview와 true streaming partial을 metric에서 분리한다.

### 검증

- first partial latency
- partial revision count
- final CER
- stop/drain 누락
- long session memory growth

### 성공 기준

- streaming-capable engine은 chunk 재전사 없이 partial/final을 낸다.
- one-shot engine의 기존 안정성은 유지된다.

## Phase 5. Nemotron MLX sidecar 검증

### 목표

Nemotron을 "기본값 후보"가 아니라 "고정확도 연구 엔진"으로 안전하게 검증한다.

### 작업

- Python/MLX sidecar를 앱 밖 프로세스로 둔다.
- Swift 앱은 stdin/stdout, HTTP localhost, 또는 Unix domain socket으로 요청한다.
- 초기에는 final chunk 전용으로만 붙인다.
- 모델은 8-bit 우선으로 메모리 상한을 둔다.
- worker warm-up, queue limit, timeout, crash restart 정책을 둔다.

### 검증

- `sample/meeting` 전체 CER
- 5초/15초 current VAD chunk CER
- 60초 offline chunk CER와 차이
- peak memory
- worker cold start / warm start latency
- 30분 이상 반복 실행

### 성공 기준

- WhisperKit/SpeechAnalyzer 대비 CER 이득이 실제 앱 chunk에서도 유지된다.
- peak memory가 사용자 Mac에서 안전한 범위에 들어온다.
- sidecar 장애가 앱 UI를 멈추지 않는다.

## Phase 6. transcript normalization과 회의록 품질

### 목표

30초 처리 chunk가 그대로 회의록 줄이 되는 문제를 줄이고, 전사 결과를 읽기 쉬운 회의록으로 바꾼다.

### 작업

- 저장/export 전용 `TranscriptNormalizer` pure function을 추가한다.
- STT 원문 segment와 표시/export paragraph를 분리한다.
- LLM correction은 STT 정확도 지표와 섞지 않는다.
- 개인 OAuth 또는 로컬 LLM 선택지를 후처리 단계에 둔다.

### 검증

- 원문 보존
- normalized paragraph 수
- 너무 긴 줄/짧은 줄 비율
- export 결과 수동 QA
- LLM 실패 시 원문 fallback

### 성공 기준

- 전사 원문은 잃지 않는다.
- 사용자가 보는 회의록은 chunk 경계보다 문장/주제 흐름에 가깝다.

## Phase 7. diarization PoC

### 목표

회의록 앱 체감 품질에 중요한 "누가 말했는가"를 별도 축으로 검증한다.

### 작업

- `AudioChunk`와 `Segment`에 audio offset을 보존한다.
- 회의 종료 후 offline diarization을 먼저 붙인다.
- speaker timeline과 transcript segment를 overlap으로 매칭한다.
- 실시간 diarization은 offline 품질 확인 뒤 후순위로 둔다.

### 검증

- speaker segment 수
- speaker switch 탐지
- transcript-speaker overlap matching
- 수동 label 샘플 품질

### 성공 기준

- speaker label이 틀려서 회의록을 망치지 않는다.
- 최소한 저장/export 단계에서 유용한 speaker 구분을 제공한다.

## 우선순위

### P0. 지금 바로 해야 할 것

- 현재 STT 엔진 분리 WIP를 완성하고 테스트 통과.
- 기존 WhisperKit turbo 기본 경로 보존.

### P1. 다음으로 해야 할 것

- 측정 하니스 표준화.
- SpeechAnalyzer final-only 제품 통합 검증.
- VAD flush/short utterance 테스트 고정.

### P2. 숫자 보고 결정할 것

- Silero VAD를 기본 VAD로 승격할지.
- SpeechAnalyzer를 지원 OS에서 추천/default로 올릴지.
- Nemotron sidecar를 연구 엔진에서 사용자 선택지로 올릴지.

### P3. 후순위

- true streaming protocol과 streaming UI.
- offline diarization.
- FluidAudio ASR 후보 추가 benchmark.

## 기본값 변경 기준

기본 STT 엔진은 다음 조건을 모두 만족할 때만 바꾼다.

- `sample/meeting` 전체 micro CER가 WhisperKit turbo보다 명확히 낮다.
- first final latency가 현재 사용성을 해치지 않는다.
- peak memory가 장시간 회의에서 안전하다.
- 미지원 OS/권한/모델 오류에서 fallback이 확실하다.
- 앱 UI에서 preview/final 상태가 흔들리지 않는다.

## 중단 기준

아래 조건이면 해당 방향은 기본값 후보에서 제외하고 fallback 또는 연구 트랙으로 낮춘다.

- 전체 CER가 좋아도 짧은 발화 누락이 증가한다.
- peak memory 때문에 사용자 Mac이 불안정해질 가능성이 크다.
- sidecar crash가 앱 전사 흐름을 멈춘다.
- preview가 final보다 자주 사라지거나 뒤집힌다.
- 모델/언어 asset 설치 실패를 사용자가 이해할 수 없게 만든다.

## 예상 커밋 단위

1. `refactor: split STT engine implementations`
2. `test: standardize STT benchmark metrics`
3. `feat: add SpeechAnalyzer engine integration`
4. `test: add short utterance VAD probes`
5. `feat: add VAD engine boundary`
6. `test: benchmark Silero VAD candidate`
7. `test: add Nemotron sidecar benchmark runner`
8. `feat: add transcript normalizer`
9. `feat: preserve audio offsets for transcript segments`
10. `test: add offline diarization PoC`
