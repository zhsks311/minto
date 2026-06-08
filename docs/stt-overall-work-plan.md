# STT 전체 작업 계획

작성일: 2026-06-08

## 목적

Minto를 비싼 회의록 앱의 무료/로컬 우선 대안으로 만든다. 핵심은 STT 엔진, 실시간 표시, 회의록 후처리를 섞지 않고 각각 숫자로 검증하는 것이다.

- 한국어 회의 전사의 CER를 낮춘다.
- 녹음 중에는 빠르게 반응하고, 녹음 종료 시에는 마지막 발화가 사라지지 않게 한다.
- 모델별 CER, RTF, latency, peak memory를 같은 기준으로 비교한다.
- 회의록 정리는 개인 OAuth LLM 또는 로컬 LLM을 선택하게 하되, STT 정확도 평가와 분리한다.
- 기본값 변경은 느낌이 아니라 `sample/meeting` 전체 결과로 결정한다.

## 현재 확정된 상태

현재 브랜치는 구조 개선을 시작할 수 있는 상태다. 대수술보다 측정 가능한 개선을 작은 단위로 쌓는 쪽이 맞다.

- `STTService`는 앱이 보는 facade 역할을 한다.
- `SpeechTranscriptionEngine`이 있고, WhisperKit, SpeechAnalyzer, SFSpeech 구현이 분리되어 있다.
- 현재 기본 fallback은 `openai_whisper-large-v3-v20240930_turbo` 기반 WhisperKit turbo다.
- `VoiceActivityDetector` 경계와 `VADProcessor.flushPending()`이 있다.
- `stopRecordingAndDrain()`은 VAD 잔여 청크를 final 전사까지 drain하도록 테스트가 고정되어 있다.
- final STT가 empty일 때 기존 preview를 즉시 지우지 않는 테스트가 있다.
- `TranscriptNormalizer`가 저장/export 경로에 붙어 있고, 원문 chunk를 그대로 회의록 줄로 저장하는 문제를 줄인다.
- VAD/STT benchmark는 per-chunk CER뿐 아니라 global CER와 aggregate RTF를 봐야 한다.

## 2026-06-08 측정 업데이트

`sample/meeting` 전체 7개 샘플을 같은 조건으로 짧게 자른 120초 기준선을 먼저 만들었다. 전체 회의 실행 전 리소스와 runner 경로를 검증하기 위한 중간 기준선이다.

- 실행 범위: `sample/meeting/raw` 7샘플, `MEETING_MAX_WINDOWS=6`, 20초 window.
- 실행 엔진: `whisper_accurate` / `openai_whisper-large-v3-v20240930_turbo`.
- 결과 위치: `/private/tmp/minto2-bench-whisper-120s`.
- 결과: 7/7 성공, weighted CER 49.1%, macro CER 50.1%, mean global CER 43.7%, RTF 0.144, peak memory 710.688MB, empty final 6, false-positive chars 0.
- 해석: 초반 120초 window는 자막 비verbatim, 의사진행 발화, 짧은 창, 빈 출력 영향이 커서 절대 품질 결론으로 쓰면 안 된다. 같은 조건의 엔진 간 A/B 비교 기준선으로만 사용한다.

같은 runner로 Apple 엔진 smoke도 확인했다.

- `sf_speech_on_device`: 현재 시스템에서 "Apple 음성 인식 권한이 거부" 상태라 1샘플 smoke가 load 단계에서 실패했다.
- `speech_analyzer`: 현재 테스트 플랫폼은 `arm64e-apple-macos14.0`이고, 한국어 SpeechAnalyzer 지원을 찾지 못해 1샘플 smoke가 load 단계에서 실패했다.
- 결론: 이 Mac의 현재 상태에서는 WhisperKit turbo만 재현 가능한 benchmark 대상이다. SFSpeech는 권한/Dictation 상태를 풀고 다시 측정해야 하고, SpeechAnalyzer는 macOS 26+ 지원 환경에서 다시 측정해야 한다.

## 핵심 판단

true streaming은 일부 streaming 지원 엔진에만 적용한다.

- WhisperKit, SFSpeech file/request, Nemotron offline sidecar는 one-shot final 엔진이다.
- WhisperKit rolling preview는 반복 재전사 기반 preview이지 true streaming이 아니다.
- SpeechAnalyzer streaming, sherpa streaming, FluidAudio streaming 계열처럼 session cache와 partial/final event를 제공하는 엔진만 streaming 경로에 태운다.
- one-shot과 streaming을 하나의 protocol에 억지로 맞추면 기존 안정성이 흔들린다.
- STT 정확도 개선, transcript 가독성 개선, LLM 회의록 품질 개선은 서로 다른 metric으로 평가한다.

