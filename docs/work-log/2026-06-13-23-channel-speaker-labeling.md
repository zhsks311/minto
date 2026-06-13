# 채널 기반 화자 라벨링

날짜: 2026-06-13

## 변경 요약

- `DualAudioBufferMixer`가 mixed PCM과 함께 mic/system RMS 우세 채널을 `MixedChunk`로 반환하도록 변경했다.
- `MixedAudioSource`가 mixed sample-clock 기준 채널 활동 타임라인을 기록하고, 구간별 sample 가중 다수결 조회를 제공하도록 했다.
- `TranscriptionViewModel`이 녹음 시작 시 activity provider를 reset/보관하고, preview/final 공통 `positionedResult`에서 `Segment.speaker`를 채우도록 했다.
- `ChannelSpeakerLabeler`를 추가해 입력 모드별 라벨 규칙을 분리했다.

## 결정

- STT는 기존 mixed PCM에서 1번만 수행한다.
- 마이크 단독 모드는 speaker `nil`을 유지한다.
- 시스템 오디오 단독 모드는 `상대`로 라벨링한다.
- mixed overlap 또는 활동 데이터 없음은 잘못된 라벨보다 무라벨이 낫기 때문에 `nil`로 둔다.
- activity timeline은 최근 10분 또는 20,000 entry까지만 보관한다. final chunk 라벨링은 방출 직후 일어나므로 충분한 여유를 두면서 장시간 세션의 무한 성장을 막기 위한 상한이다.

## 검증

- `./scripts/dev.sh test AudioInputModeTests`: 17 tests passed
- `./scripts/dev.sh test TranscriptionViewModelStopTests`: 10 tests passed
- `git diff --check`: passed
- `./scripts/dev.sh build`: passed
- `./scripts/dev.sh test`: 520 tests / 77 suites passed

## 주의

- mic/system capture timestamp 동기화는 사용하지 않는다. 라벨은 mixed stream 상의 에너지 우세 채널만 의미한다.
- `MixedAudioSource.stop()`에서 activity timeline은 지우지 않는다. stop 이후 `flushPending()` final chunk가 라벨을 조회해야 하기 때문이다. 다음 녹음 시작 시 reset한다.
