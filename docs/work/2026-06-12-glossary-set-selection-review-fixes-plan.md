# 2026-06-12 용어집 묶음 선택 리뷰 반영 계획

## 목표

- 선택 UI에서는 usable 용어가 없는 분류를 숨긴다.
- 회의 시작 시트와 파일 임포트 시트의 용어집 선택 영속 로직을 같은 헬퍼로 공유한다.
- 파일 임포트 시트도 회의 시작 시트처럼 `UserDefaults`를 주입받을 수 있게 한다.
- 기존 설정 화면의 전체 용어 관리 그룹핑은 유지한다.

## 작업 단계

1. `GlossaryStore` 선택용 그룹핑 분리
   - 전체 `groupedEntriesByCategory`는 유지한다.
   - `isUsable` 필터 후 같은 그룹핑/정렬을 적용하는 선택용 API를 추가한다.
   - 검증: disabled-only 분류는 선택용 그룹핑에서 빠지고 전체 그룹핑에는 남는다.

2. 선택 영속 헬퍼 확장
   - available/valid/manual/badge 계산과 load/save/prune을 `GlossarySetSelectionPersistence`로 모은다.
   - 뷰에는 `@State` 바인딩과 호출 타이밍만 남긴다.
   - 검증: 기존 persistence 테스트를 순서 무관 단정으로 바꾸고 helper 동작을 유지한다.

3. 두 시트 배선 정리
   - `MeetingSetupView`와 `FileImportSetupSheet`가 선택용 분류 이름을 쓰도록 바꾼다.
   - `FileImportSetupSheet`에 `glossarySelectionDefaults` init 파라미터를 추가한다.
   - 기존 호출처는 기본값으로 컴파일되게 둔다.

4. 검증과 커밋
   - `git diff --check`
   - `./scripts/dev.sh build`
   - `./scripts/dev.sh test`
   - worktree clean 상태로 한국어 커밋을 만든다.

## 진행 상태

- 계획 작성: 완료
- 구현: 완료
- 검증: 완료
- 커밋: 대기