## 목표 구조

목표 파이프라인은 다음 형태다.

> AudioSource
> → Segmenter/VAD
> → TranscriptionCoordinator
> → one-shot engine 또는 streaming engine
> → TranscriptAssembler
> → raw transcript store
> → TranscriptNormalizer
> → LLM correction / summary / export

역할은 이렇게 나눈다.

- `STTService`: 엔진 선택, 로딩 상태, availability, fallback, cache recovery를 담당한다.
- `SpeechTranscriptionEngine`: one-shot final 전사 경계다. WhisperKit, SFSpeech, SpeechAnalyzer final-only, Nemotron sidecar가 이쪽이다.
- `StreamingTranscriptionEngine`: true streaming 엔진 전용 경계다. continuous sample input, partial callback, final callback, finish/reset lifecycle을 가진다.
- `VoiceActivityDetector`: 음성 구간 후보를 만든다. Energy VAD와 Silero VAD를 같은 계약으로 비교한다.
- `TranscriptionCoordinator`: VAD chunk, one-shot final, streaming event를 한 곳에서 조율한다. 지금 `TranscriptionViewModel`에 있는 흐름을 점진적으로 옮길 대상이다.
- `TranscriptAssembler`: preview/final 전환, empty final, partial revision, timestamp 보존을 담당한다.
- `TranscriptNormalizer`: 저장/export용 문단 정리다. CER 개선으로 계산하지 않는다.
- `MeetingNoteProcessor`: 개인 OAuth LLM 또는 로컬 LLM 후처리다. STT 엔진과 분리한다.

## 우선순위

### P0. 현재 기준선 고정

**상태**

- 완료에 가깝다. 지금은 이 기준선을 깨지 않는 것이 중요하다.

**목표**

- WhisperKit turbo 기본 경로를 유지한다.
- stop/drain, preview empty-final, normalizer, benchmark metric 테스트를 기준선으로 고정한다.
- 미추적 보고서/디자인 파일은 별도 산출물로 두고 코드 변경과 섞지 않는다.

**검증**

- `swift test --disable-sandbox`
- `git diff --check`

**성공 기준**

- 기존 기본 엔진이 `openai_whisper-large-v3-v20240930_turbo`로 유지된다.
- stop 직전 짧은 발화가 drain된다.
- final empty가 preview를 조용히 지우지 않는다.
- 저장/export는 `TranscriptNormalizer`를 지난다.

### P1. benchmark 하니스 표준화

**상태**

- 진행 중이다. 엔진 논쟁을 끝내려면 먼저 측정 형식을 고정해야 한다.
- `STTBenchmarkRunMetric` / `STTBenchmarkSegmentMetric` schema v1을 추가했다.
- `MeetingCorpusTests`, `VADBenchmarkTests`의 STT 측정, `StreamingChunkBenchmarkTests`는 같은 top-level schema로 JSON을 쓴다.
- `peak_memory_mb`는 macOS `getrusage` 기반 peak RSS 스냅샷으로 기록한다.
- `scripts/run_meeting_stt_benchmarks.py`로 `sample/meeting` 샘플과 엔진을 순차 실행할 수 있다.
- `scripts/summarize_stt_benchmarks.py`로 실행 결과를 엔진별 weighted CER/RTF/peak memory 표로 요약할 수 있다.

**작업**

- 모든 STT benchmark output을 같은 schema로 맞춘다.
- 결과는 `tmp/`에 저장하고, 사람이 읽는 요약만 `docs/`에 남긴다.
- 긴 샘플은 병렬 수를 제한해 메모리 폭주를 막는다.
- 전체 회의 실행에서는 Swift global CER를 자동 skip하고, per-window micro/macro CER와 peak memory를 먼저 본다.
- benchmark runner는 같은 샘플을 다음 축으로 분리해 실행한다.
  - 60초 smoke
  - 120초 비교
  - `sample/meeting` 전체
  - streaming chunk 실험

**공통 metric**

- engine id
- model id
- sample id
- reference length
- hypothesis length
- per-sample CER
- macro CER
- micro CER
- global CER
- empty final count
- false-positive transcript chars
- elapsed seconds
- RTF
- aggregate RTF
- peak memory
- supports preview

