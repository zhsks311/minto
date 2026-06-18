# 회의 자료(문서) export·검색 인덱스 포함 계획

작성일: 2026-06-18 · 선행: `2026-06-18-meeting-document-persistence-plan.md`(머지됨 d8e2f9d)

## 배경

직전 작업으로 `MeetingRecord.document`(회의 첨부 자료)를 영속하고 재요약에 반영했다. 그러나 **export 결과물과 검색 인덱스에는 document가 포함되지 않는다**(opus 리뷰가 누락 소비자로 지적). 사용자가 "문서 내용으로도 검색·내보내기"를 원해 두 경로에 추가한다.

## 목표

1. **Export**: Markdown(=Notion/Confluence 공유) 결과물에 "회의 자료" 섹션 포함.
2. **검색**: document 본문이 검색·임베딩·인용 근거에 포함.

## 비목표

- 라이브 결과 화면(MeetingSummaryView)에 document 표시 — 저장 회의 상세엔 이미 섹션 있음(직전 작업). export만 다룬다.
- document 편집 — 별도.
- chunkingVersion bump으로 전체 재색인 — 아래 "캐시" 참조(불필요로 판단, 리뷰 확인 대상).

## A. Export

### 단일 조립/변환점
- `MeetingExporter.markdown(for: MeetingResult)`(`MeetingExporter.swift:11`)가 유일한 MD 조립점. save/copy/Confluence 3경로 모두 여기 통과(`MeetingLibraryView.swift:216, 3091`, `ConfluenceExportSheet.swift:146`).
- `MeetingResult.from(record)`(`MeetingSummaryView.swift:371`)가 record→Result 유일 변환점. 단 `MeetingResult`(`MeetingSummaryView.swift:42`)에 `document` 필드 없음.

### 변경
1. `MeetingSummaryView.swift:42` — `MeetingResult`에 `public let document: String?` 추가.
   - init(`:61`)에 `document: String? = nil` 파라미터 추가(**default nil로 기존 호출 비파괴**).
2. `MeetingSummaryView.swift:371` — `from(record)`에서 `document: record.document` 전달.
3. `MeetingExporter.swift:11` `markdown(for:)` — summary 다음, **전사(`## 전사`) 앞**에 섹션 삽입:
   ```
   ## 회의 자료

   <document 본문 그대로>
   ```
   - `result.document`가 nil/공백이면 섹션 생략(transcript 가드와 동일 패턴).
   - 문서는 사용자 원문이므로 과도한 escaping 없이 본문 그대로 출력(전사 라인 escaping과 구분).
   - 배치 근거: 정제 결과(요약) → 참고 원천(회의 자료) → 원본(전사) 순서.

## B. 검색 인덱스

### Kind 추가 (`MeetingSearchIndex.swift`)
1. `:4` `Kind` enum에 `case document` 추가.
2. `:15` `label` switch에 `case .document: return "회의 자료"`.
3. `:29` `rankWeight` switch에 `case .document: return 1` — **전사와 동일한 최저 가중치**. 근거: 분량 큰 참고자료가 정제된 요약·결정 매치를 밀어내지 않도록.

### chunk 빌더 (`MeetingSearchIndex.swift:111` `chunks(for:)`)
- 전사 루프 뒤에 document를 **문단 단위로 분할**해 추가(섹션 패턴 모방, 통짜 거대 chunk 방지):
  - `record.document`를 빈 줄(`\n\n`+) 기준으로 문단 블록 분할. 블록이 1개면(빈 줄 없음) 그대로 1 chunk.
  - 각 비어있지 않은 블록 → `builder.append(.document, sourcePath: "document[\(i)]", text: block)`.
  - `ChunkBuilder.append`가 공백 블록을 자동 skip(`:258`)하므로 nil/빈 document는 chunk 0개.
- **임베딩**: `MeetingSearchEmbeddingBuilder.build`가 `index.chunks` 전체를 순회(`MeetingSearchEmbeddingIndex.swift:134`)하므로 **자동 포함, 수정 불필요**.
- **인용(citation)**: `metadataKinds`(`MeetingSearchAnswerService.swift:57` = title/topic/keywords)에 document를 **넣지 않는다** → 실콘텐츠로 citation 자동 포함. 수정 불필요.

### 검색 필터 UI (`MeetingLibraryView.swift`)
- `SearchKindFilter`(`:2557`)에 `case document` 추가, `allowedKinds`에 `case .document: return [.document]`.
- 필터 칩 배열(`:826`)에 `.document`("회의 자료") 추가.
- 근거: 모든 Kind가 어느 버킷엔 속하는 기존 일관성 유지 + document를 별도로 찾고 싶은 사용자에 발견성 제공. 칩 1개 증가(요약/전사/주제 → +회의 자료)는 수용 가능.

