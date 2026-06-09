# ADR 0003: System Audio Input Foundation

상태: Accepted
작성일: 2026-06-09

## Context

Minto2는 화상회의 상대방 소리를 전사하기 위해 마이크 외의 시스템 오디오 입력을 지원해야 한다. 기존 live recording 경로는 `AudioSourceProtocol` 하나를 `TranscriptionViewModel`에 주입하고, source가 내보내는 16kHz mono float sample을 VAD pipeline으로 전달한다.

## Decision

시스템 오디오 입력은 기존 live recording pipeline을 바꾸지 않고 `AudioSourceProtocol` 구현체로 확장한다.

- `AudioInputMode`는 `microphone`, `systemAudio`, `mixed` 세 모드를 표현하되, 1차 UI 선택지는 `microphone`, `systemAudio`로 제한한다.
- `TranscriptionViewModel`은 녹음 시작 전 선택한 input mode에 맞는 source를 `AudioSourceFactory`에서 받아 교체한다.
- `SystemAudioSource`는 ScreenCaptureKit `SCStream`을 사용하고 `SCStreamConfiguration.capturesAudio = true`, `excludesCurrentProcessAudio = true`, `sampleRate = 16000`, `channelCount = 1`로 설정한다.
- `SystemAudioSource`는 `SCStreamOutputType.audio` sample buffer를 float PCM으로 변환해 sample handler queue에서 기존 `onBuffer`/`onLevel` callback으로 전달한다.
- `TranscriptionViewModel`은 source callback을 받을 때 MainActor로 hop해 기존 UI/VAD state 경계를 유지한다.
- `SystemAudioSource.stop()` 이후 들어오는 sample/error callback은 capture state gate로 무시한다.
- `mixed`는 실제 mixer가 생기기 전까지 `UnavailableAudioSource`로 막는다. Echo cancellation이나 정교한 동기화 mix는 실제 회의 fixture로 품질을 본 뒤 별도 작업으로 둔다.
- 권한이 없거나 ScreenCaptureKit이 시작되지 않으면 `AudioSourceError.screenCapturePermissionDenied` 또는 `systemAudioUnavailable`로 UI에 전달한다.

## Alternatives

- `TranscriptionViewModel` 내부에서 ScreenCaptureKit을 직접 다룸
  - 장점: 빠르게 붙일 수 있다.
  - 단점: UI state, recording orchestration, OS capture adapter가 섞인다.
  - 기각 이유: 기존 `AudioSourceProtocol` 확장 지점을 무너뜨린다.
- 가상 오디오 드라이버 설치 안내
  - 장점: OS 버전 차이를 줄일 수 있다.
  - 단점: 설치 부담과 권한/보안 UX가 커진다.
  - 기각 이유: macOS 14 기준 1차 목표는 앱 자체 ScreenCaptureKit 경로다.
- 마이크+시스템을 즉시 sample-accurate mixer로 구현
  - 장점: 하나의 시간축으로 VAD에 전달된다.
  - 단점: 두 source의 callback cadence, silence behavior, drift 처리를 먼저 검증해야 한다.
  - 기각 이유: 1차 목표는 입력 가능성 확보이며 echo/mix 최적화는 후속 측정 항목이다.

## Consequences

### Positive

- 마이크-only 기존 경로는 기본값으로 유지된다.
- 시스템 오디오 capture adapter는 독립 파일로 되돌릴 수 있다.
- 기존 VAD/STT/요약 pipeline과 저장 경로를 재사용한다.

### Negative

- 권한 상태 사전 판별 UI는 아직 시작 실패 후 안내 중심이다.
- `mixed` 모드는 아직 선택할 수 없다.
- 실제 입력 감지는 사용자가 녹음을 시작해야 level meter로 확인할 수 있다.

## Verification

- `swift build --disable-sandbox --scratch-path /tmp/minto2-system-audio-build`
- `swift test --disable-sandbox --scratch-path /tmp/minto2-system-audio-test --filter 'AudioInputMode|TranscriptionViewModelStopTests'`
- `git diff --check`
- 후속 수동 QA: 화면/오디오 캡처 권한 없음, 권한 있음, 화상회의 앱 출력 감지, 마이크-only 회귀
