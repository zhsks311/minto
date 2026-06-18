# 회의 첨부 문서 영속화 + 재요약 반영 + 제거 UI 계획

작성일: 2026-06-18

## 배경 / 문제

회의 설정 시 입력/Confluence 조회한 "회의 자료(문서)"는 현재 `MeetingContext.shared.document`(메모리)에만 존재한다. 라이브 최초 요약·교정 프롬프트에는 `[참고 문서]` 블록으로 들어가지만(`SummaryPrompt`/`CorrectionPrompt`), **`MeetingRecord`에는 영속 필드가 없다**. 이 한 가지 공백이 세 증상을 만든다.

1. **표시 부재**: 저장된 회의에서 어떤 문서를 참고했는지 볼 수 없다. ("관련 문서 탭"은 별개 기능 — Notion/Confluence 실시간 검색 결과를 메모리에 담아 렌더하므로 첨부 문서와 무관하다.)
2. **재요약 시 유실**: `MeetingSummaryRetryUseCase.retry`가 `document: ""`로 하드코딩(`MeetingSummaryRetryUseCase.swift:107`)이라 재요약은 문서 맥락 없이 전사·주제·용어집만으로 요약한다. 최초 요약보다 정보가 적다.
3. **제거 기능 부재**: 영속 데이터가 없으니 지울 대상도 없다.

## 결정

첨부 문서를 `MeetingRecord`에 **additive(backward-compatible) optional 필드로 영속**한다. 기존 `summaryGlossary: String?` 추가와 동일 패턴이므로 schemaVersion은 1을 유지하고, 구버전 저장 파일은 `decodeIfPresent` → `nil`로 무손실 로드된다. 마이그레이션 불필요. → 별도 ADR 없이 work plan으로 진행(비호환 변경 아님). 단 **문서 본문이 디스크 .json에 저장되는 privacy surface 확대**이므로 로그 정책(글자 수만, 본문 금지)을 명시한다.

## 비목표 (YAGNI)

- 문서 편집(수정) — 표시·제거만. 수정은 다음 회의를 새로 시작하거나 재요약 흐름과 분리.
- 관련 문서 탭(동적 검색) 변경 — 그대로 둔다. 첨부 문서는 **별도 read-only 섹션**으로 표시.
- 여러 문서 분리 저장 — 현재 `combinedDocument`는 단일 문자열. 그대로 단일 `String?`로 저장.
- 재요약 시 문서 재조회(MCP/네트워크) — 저장된 본문만 사용.

## 변경 범위

### 1. 모델 — `Sources/Minto/Models/MeetingRecord.swift`
- `public var document: String?` 추가 (위치: `summaryGlossary` 인접).
- `CodingKeys`에 `case document` 추가.
- `init(...)`에 `document: String? = nil` 파라미터 추가, 빈 문자열은 nil로 정규화(공백 trim 후 비면 nil) — `normalizedSummaryGlossary`와 같은 헬퍼 스타일.
- 커스텀 `init(from:)`에 `document = try c.decodeIfPresent(String.self, forKey: .document)` (정규화 적용).
- schemaVersion 1 유지 (additive optional). 주석에 근거 명시.

### 2. 팩토리 — `Sources/Minto/Services/MeetingRecordFactory.swift`
- `makeRecord(...)`에 `document: String? = nil` 파라미터 추가 → `MeetingRecord(... document: document ...)` 전달.

### 3. 라이브 저장 경로 — `Sources/Minto/App/AppDelegate.swift`
- `AppDelegate.makeRecord(...)` 래퍼에 `document: String? = nil` 추가, 팩토리에 전달.
- 호출부(`:61`)에서 `document: MeetingContext.shared.document` 전달. **summary 유무와 무관하게** 전달(문서는 요약 성공 여부와 독립한 원천 자료. `summaryGlossary`처럼 gating하지 않는다). 빈 값은 모델이 nil 처리.

### 4. 임포트 경로 — `Sources/Minto/Services/MeetingFileImportUseCase.swift`
- `makeRecord(... )` 호출(`:303`)에 `document: summaryContext.document` 추가.

