# 회의 자료 검색 후속: citation deep-link + 대형 문서 chunk 길이 상한

작성일: 2026-06-18 · 선행: `2026-06-18-document-export-search-plan.md`(머지 25cb034)

선행 작업의 "후속 과제" 2건을 구현한다.

## #1 [MEDIUM] document citation deep-link / highlight

### 문제
document chunk(`sourcePath="document[i]"`)가 검색 답변 인용 목록엔 뜨지만, 클릭 시 회의 자료 섹션으로 **스크롤·하이라이트되지 않는다**. `citationScrollTargetID`가 `document` prefix를 매핑하지 않고, `storedDocumentSection`에 anchor `.id`·하이라이트가 없으며, 본문이 접힌 `DisclosureGroup` 안에 있다.

### 확인된 메커니즘 (근거)
- `selectSearchAnswerCitation`(`MeetingLibraryView.swift:2738`)이 `detailTab = citation.kind == .transcript ? .transcript : .summary` → **document kind는 이미 요약 탭으로 전환**된다(섹션이 요약 탭에 있으므로 정합).
- `citationScrollTargetID(_:)`(`:2768`)가 sourcePath→anchor ID 매핑. 그룹 단위 이동 패턴 존재(decisions/actions/questions는 행 인덱스 대신 그룹 앵커).
- lead 카드(`:1583-1593`)가 `citationCardBorder` + `isCitationHighlightTarget` + `.id`로 하이라이트/스크롤 타겟이 되는 **정확한 모방 패턴**.

### 변경 (`MeetingLibraryView.swift`)
1. `documentAnchorID` static 상수 추가(예: `"meeting-document"`). 모든 `document[i]`는 **단일 섹션 앵커**로 매핑(decisions처럼 그룹 단위).
2. `citationScrollTargetID(_:)`에 분기 추가: `if indexedSourcePath(path, prefix: "document") != nil { return Self.documentAnchorID }`.
3. `storedDocumentSection`(`:1597`):
   - 카드 컨테이너에 `.id(Self.documentAnchorID)` 추가.
   - 현재 `.overlay(RoundedRectangle...stroke(LibraryPalette.border, lineWidth: 1))`를 lead 카드와 동일하게 `citationCardBorder(Self.documentAnchorID)` + `lineWidth: isCitationHighlightTarget(Self.documentAnchorID) ? 1.5 : 1`로 교체.
   - DisclosureGroup을 `@State private var documentSectionExpanded` 바인딩(`DisclosureGroup(isExpanded:)`)으로 바꾸고, **인용 대상일 때 자동 펼침**. 인용 anchor 변경 시(`searchAnswerCitationAnchor`) target이면 `documentSectionExpanded = true`.
   - `documentSectionExpanded`는 `selectedID`/`detailTab` 변경 시 초기화(기존 transcriptEdit*·documentRemoval* @State 정리 패턴에 합류 — `cancelDocumentRemoval()` 인접).

### 비목표
- 문단(`document[i]`) 단위 정밀 스크롤 — 섹션 단위로 충분(decisions 등과 일관). 추후 필요 시.

## #2 [LOW] 대형 문서 chunk 길이 상한

### 문제
빈 줄 없는 매우 긴 문단은 단일 거대 chunk가 돼 (1) 임베딩이 희석되고 (2) answer top-N 후보·citation context를 한 회의가 잠식할 수 있다. answer 경로(공유 retrieve)를 바꾸는 건 모든 kind에 영향(회귀 위험)이므로, **document chunk 생성 단계에서 길이 상한**으로 국한해 푼다.

### 변경 (`MeetingSearchIndex.swift`)
- `paragraphBlocks(_:)`(또는 chunk append 직전)에서 한 문단 블록이 **상한(800자) 초과 시 하위 블록으로 분할**한다.
  - 상한 이전 마지막 공백 경계에서 자른다(단어 중간 분할 방지). 공백이 없으면 상한에서 하드 분할.
  - sourcePath `document[i]`의 `i`는 분할 결과 전체에 걸쳐 **연속**(결정론적 순서 유지).
- 상한 미만 문단은 기존과 동일(일반 문서는 형상 불변).

### chunkingVersion (필수 bump)
- document chunk 형상이 바뀌므로 `chunkingVersion` **2→3**. 기존 v2 사이드카는 `isCompatible` 불일치로 자동 무효화·재빌드.
- **재색인 비용 무시 가능**: 임베딩은 `LocalHashEmbeddingProvider`(`SearchEmbeddingViewModel.swift:26`, 로컬 해시·무료·즉시)라 전체 재임베딩이 LLM 비용을 유발하지 않는다.

## 테스트

### #1 (UI — 로직 가능한 부분만 단위 테스트, 나머지 수동 QA)
- `citationScrollTargetID`가 `document[0]`/`document[3]` → `documentAnchorID` 반환. (private이면 최소 통합 경로 또는 내부 접근 가능 범위에서.)
- 스크롤·하이라이트·자동 펼침은 수동 QA(하이브리드).

### #2 (`MeetingSearchIndexTests`)
- 800자 초과 단일 문단 document → `.document` chunk 2개 이상, 각 ≤ 상한, sourcePath `document[0]`,`document[1]`… 연속.
- 단어 경계 분할 확인(분할 지점이 공백).
- 상한 미만 문단은 기존대로 1 chunk(형상 불변 회귀 테스트).
- 기존 문단 분할/CRLF 테스트 그대로 통과.

## 검증 게이트
- `swift build --disable-sandbox --scratch-path /tmp/minto2-docf-build`
- `swift test --disable-sandbox --scratch-path /tmp/minto2-docf-test`
- 로그에 문서 본문 미포함.
- 수동 QA: 검색 답변에서 document 인용 클릭 → 요약 탭 전환 + 회의 자료 섹션 스크롤 + 카드 하이라이트 + 자동 펼침.

## 리스크
- #1 @State 자동 펼침이 selection/tab 전환 시 잔류하지 않도록 초기화 경로 누락 주의(직전 documentRemoval* HIGH와 동형 위험).
- #2 800자 상한은 임의값 — 운영 데이터로 조정. 분할이 문장 중간을 끊어 임베딩 의미가 일부 약화될 수 있으나, 거대 단일 chunk보다 낫다.
