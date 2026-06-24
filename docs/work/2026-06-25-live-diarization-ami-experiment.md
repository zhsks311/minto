# 라이브 화자분리 LS-EEND AMI variant 실험

## 목표

`main` 기준 실험 브랜치에서 라이브 LS-EEND 기본 variant를 `dihard3`에서 `ami`로 바꾸면 실제 한국어 회의의 라이브 화자 수 추정이 개선되는지 확인한다.

## 배경

대상 회의 `선관위 부실 관리 원인과 선거 신뢰 회복 과제`는 저장 종료 후 VBx에서 `화자 1`~`화자 5`로 분리됐다. 같은 WAV에서 LS-EEND batch variant 비교 결과:

- `ami`: 4명
- `callhome`: 3명
- `dihard2`: 2명
- `dihard3`: 2명

따라서 live 기본값 후보는 `ami`다.

## 변경

- `FluidAudioLSEENDStreamingProvider` 기본 `variant`를 `.ami`로 변경한다.
- snapshot fix(`a5fb3dc`)를 선행 적용해 stale tentative 누적 영향을 제거한 상태에서 비교한다.

## 검증

- [x] `RUN_LSEEND_STREAM=1 DIARIZATION_EVAL_WAV=<대상 wav> ./scripts/dev.sh test LSEENDStreamingCountTests`
  - 결과: `finalSpeakers=4`, `runningSpeakers=4`, `finalSegments=193`, `audioSec=440.3`
- [x] `./scripts/dev.sh test StreamingSpeakerDiarizationProviderTests`
- [x] `./scripts/dev.sh test LiveSpeakerAssignmentUseCaseTests`
- [x] `./scripts/dev.sh test TranscriptionViewModelLiveSpeakerTests`
- [x] `./scripts/dev.sh build`

## 결론

`ami`는 같은 회의 WAV에서 라이브 경로의 화자 수 추정을 `dihard3`의 2명에서 4명으로 개선한다. 다만 종료 후 VBx 결과의 5명과는 아직 차이가 있으므로, 최종 회의록 수준의 화자 수 보정은 계속 VBx finalize 경로에 맡겨야 한다.
