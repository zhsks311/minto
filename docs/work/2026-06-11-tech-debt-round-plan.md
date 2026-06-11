# Tech debt round plan

## 목표

- Provider follow 설정이 활성 provider 변경을 수동 refresh 없이 반영하게 한다.
- MeetingRecord JSON encoder/decoder 설정을 한 곳에서 관리한다.
- LLMCorrectionService fail-soft 교정 동작을 단위 테스트로 고정한다.

## 범위

1. `LLMSummarySettingsService`, `MeetingSearchAnswerSettingsService`
   - `LLMCorrectionService.selectedProvider` 변경을 Combine으로 구독
   - 테스트 격리용 publisher 주입 지점 추가
   - 중복 수동 refresh 호출 제거, answer 상태 reset 같은 기존 UI 역할은 유지
2. `MeetingRecordCoding`
   - 공통 `makeEncoder()`, `makeDecoder()` 팩토리 추가
   - `MeetingStore`, `MeetingSaveRecovery` 호출처 교체
   - 팩토리 왕복 테스트 추가
3. `LLMCorrectionService`
   - 기존 동작을 유지하는 최소 provider resolver 주입 지점 추가
   - 성공, provider 오류, 미설정, 미지원, 빈 입력 테스트 추가

## 검증

- 각 작업 커밋 전 `./scripts/dev.sh build`
- 각 작업 커밋 전 `./scripts/dev.sh test`
- 앱 실행 금지
- `Co-Authored-By` 없는 커밋 메시지 사용