**streaming metric**

- first partial latency
- partial revision count
- final latency
- final CER
- unstable partial ratio
- long session memory growth

**검증**

- WhisperKit turbo, SpeechAnalyzer, SFSpeech on-device가 같은 schema를 생성한다.
- preview 미지원 엔진은 실패하지 않고 `supports_preview=false`로 기록된다.
- 메모리 부족으로 Mac이 꺼지지 않도록 동시 실행 수 제한이 동작한다.

**성공 기준**

- "어떤 엔진이 낫다"는 판단을 같은 샘플, 같은 metric으로 재현할 수 있다.

### P2. final-only 엔진 제품 후보 결정

**목표**

- 현재 제품 기본 경로는 final-only 품질부터 안정화한다.
- macOS 26 이상은 SpeechAnalyzer를 1순위 후보로 보되, 기본값 변경은 전체 샘플 결과 이후로 미룬다.

**작업**

- WhisperKit turbo를 baseline으로 고정한다.
- SpeechAnalyzer final-only 경로의 availability gate를 제품 UX와 연결한다.
  - OS 버전
  - Korean locale 지원
  - language asset 설치 상태
  - 권한 상태
- SFSpeech on-device는 보조 Apple-native 후보로만 둔다.
- unsupported 환경은 WhisperKit turbo fallback으로 간다.
- 모델 선택 UI에는 "왜 비활성인지"를 설명 가능한 상태로 노출한다.

**검증**

- `sample/meeting` 전체 CER
- 10분 이상 긴 파일 batch
- asset 미설치 상태
- OS 미지원 상태
- 권한 거부 상태
- 실제 앱 녹음 종료 flow

**성공 기준**

- SpeechAnalyzer가 지원 환경에서 WhisperKit turbo보다 CER 또는 latency가 명확히 좋다.
- 미지원 환경에서 조용히 실패하지 않고 fallback이 동작한다.
- SFSpeech는 1분 제한, on-device 가능 여부, 긴 파일 안정성 검증 없이는 기본값으로 올리지 않는다.

### P3. VAD와 segmentation 개선

**목표**

- 짧은 발화와 stop 직전 발화 누락을 줄인다.
- 잡음 chunk 증가와 hallucination 증가를 막는다.

**작업**

- Energy VAD를 현재 기본값으로 유지한다.
- Silero VAD는 후보 adapter로만 붙인다.
- short utterance probe set을 유지한다.
  - 0.5초 미만
  - 0.8초 전후
  - 짧은 대답
  - 말 끝이 바로 녹음 종료되는 케이스
- chunk merge 정책을 명시적으로 분리한다.
  - min duration
  - max duration
  - merge gap
  - speech probability threshold
- ASR-aware segmentation을 실험한다. VAD recall이 좋아도 STT CER가 나빠지면 기본값으로 올리지 않는다.

**현재 60초 smoke 결과**

- energy VAD + WhisperKit turbo: chunk CER 35.8%, global CER 31.2%, empty final 1, false-positive text 1 chunk / 13 chars.
- Silero VAD + gap merge 1.1초 + WhisperKit turbo: chunk CER 54.5%, global CER 31.8%, empty final 1, false-positive text 0.
- 해석: Silero는 false-positive를 줄일 가능성이 있지만, chunk 경계가 잘게 나뉘면 WhisperKit final CER가 나빠질 수 있다. 기본값 변경은 아직 금지다.

**검증**

- short utterance recall
- false-positive chunk count
- false-positive transcript chars
- empty final count
- per-chunk CER
- global CER
- stop/drain 누락 여부

**성공 기준**

- 짧은 발화 recall이 오른다.
- global CER가 악화되지 않는다.
- false-positive transcript가 늘지 않는다.

### P4. 녹음 종료와 후처리 안정성

**목표**

- 사용자가 본 preview, 저장된 final, correction, summary, export가 종료 시점에 서로 어긋나지 않게 한다.

**현재 고정된 것**

- `stopRecordingAndDrain()`은 audio stop 이후 VAD `flushPending()`을 호출하고 final chunk를 전사 queue에 넣는다.
- final STT가 empty이면 기존 preview를 즉시 지우지 않는다.
- `finalizeMeeting()`은 마지막 correction task를 기다린 뒤 최종 summary를 만든다.

**남은 작업**

