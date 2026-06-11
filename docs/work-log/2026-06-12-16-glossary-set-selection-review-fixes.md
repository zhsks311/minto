# 용어집 묶음 선택 리뷰 반영

## 요약

회의 시작 시트와 파일 임포트 시트의 용어집 분류 선택에서 usable 용어가 없는 분류를 숨기고, 두 시트에 중복된 선택 영속/파생 계산을 공용 helper로 모았다.

## 변경 사항

- `GlossaryStore`에 선택 UI 전용 `usableGroupedEntriesByCategory`를 추가했다.
  - 기존 `groupedEntriesByCategory`는 비활성 용어까지 포함하는 설정 관리용 API로 유지했다.
  - `categorySelectionNames`는 선택 경로에 맞게 usable 분류만 반환한다.
- `GlossarySetSelectionSection`은 usable 그룹핑만 렌더링한다.
- `GlossarySetSelectionPersistence`가 아래 순수 계산과 UserDefaults 입출력을 공유한다.
  - 선택 가능 분류 계산
  - 유효 선택 교집합 계산
  - 직접 입력 여부
  - 배지 문구
  - restore/save/prune
- `MeetingSetupView`와 `FileImportSetupSheet`의 중복 helper를 공용 helper 호출로 축소했다.
- `FileImportSetupSheet`에 `glossarySelectionDefaults` 기본 init 파라미터를 추가했다.

## 테스트

- disabled-only 분류가 usable 그룹핑과 `categorySelectionNames`에서 빠지는지 확인했다.
- 같은 disabled-only 분류가 설정 관리용 전체 그룹핑에는 남는지 확인했다.
- persistence 저장 배열 단정은 정렬 순서에 기대지 않도록 `Set` 비교로 바꿨다.
- 선택 저장과 배지 계산의 공유 helper 동작을 테스트했다.

## 검증

- `git diff --check` 통과
- `./scripts/dev.sh build` 통과
- `./scripts/dev.sh test` 통과: 432 tests, 60 suites

## 주의

- 빌드 중 `GlossaryStore.update`의 기존 unused `index` 경고가 표시됐지만 이번 변경으로 생긴 경고가 아니므로 수정하지 않았다.
