# 2026-06-12 회의 시작 용어집 묶음 선택 계획

## 목표

- 회의 시작과 파일 임포트 시트의 용어집 입력을 주제 기반 추천 목록에서 분류 선택 + 직접 입력 방식으로 바꾼다.
- 새 저장 모델 없이 기존 `GlossaryEntry.category`를 선택 가능한 용어집 묶음으로 사용한다.
- 마지막 선택 분류는 두 시트가 같은 UserDefaults key로 공유한다.

## 작업 단계

1. 공용 용어집 묶음 API
   - `GlossaryStore`에 빈 분류를 `기타`로 정규화하는 공용 로직을 추가한다.
   - 설정 화면과 새 선택 UI가 같은 그룹핑/정렬 결과를 사용하게 한다.
   - `entries(inCategories:)`는 usable 항목만 반환하고 비존재 분류를 무시한다.
   - 검증: 일치, 빈 분류, disabled 제외, 비존재 분류 테스트.

2. 공용 SwiftUI 선택 섹션
   - `GlossarySetSelectionSection`을 추가해 분류 체크박스 목록과 직접 입력 `TextEditor`를 렌더링한다.
   - 행 전체 클릭 토글, 용어 수 표시, empty 안내 문구, 1,200자 카운트와 초과 경고를 포함한다.
   - 검증: build로 SwiftUI 컴파일 확인.

3. 두 시트 배선
   - `MeetingSetupView`와 `FileImportSetupSheet`에서 개별 추천/선택 UI를 제거하고 공용 섹션을 사용한다.
   - 선택 분류로부터 `GlossaryContextResolver` 입력을 계산한다.
   - `meetingGlossarySelectedCategories`를 저장하고, 열릴 때 현존 분류와 교집합만 복원한다.
   - 검증: 복원 helper 테스트와 build/test.

4. 데드코드 확인
   - `GlossaryStore.candidates(for:)`는 다른 호출처가 있으면 유지한다.
   - 설정 화면의 후보/별칭 제안 기능은 변경하지 않는다.

## 검증 기준

- `git diff --check`
- `./scripts/dev.sh build`
- `./scripts/dev.sh test`
- 앱 실행은 하지 않는다.

## 진행 상태

- 계획 작성: 완료
- 구현: 완료
- 검증: 완료
- 커밋: 대기
