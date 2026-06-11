# 회의 시작 용어집 묶음 선택

## 요약

회의 시작 시트와 파일 임포트 시트의 용어집 영역을 주제 기반 추천/개별 체크박스에서 분류 선택 + 직접 입력 방식으로 바꿨다. 새 저장 모델은 만들지 않고 기존 `GlossaryEntry.category`를 선택 가능한 용어집 묶음으로 사용한다.

## 변경 사항

- `GlossaryStore`에 분류 공용 헬퍼를 추가했다.
  - 빈 분류는 `기타`로 표시한다.
  - 설정 화면과 선택 UI가 같은 그룹핑/정렬 로직을 쓴다.
  - `entries(inCategories:)`는 선택 분류의 usable 용어만 반환한다.
- `GlossarySetSelectionSection`을 추가했다.
  - 분류 체크박스 행과 용어 수를 표시한다.
  - 직접 입력 TextEditor를 유지한다.
  - 선택 분류 + 직접 입력 기준으로 1,200자 예산과 잘림 경고를 표시한다.
- `MeetingSetupView`와 `FileImportSetupSheet`에서 추천 목록, 추천 선택 버튼, 선택된 용어 블록을 제거했다.
  - 두 시트 모두 공용 선택 섹션을 사용한다.
  - 배지는 `분류 N개 선택`, `직접 입력`, `선택`으로 표시한다.
  - 마지막 선택 분류는 `meetingGlossarySelectedCategories` key로 공유 저장한다.
  - 저장된 선택은 현재 존재하는 분류와 교집합만 복원한다.
- `MeetingSetupView`의 시작 버튼은 `.borderedProminent` 대신 기존 `ProminentActionButtonStyle`을 사용하게 맞췄다.
- `GlossaryStore.candidates(for:)`는 `MeetingSummaryRetryUseCase` 호출처가 남아 있어 제거하지 않았다.

## 테스트

- `entries(inCategories:)`
  - 선택 분류 일치
  - 빈 분류 `기타`
  - disabled 제외
  - 비존재 분류 무시
- 선택 분류 entries를 `GlossaryContextResolver`에 넘기는 경로가 문자 예산을 지키는지 확인했다.
- 마지막 선택 복원에서 없는 분류를 걸러내는지 확인했다.

## 검증

- `git diff --check` 통과
- `./scripts/dev.sh build` 통과
- `./scripts/dev.sh test` 통과: 429 tests, 60 suites

## 주의

- 앱 실행은 요청에 따라 수행하지 않았다.
- 설정 화면의 pending 후보 제안과 alias 제안 기능은 변경하지 않았다.