- correction batch flush 이후 summary incremental이 진행 중일 때 종료 UX가 어떻게 보이는지 테스트한다.
- LLM provider가 none, 실패, timeout일 때 저장/export가 원문 fallback으로 끝나는지 테스트한다.
- finalizing 상태에서 사용자가 다시 녹음을 시작하거나 창을 닫는 경로를 테스트한다.
- stop 직전 enqueue된 main queue audio buffer가 실제 기기에서도 누락되지 않는지 수동 QA한다.

**검증**

- stop 직전 0.5초/0.8초 발화 저장 여부
- preview-only 상태 유지 여부
- correction 실패 fallback
- summary 실패 fallback
- 저장 record와 report export의 transcript 일치

**성공 기준**

- 짧은 마지막 말이 사라지지 않는다.
- final empty 때문에 UI가 비어 보이지 않는다.
- LLM 실패가 회의 저장 실패로 번지지 않는다.

### P5. true streaming 경로 추가

**목표**

- streaming 지원 엔진만 session lifecycle을 사용한다.
- one-shot 엔진의 기존 성능과 안정성을 유지한다.

**작업**

- `StreamingTranscriptionEngine` protocol을 추가한다.
  - `startSession()`
  - `accept(samples:)`
  - `finish()`
  - `resetSession()`
  - partial callback
  - final callback
- `TranscriptionCoordinator`가 capability에 따라 경로를 나눈다.
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
- one-shot engine은 기존 benchmark 결과가 악화되지 않는다.
- streaming이 정확도를 망치면 UI preview 실험에만 남기고 기본값으로 올리지 않는다.

### P6. Nemotron MLX sidecar 연구

**목표**

- Nemotron은 앱 기본 엔진이 아니라 고정확도 연구 엔진으로 검증한다.
- Python/MLX sidecar로 붙일 때의 현실성을 숫자로 판단한다.

**작업**

- Python sidecar를 앱 밖 프로세스로 둔다.
- Swift 앱은 localhost HTTP, stdin/stdout, 또는 Unix domain socket 중 하나로 요청한다.
- 처음에는 final chunk 전용으로만 붙인다.
- 8-bit 또는 더 작은 quantized 모델을 우선 검증한다.
- worker warm-up, queue limit, timeout, crash restart를 둔다.
- peak memory와 cold start latency를 필수 metric으로 기록한다.

**검증**

- `sample/meeting` 전체 CER
- current VAD chunk CER
- 60초 offline chunk CER와 실제 앱 chunk CER 차이
- cold start latency
- warm start latency
- peak memory
- 30분 반복 실행
- worker crash 후 WhisperKit fallback

**성공 기준**

- WhisperKit/SpeechAnalyzer 대비 CER 이득이 실제 앱 chunk에서도 유지된다.
- 메모리 사용량이 사용자 Mac에서 안전하다.
- sidecar 장애가 앱 UI를 멈추지 않는다.

**중단 기준**

- peak memory가 과도하다.
- dependency 설치와 모델 관리가 일반 사용자가 감당하기 어렵다.
- crash isolation이 안 된다.
- 정확도 이득이 전체 샘플에서 재현되지 않는다.

### P7. transcript normalization과 회의록 후처리

**목표**

- 원문 transcript와 사용자에게 보여줄 회의록 문단을 분리한다.
- STT 정확도와 회의록 가독성을 따로 개선한다.

**작업**

- 현재 `TranscriptNormalizer`를 유지하되, sample 기반 regression set을 늘린다.
- 원문 segment는 그대로 보존한다.
- 저장/export 문단만 병합, 줄바꿈, 문장 정리를 적용한다.
- LLM correction은 별도 단계로 둔다.
- 개인 OAuth LLM과 로컬 LLM을 후처리 옵션으로 둔다.
- LLM 비용이 없는 경로에서도 기본 회의록이 읽을 만해야 한다.

**검증**

- 원문 보존 여부
- normalized paragraph 수
- 너무 긴 줄/너무 짧은 줄 비율
- dangling ending 감소율
- export 수동 QA
- LLM 실패 시 원문 fallback

**성공 기준**

- CER는 그대로여도 읽기 좋은 회의록이 된다.
- "정확도가 좋아졌다"와 "읽기 좋아졌다"를 분리해서 설명할 수 있다.

### P8. diarization PoC

**목표**

- 회의록 앱에서 중요한 "누가 말했는가"를 STT 다음 축으로 검증한다.

**작업**

