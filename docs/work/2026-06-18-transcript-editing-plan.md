# 회의 후 전사 편집 구현 계획

## 목표

- 저장된 회의의 전사 탭에서 segment 단위 텍스트 편집을 제공한다.
- 저장 시 최신 `MeetingRecord`를 다시 읽고 `transcript`만 교체한다.
- 편집 저장 실패 시 draft를 유지하고, 성공 시 요약 재생성 안내만 표시한다.

## 단계

1. 순수 편집 로직 추가
   - `Segment.text` 변경 시 public init으로 새 `Segment`를 만들고, 변경된 segment만 `words = nil`로 둔다.
   - 공백뿐인 편집 결과는 저장 배열에서 제거한다.
   - verify: Swift Testing 테스트로 id/timestamp/duration/speaker/words 보존 규칙을 확인한다.

2. 저장 병합 경로 추가
   - 저장 시 `store.meetings`에서 최신 record를 재조회해 transcript만 교체한다.
   - `MeetingStore.save` 결과별 UI 상태를 분리한다.
   - verify: 최신 record의 summary 보존, search index/export 반영, 실패 시 draft 유지, `.skippedEmpty` 처리를 테스트한다.

3. UI 연결
   - 저장 회의 전사 탭에 `편집` 진입을 추가하고 라이브 회의 중에는 비활성화한다.
   - edit mode는 `TranscriptEditView`가 스크롤 transcript와 fixed bottom bar를 sibling으로 렌더링한다.
   - speaker 편집 UI는 edit mode에서 렌더링하지 않는다.
   - verify: diff self-review로 sticky bar가 outer `ScrollView` 안에 들어가지 않는지 확인한다.

## 검증 제한

- 사용자 요청에 따라 `swift build`와 `swift test`는 실행하지 않는다.
- 실행 가능한 검증은 `git diff --check`와 diff 기반 자체 검토로 제한한다.

## 진행 상태

- 순수 편집 로직: 완료.
- 저장 회의 전사 탭 UI 연결: 완료.
- Swift Testing 테스트 추가: 완료.
- 검증: `git diff --check` 통과, 새 파일 trailing whitespace 없음. SwiftPM 빌드/테스트는 요청대로 실행하지 않음.
