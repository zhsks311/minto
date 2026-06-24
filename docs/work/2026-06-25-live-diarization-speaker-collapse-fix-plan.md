# 라이브 화자 라벨 collapse 수정 계획

## 목표

라이브 전사 중 LS-EEND 스트리밍 결과가 `화자 1`로 과대표시되는 문제를 수정한다. 저장 종료 후 VBx 최종 분리 경로는 유지한다.

## 확인된 증상

- 대상 회의: `선관위 부실 관리 원인과 선거 신뢰 회복 과제`
- 저장된 최종 transcript는 VBx 후처리로 `화자 1`~`화자 5`가 존재한다.
- 같은 WAV를 `LSEENDStreamingCountTests`로 재현하면 현재 라이브 스트리밍 경로는 `finalSpeakers=1`, `runningSpeakers=2` 수준으로 과소추정한다.

## 원인 가설

`FluidAudioLSEENDStreamingProvider`가 매 처리마다 `finalizedSegments + tentativeSegments`를 반환하고, `LiveSpeakerAssignmentUseCase`가 이를 계속 append한다. tentative segment는 현재 추정 스냅샷이라 누적 대상이 아니므로, 긴/반복 tentative가 matcher에서 특정 화자 overlap을 과대표집할 수 있다.

## 변경 범위

1. Provider 반환 의미를 현재 전체 timeline snapshot으로 맞춘다.
2. UseCase는 provider 응답을 append하지 않고 snapshot replace로 보관한다.
3. mock 기반 테스트를 snapshot 의미로 갱신하고, 다화자 라이브 라벨 회귀 테스트를 추가한다.
4. 실제 회의 WAV 계측과 관련 단위 테스트로 검증한다.

## 검증

- [x] `./scripts/dev.sh test LiveSpeakerAssignmentUseCaseTests`
- [x] `./scripts/dev.sh test TranscriptionViewModelLiveSpeakerTests`
- [x] `./scripts/dev.sh test StreamingSpeakerDiarizationProviderTests`
- [x] `RUN_LSEEND_STREAM=1 DIARIZATION_EVAL_WAV=<대상 wav> ./scripts/dev.sh test LSEENDStreamingCountTests`
  - 수정 전: `finalSpeakers=1`, `runningSpeakers=2`, `finalSegments=1`
  - 수정 후: `finalSpeakers=2`, `runningSpeakers=2`, `finalSegments=164`
- [x] `git diff --check`
- [x] `./scripts/dev.sh build`
- [x] `./scripts/dev.sh test` — 750 tests / 112 suites
