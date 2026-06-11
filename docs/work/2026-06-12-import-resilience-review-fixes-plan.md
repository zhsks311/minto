# 2026-06-12 파일 가져오기 리뷰 반영 계획

## 목표

- 직전 파일 가져오기 복원력/재요약/톤 커밋에 대한 코드리뷰 지적을 한 커밋으로 반영한다.
- 파일 가져오기 정적 실행 상태가 테스트 간 오염되지 않도록 시작/종료 정리를 테스트로 보장한다.
- pending import marker는 읽기와 쓰기 모두에서 파일명만 저장/노출되게 한다.

## 작업 단계

1. 정적 import 상태 정리
   - `MeetingFileImportUseCase`에 테스트가 호출할 수 있는 internal reset helper를 추가한다.
   - `MeetingFileImportUseCaseTests`의 각 테스트 시작/종료에서 정적 상태와 marker를 정리한다.
   - 성공/실패/취소 경로에서 `isAnyImportRunning == false`를 유지하는 기존 검증을 보존한다.

2. pending import marker 방어
   - `updatePendingImportMarker` 저장 시점에 `lastPathComponent`를 적용한다.
   - full path 입력이 들어와도 marker 저장값은 파일명만 남는 회귀 테스트를 추가한다.
   - marker 제거 조건을 `!nextState.isRunning`으로 단순화한다.

3. UI/종료 안내 보강
   - 종료 Alert에서 사용자가 `종료`를 고르면 marker를 남겨 다음 실행 안내 카드가 뜨는 의도를 주석으로 남긴다.
   - 안내 카드의 파일명 텍스트에 `lineLimit(1)`과 `.truncationMode(.middle)`을 적용한다.

## 검증 기준

- `./scripts/dev.sh build` 통과
- `./scripts/dev.sh test` 통과
- 앱 실행은 하지 않는다.

## 진행 상태

- 계획 작성: 완료
- 구현: 완료
- 검증: 완료
- 커밋: 대기