### 5. 재요약 문서 반영 (질문 2 해결) — `Sources/Minto/Services/MeetingSummaryRetryUseCase.swift`
- `:107` `document: ""` → `document: record.document ?? ""`.
- 로그: 재요약 시작 로그에 `hasDocument=<Bool>` 또는 `documentChars=<Int>` 추가(본문 금지).

### 6. 표시 (질문 1 해결) — `Sources/Minto/UI/MeetingLibraryView.swift`
- 저장 회의 상세에 **read-only "회의 자료(첨부 문서)" 섹션** 추가. 길 수 있으므로 collapsible(DisclosureGroup) 또는 접기/펼치기. `record.document`가 nil/빈 값이면 섹션 자체를 숨긴다(상태: empty=숨김).
- 위치: 관련 문서 탭이 아니라 별도(혼동 방지). 요약/주제 인접 또는 전사 탭 헤더 영역 등 기존 레이아웃에 맞춰 codex가 제안, opus 리뷰에서 확정.
- 클라우드/로컬 구분 표시 원칙 유지(이 문서는 로컬 저장).

### 7. 제거 UI (질문 3 해결) — `Sources/Minto/UI/MeetingLibraryView.swift`
- "회의 자료" 섹션에 "문서 제거" 컨트롤.
- **확인 다이얼로그** 후 제거(CLAUDE.md: 삭제는 확인 없이 하지 않는다).
- 제거 = 전사 편집 저장 패턴과 동일하게 **store.meetings에서 최신 record를 다시 가져와 `document = nil`만 교체** 후 `MeetingStore.save`(upsert+rebuildSearchIndex). 다른 필드 보존.
- 로그: `report`/`store` 카테고리에 제거 시작·성공·실패(본문 금지, 글자 수만). fail-soft.
- 상태: success(섹션 사라짐)/error(유지+에러 표시)/disabled(라이브 진행 중이면 비활성, 전사 편집과 동일 정책).

### 8. 로그 정책 (전 경로 공통)
- 문서 본문·일부 발췌 금지. 허용: `documentChars=<Int>`, `hasDocument=<Bool>`.
- 영속 시작/성공, 제거 시작/성공/실패에 위 메타만.

## 테스트 (Swift Testing / AssertJ 불가 → #expect)

- **round-trip**: `document` 설정 → encode → decode 동일.
- **backward-compat**: `document` 키 없는 구 JSON → decode 시 `document == nil`, quarantine 안 됨.
- **정규화**: 공백만 입력 → nil 저장.
- **재요약 문서 반영**: `record.document`가 있는 record로 retry → `SummaryGenerationContext.document == record.document`(또는 프롬프트에 포함)임을 검증. (SummaryService를 스텁/주입 가능한 형태면 그걸로, 아니면 UseCase가 context를 만드는 지점 단위 테스트.)
- **제거**: document 있는 record → 제거 로직 → store 최신 record의 `document == nil`, 다른 필드(summary/transcript/summaryGlossary) 보존. (전사 편집 테스트의 "최신 record 병합" 패턴 재사용.)
- **라이브 저장 경로**: `MeetingContext.document` 주입 → 저장된 record.document 일치(가능한 범위에서).

## 검증 게이트

- `swift build --disable-sandbox --scratch-path /tmp/minto2-build`
- `swift test --disable-sandbox --scratch-path /tmp/minto2-test`
- 로그에 문서 본문 미포함 확인.
- UI: 회의 자료 섹션 empty(숨김)/표시/제거 확인 = 수동 QA.

## 엣지 / 리스크

- **기존 저장 회의**: document 없이 저장됐으므로 nil. 재요약해도 과거 회의는 문서 맥락이 없다(소실은 이미 발생). 신규 회의부터 반영. 사용자에게 혼동 없도록 섹션은 nil이면 숨김.
- **문서 크기**: combinedDocument가 클 수 있으나 transcript 대비 작다. 16MB 같은 한도 없음(로컬 JSON). 다만 매우 큰 문서는 record 파일 비대 → 현재 프롬프트도 4000자 절단이므로, 저장은 원본 보존(절단은 프롬프트 빌드 시점에만) 유지.
- **privacy**: 문서 본문 디스크 저장. 진단 로그 내보내기는 본문을 안 넣으면 안전(로그 정책 7·8 준수).
