# 요약 용어집 스냅샷 + 재요약 용어집 선택 계획

## 목표

- 저장된 회의에서 최종 요약 생성에 사용된 resolved glossary 문자열을 `MeetingRecord.summaryGlossary`로 보존한다.
- 회의 상세 요약 영역에서 스냅샷을 접힌 배너로 표시한다.
- 재요약 시 용어집 분류와 수동 용어를 로컬 draft로 다시 선택하고, 선택 결과를 명시 주입해 요약을 다시 만든다.

## 구현 순서와 검증 기준

1. `MeetingRecord` optional 필드 추가
   - `summaryGlossary`는 additive optional 필드라 schemaVersion을 올리지 않는다.
   - init, CodingKeys, `init(from:)`에 추가하고 빈 문자열은 nil로 정규화한다.
   - 검증: 라운드트립 보존, 구스키마 nil, 빈 값 nil 테스트 작성.

2. 저장 경로 스냅샷 캡처
   - 라이브 종료 경로는 `MeetingContext.shared.glossary`를 `AppDelegate.makeRecord`와 `MeetingRecordFactory.makeRecord`로 전달한다.
   - 파일 임포트 경로는 `SummaryGenerationContext.glossary`와 같은 문자열을 record에 기록한다.
   - 검증: makeRecord/import 테스트가 snapshot 값을 확인한다.

3. 재요약 use-case overload
   - 기존 `retry(record:)`는 자동 resolver 동작을 유지한다.
   - 신규 `retry(record:glossary:)`는 명시 glossary를 SummaryGenerationContext에 넣고, 성공+저장 시에만 `summaryGlossary`를 갱신한다.
   - 검증: 주입 glossary 사용, 저장 성공 시 갱신, LLM/저장 실패 시 기존 snapshot 미저장 테스트 작성.

4. 요약 용어집 배너
   - `SummaryGlossaryBanner`를 추가하고 요약 섹션 상단에 표시한다.
   - nil/빈 값은 표시하지 않고, 줄 수를 기준으로 "요약에 사용된 용어 N개"를 렌더한다.

5. 재요약 sheet
   - 두 재요약 진입점 모두 직접 retry 대신 sheet를 연다.
   - sheet는 `GlossarySetSelectionSection`을 재사용하되 selection/manual/error/progress를 로컬 draft로만 보관한다.
   - 확인 시 시작 화면과 같은 `GlossaryContextResolver` 경로로 resolved glossary를 만들고 `retry(record:glossary:)`를 호출한다.

## 제한

- 요청에 따라 `swift build`와 `swift test`는 실행하지 않는다.
- 커밋하지 않는다.
- glossary 내용, transcript, prompt 원문은 로그로 남기지 않는다.

## 진행 상태

- 2026-06-17: STEP 1~5 구현 완료.
- 정적 확인: `git diff --check` 통과.
- 미실행: 사용자 요청에 따라 `swift build`, `swift test`는 실행하지 않음.