### 캐시 / chunkingVersion (리뷰 확인 대상)
- `chunkingVersion`(`:99`)을 **bump하지 않는다**. 근거: document는 직전 기능 이후 저장된 신규 회의에만 존재하고, 회의 저장 시 `rebuildSearchIndex`가 호출돼 자연 재색인된다. 과거 회의는 document=nil이라 chunk 0개. → 전체 재색인(전 회의 재임베딩 비용) 불필요.
- **리뷰어 확인 요청**: 디스크 캐시 유효성 판정 키(`MeetingSearchIndex` 캐시 무효화 로직)가 코드 변경을 감지하지 못해, doc-persist 머지와 이번 머지 **사이에 저장된** document 보유 회의가 재색인 전까지 document chunk 없이 캐시될 가능성. 그 시간창은 사실상 0(로컬 dev)이라 무시 가능하나, 캐시 키 구조를 확인해 실제 영향 판정.

## 테스트

### Export (`MeetingExporterTests` 또는 기존 export 테스트 파일)
- document 있는 record → markdown에 "## 회의 자료" + 본문 포함.
- document nil → "회의 자료" 섹션 없음.
- 섹션 순서: 요약 < 회의 자료 < 전사.
- `MeetingResult.from(record)`가 document를 싣는지.

### 검색 (`MeetingSearchIndexTests`)
- document 있는 record → `chunks.contains { $0.kind == .document }`.
- document nil/공백 → `.document` chunk 0개.
- 문단 2개 document → `.document` chunk 2개, sourcePath `document[0]`,`document[1]`.
- document 본문 단어로 `index.search`가 해당 회의 chunk 반환.
- 임베딩(`MeetingSearchEmbeddingIndexTests`): `embeddingIndex.records.count == searchIndex.chunks.count` 유지(document 포함).
- citation: document chunk가 인용 후보에 포함(`MeetingSearchAnswerServiceTests` 패턴, 필요 시).

## 검증 게이트

- `swift build --disable-sandbox --scratch-path /tmp/minto2-docidx-build`
- `swift test --disable-sandbox --scratch-path /tmp/minto2-docidx-test`
- export 결과에 요약/결정/할일/질문/전사 + 신규 회의 자료가 누락 없는지(CLAUDE.md export 규칙).
- 로그에 문서 본문 미포함(검색/ export 모두 본문 로깅 없음 확인).

## 리스크

- **긴 단문서**(빈 줄 없는 수천 자) → 1 chunk로 임베딩 희석. v1 수용, 추후 길이 캡 검토.
- **rankWeight 1**이 너무 낮아 document만 매치되는 질의에서 순위 하락 가능 → 전사와 동일 취급이므로 일관적. 운영 데이터로 조정.
- export "회의 자료"가 길면 MD가 비대 → 사용자 원문이므로 절단하지 않음(요약 프롬프트 절단과 별개).

## 리뷰 반영 (opus + codex 크로스리뷰)

- **[HIGH 반영]** `chunkingVersion` 1→2. doc-persist 빌드에서 저장된 회의의 stale 사이드카가 앱 재시작 시 ID 집합 일치로 재사용되어 document chunk가 누락되던 회귀 차단(`isCompatible` 버전 불일치로 자동 무효화·재빌드).
- **[MEDIUM 반영]** `paragraphBlocks` CRLF/CR→LF 정규화. `.newlines` 직접 split이 `\r\n`을 separator 둘로 처리해 Confluence 등 CRLF 문서가 줄마다 과분할되던 버그 수정 + CRLF 테스트.
- **[LOW 반영]** 공백 전용 document export 생략 테스트 추가.

## 후속 과제 (이번 범위 밖, 별도 작업)

- **[MEDIUM] document citation deep-link/highlight**: document chunk(`sourcePath="document[i]"`)가 인용 후보·근거 목록엔 포함되나, 클릭 시 회의 자료 섹션으로 스크롤·하이라이트되지 않는다(섹션에 anchor `.id`/highlight 없음 + DisclosureGroup 접힘). 인용 목록 기능 자체는 동작. anchor 배선 + 자동 펼침은 별도 UI 작업.
- **[LOW] 대형 문서 answer 후보 잠식**: rankWeight는 적정(전사 동일)하고 검색은 chunk 단위 정렬이라 flood 아님. 단 answer retrieve가 top-N 자른 뒤 회의당 cap을 적용해, 빈 줄 없는 긴 문서나 다수 문단이 한 회의 후보를 채울 수 있다. top-N 전 per-meeting/per-kind 다양화 또는 문단 길이 상한 검토.
- **NIT 보류**: `SearchKindFilter`의 `id: \.label`(현 label 고유라 무해, 추후 Hashable+`\.self`), export document 본문 끝 `\n`로 인한 전사 앞 `\n\n\n`(MD 렌더 무해).
