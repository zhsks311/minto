# 전사 중 AI provider 변경 반영 수정 계획

## 목표

전사 중 사용자가 AI provider를 바꾸면, 기존 provider로 진행 중이던 교정/증분 요약 작업을 취소하고 이후 배치가 새 provider로 실행되게 한다.

## 원인

- `TranscriptionViewModel`은 교정/증분 요약 작업을 `correctionTask`, `summaryTask`로 보관한다.
- provider 설정 변경은 `LLMCorrectionService`와 `LLMSummarySettingsService`에 반영되지만, 이미 실행 중인 작업은 취소되지 않는다.
- `summaryTask`가 살아 있으면 다음 증분 요약 배치는 `summaryTask == nil` 조건 때문에 drop된다.
- 따라서 느리거나 미설정인 provider에서 timeout이 날 때까지 새 provider 전환이 체감되지 않는다.

## 변경 범위

- `TranscriptionViewModel`
  - 교정 provider와 요약 provider 변경을 관찰한다.
  - 녹음 중 변경되면 진행 중인 교정/요약 task를 취소한다.
  - 취소 후 다음 전사 배치가 새 provider로 enqueue될 수 있게 한다.
  - 진행 중이던 요약 배치가 있으면 같은 배치를 새 provider로 재시도한다.
- `TranscriptionViewModelStopTests`
  - 진행 중인 증분 요약이 provider 변경으로 취소되고, 다음 배치가 막히지 않는지 테스트한다.

## 검증 기준

- `./scripts/dev.sh test TranscriptionViewModelStopTests`
- `./scripts/dev.sh build`
- `git diff --check`

## 진행 상태

- [x] 원인 확인
- [x] 구현
- [x] 테스트 추가
- [x] 검증
- [x] 커밋

## 검증 결과

- `git diff --check` 통과
- `./scripts/dev.sh test TranscriptionViewModelStopTests` 통과: 12 tests
- `./scripts/dev.sh build` 통과