- audio offset을 모든 segment에 보존한다.
- offline diarization을 먼저 붙인다.
- speaker timeline과 transcript segment를 overlap으로 매칭한다.
- FluidAudio diarization 또는 다른 local diarization 후보를 benchmark 전용으로 비교한다.
- streaming diarization은 후순위로 둔다.

**검증**

- speaker segment 수
- speaker switch 탐지
- transcript-speaker overlap matching
- 수동 label 샘플 품질
- speaker label이 틀렸을 때 UI/export가 망가지지 않는지

**성공 기준**

- speaker label이 틀려도 원문 transcript를 훼손하지 않는다.
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
- 동일 조건에서 최소 2회 재실행해 큰 변동이 없다.

## 채택 판단표

| 후보 | 지금 역할 | 바로 default 가능 여부 | 다음 판단 기준 |
| --- | --- | --- | --- |
| WhisperKit turbo | 기본 fallback | 유지 | 전체 sample/meeting baseline 고정 |
| SpeechAnalyzer | macOS 26+ 1순위 후보 | 아직 보류 | 전체 CER, asset/locale fallback, final-only 안정성 |
| SFSpeech on-device | Apple-native 보조 후보 | 보류 | 긴 파일 안정성, 권한/asset 상태, 1분 제한 확인 |
| Silero VAD | VAD 후보 | 보류 | short recall 이득과 global CER 동시 개선 |
| Nemotron MLX | 고정확도 연구 후보 | 불가 | peak memory, sidecar 안정성, 전체 CER 재현 |
| FluidAudio ASR | streaming/Swift 구조 참고 후보 | 불가 | 한국어 CER, RTF, memory, 실제 streaming 지표 |
| diarization | 회의록 UX 후보 | 불가 | speaker label 품질과 transcript 매칭 안정성 |

## 바로 다음 작업 순서

1. WhisperKit turbo를 `sample/meeting` 전체 duration으로 순차 실행한다.
2. SFSpeech 권한/Dictation 상태를 복구한 뒤 같은 120초 runner로 다시 smoke를 돌린다.
3. macOS 26+ 환경에서 SpeechAnalyzer 한국어 asset 상태를 확인하고 같은 120초 runner로 smoke를 돌린다.
4. Apple 엔진 smoke가 통과한 환경에서 `sample/meeting` 전체를 WhisperKit turbo, SpeechAnalyzer, SFSpeech on-device 기준으로 안전한 동시성에서 다시 측정한다.
5. 같은 runner로 VAD energy와 Silero 후보를 비교하되, per-chunk CER와 global CER를 함께 본다.
6. SpeechAnalyzer final-only 제품 gate를 UI/설정 상태와 연결한다.
7. correction/summary/export 종료 flow 회귀 테스트를 추가한다.
8. `StreamingTranscriptionEngine` protocol과 `TranscriptionCoordinator` 설계를 문서화한 뒤, streaming 지원 엔진 하나만 hidden PoC로 붙인다.
9. Nemotron MLX sidecar는 별도 worker로 benchmark만 붙이고, 앱 기본 엔진 후보와 분리한다.
10. diarization은 audio offset 보존 작업 이후 offline PoC로 시작한다.

## 당장 하지 않을 것

- Silero VAD를 바로 기본값으로 바꾸지 않는다.
- Nemotron을 앱 내부 Swift 엔진처럼 바로 붙이지 않는다.
- WhisperKit을 true streaming 엔진처럼 포장하지 않는다.
- LLM correction 결과를 CER 개선으로 보고하지 않는다.
- 60초 또는 120초 샘플만 보고 default를 바꾸지 않는다.
- 여러 무거운 모델을 무제한 병렬 실행하지 않는다.
- 유료 클라우드 STT를 기본 전제에 넣지 않는다.

## 최종 제품 방향

- macOS 26 이상: SpeechAnalyzer를 우선 후보로 제시하고, 실패하면 WhisperKit turbo fallback.
- macOS 14-25: WhisperKit turbo를 안정 기본값으로 유지하고, SFSpeech on-device는 선택지로 검증.
- 고정확도 실험 모드: Nemotron MLX sidecar를 사용자가 명시적으로 켤 수 있게 검토.
- 전사 이후: 원문 보존 + normalizer + 개인 OAuth LLM/로컬 LLM 회의록 정리.
- 장기 목표: true streaming 엔진이 충분히 정확해질 때만 session 기반 실시간 경로를 제품 기본 경험으로 승격.
