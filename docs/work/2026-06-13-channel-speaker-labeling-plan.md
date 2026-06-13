# 채널 기반 화자 라벨링 구현 계획

작성일: 2026-06-13

## 목표

화상회의 녹음에서 마이크는 `나`, 시스템오디오는 `상대`로 라벨링한다. STT는 기존 mixed PCM에서 1번만 수행하고, `Segment.speaker` 필드만 채운다.

## 범위

- `AudioSourceProtocol.onBuffer` 시그니처는 유지한다.
- `DualAudioBufferMixer`는 mixed PCM과 함께 우세 채널 메타데이터를 반환한다.
- `MixedAudioSource`는 mixed PCM 방출 sample-clock과 같은 offset으로 채널 활동 타임라인을 기록한다.
- `TranscriptionViewModel`은 `AudioChunk.startSeconds/endSeconds`가 있을 때만 라벨을 주입한다.
- 마이크 단독과 파일 임포트 경로는 speaker `nil` 유지.

## 구현 단계와 검증

1. 믹서 반환 타입 확장
   - `MixedChunk(samples:dominant:)` 추가
   - aligned mix에서 mic/system RMS 비교, overflow passthrough는 해당 source dominant
   - verify: mixer 기존 mixed sample 회귀 + mic/system/silent/overlap dominant 테스트
   - status: 완료

2. mixed source 타임라인
   - `RecordingChannelActivityProviding` 추가
   - `emittedMixedSamples` 기준으로 `[startSample, endSample)` 활동 기록
   - `dominantChannel(startSeconds:endSeconds:)`는 nil 구간 제외 sample 가중 다수결
   - verify: mic/system 구간 다수결, 데이터 없는 구간 nil 테스트
   - status: 완료

3. VM 라벨 주입
   - `ChannelSpeakerLabeler` 추가
   - 녹음 시작 시 activity provider 보관 및 reset
   - `positionedResult`에서 speaker 결정
   - verify: labeler 단위 테스트 + mixed 통합 스텁 테스트 + microphone 회귀 테스트
   - status: 완료

4. 전체 검증
   - `./scripts/dev.sh test <관련 필터>`
   - `git diff --check`
   - `./scripts/dev.sh build`
   - `./scripts/dev.sh test`
   - status: 완료

## 불변조건

- VAD chunk 시간과 channel activity 시간은 같은 mixed sample stream에서 나온다.
- mic/system 입력에는 절대 타임스탬프 동기화가 없으므로, 라벨은 mixed stream 상의 에너지 우세 채널만 의미한다.
- overlap은 잘못된 라벨보다 무라벨이 낫기 때문에 `nil`로 둔다.
