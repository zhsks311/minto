# Core Service Regression Tests Plan

작성일: 2026-06-30
상태: **Approved plan — ralplan consensus 완료**
목적: 기능 추가 시 Minto2의 기존 핵심 서비스 계약이 깨지는 것을 빠르게 감지하는 회귀테스트를 추가한다.

## 요구사항 요약

사용자 목적은 특정 서비스 하나의 버그 재현이 아니라, 향후 기능 추가가 기존 기능을 망가뜨리지 않도록 보호하는 것이다. 현재 테스트는 서비스별 단위 테스트가 풍부하므로, 새 테스트는 중복 단위 검증보다 서비스 경계가 이어지는 핵심 사용자 흐름을 고정한다.

원하는 결과:

- 빠른 CI용 회귀 스위트를 추가한다.
- 네트워크, 모델 다운로드, 실오디오, 앱 실행 없이 검증한다.
- 저장 → 검색 sidecar → Markdown export 경계가 함께 깨지지 않는지 확인한다.
- 저장 schema의 additive optional 필드가 기존 저장 파일 호환성을 깨지 않는지 확인한다.
- 손상 JSON 하나가 유효 회의 목록과 검색 인덱스를 망가뜨리지 않는지 확인한다.

## 근거와 제약

기준 문서와 코드:

- `docs/service-definition.md`: 핵심 흐름 — 실시간/파일 회의 기록, 검색, 내보내기, provider fail-soft
- `Sources/Minto/Services/MeetingStore.swift`: 저장과 검색 sidecar 재빌드
- `Sources/Minto/Services/MeetingSearchIndex.swift`: 검색 chunk 생성/검색 계약
- `Sources/Minto/Services/MeetingExporter.swift`: Markdown export 계약
- `Sources/Minto/Models/MeetingRecord.swift`: 저장 schema와 additive optional 필드
- 기존 테스트: `MeetingStoreTests`, `MeetingSearchIndexTests`, `MeetingExporterTests`, `SummaryServiceTests`, `ProviderFollowSemanticTests`

제약:

- production code는 변경하지 않는다.
- 새 dependency나 테스트 러너를 추가하지 않는다.
- Swift Testing 기존 패턴을 따른다.
- 임시 파일은 세션 scratchpad 또는 `FileManager.default.temporaryDirectory` 기반 테스트 전용 디렉터리만 사용하고, 사용자 실제 저장소는 건드리지 않는다.
- `MeetingStore`가 `@MainActor`이므로 suite는 `@MainActor`, `.serialized` 패턴을 따른다.

## Non-goals / Out of Scope

- WhisperKit/SpeechAnalyzer 실제 전사 품질 회귀: 기존 manual/benchmark 테스트와 `tools/stt-benchmark` 영역으로 유지한다.
- UI 상태 회귀: 별도 앱 실행 QA가 필요하므로 이번 기본 회귀 스위트에는 넣지 않는다.
- Confluence/Notion 실제 네트워크 연동: 토큰·권한·외부 상태가 필요하므로 stub 기반 서비스 테스트만 유지한다.
- provider fail-soft 신규 검증: 이미 `SummaryServiceTests`, `ProviderFollowSemanticTests` 등에서 다루므로 이번 스위트에서는 제외한다.
- 검색 scoring/rerank 알고리즘 세부 고정: 회귀 목적은 “검색 가능”이며, 순위 고정은 제목/주제처럼 대표성이 제품 계약인 경우에만 제한적으로 사용한다.

## RALPLAN-DR Summary

### Principles

1. **사용자 가치 경계 고정**: 단일 함수 세부 구현보다 저장·검색·내보내기 연결 계약을 검증한다.
2. **결정론적이고 빠른 테스트**: 네트워크, 모델, 실오디오, 앱 실행에 의존하지 않는다.
3. **기존 단위 테스트와 역할 분리**: 세부 chunking/export formatting은 기존 테스트에 맡기고, 새 테스트는 cross-service 계약만 검증한다.
4. **호환성 우선**: 새 optional 필드가 기존 저장 JSON 로드를 깨지 않아야 한다.
5. **데이터 보호**: 손상 파일은 조용히 덮어쓰거나 전체 목록을 막지 않고 quarantine되어야 한다.

### Decision Drivers

1. 기능 추가가 가장 자주 깨뜨릴 수 있는 서비스 경계: `MeetingStore` ↔ `MeetingSearchIndexStore` ↔ `MeetingExporter`.
2. CI에서 항상 돌릴 수 있는 속도와 안정성.
3. 기존 테스트와 중복을 최소화하면서 실제 사용자 흐름 회귀를 잡는 범위.

### Viable Options

#### Option A — 서비스별 단위 테스트 추가

장점:

- 실패 원인 국소화가 쉽다.
- 기존 테스트 구조와 가장 유사하다.

단점:

- 이미 `MeetingStoreTests`, `MeetingSearchIndexTests`, `MeetingExporterTests`가 있어 중복 가능성이 높다.
- 저장→검색→내보내기 경계가 함께 깨지는 문제를 놓칠 수 있다.

#### Option B — 핵심 서비스 연결 회귀 스위트 추가 (채택)

장점:

- 사용자 목표인 “기능 추가 시 기존 핵심 기능 보호”에 직접 대응한다.
- production code 변경 없이 테스트만 추가할 수 있다.
- 기존 단위 테스트와 역할이 분리된다.

단점:

- 실패 시 어느 레이어가 원인인지 단위 테스트보다 덜 즉각적이다.
- 너무 많은 assertion을 한 테스트에 넣으면 유지보수성이 떨어질 수 있다.

완화:

- 테스트를 3개로 분리한다.
- 검색 assertion은 기본적으로 `results.contains { $0.meetingID == id }` 형태로 두어 scoring 변경에 덜 민감하게 한다.
- 실패 원인 추적은 기존 단위 테스트와 함께 수행한다.

#### Option C — 제품 경로/앱 실행 기반 E2E 회귀

장점:

- 실제 사용자 흐름과 가장 가깝다.

단점:

- UI, 권한, 모델, 파일 시스템 상태에 의존해 flaky 가능성이 높다.
- 빠른 기본 회귀 스위트 목적에 맞지 않는다.

결론: Option B를 채택한다.

## Architect Review Synthesis

Verdict: **APPROVE**

주요 판단:

- 새 production abstraction 없이 기존 서비스 경계를 테스트로 묶는 접근은 아키텍처적으로 적합하다.
- `MeetingResult`가 UI 파일에 정의되어 있어 “서비스 회귀”라는 이름과 완전히 일치하지는 않지만, 실제 export 경로가 `MeetingResult.from(record)`를 사용하므로 이번 계약에 포함하는 것이 타당하다.
- provider fail-soft는 이번 스위트에서 제외하는 편이 범위가 명확하다.
- 검색 assertion은 top result 고정보다 검색 결과 포함 검증을 기본으로 해야 scoring 개선을 불필요하게 막지 않는다.

Steelman counterargument:

> 저장→검색→내보내기 통합 테스트는 실패 시 어느 레이어가 원인인지 바로 알기 어렵고, 기존 단위 테스트가 이미 충분하니 중복 비용만 늘 수 있다.

반박:

- 이 앱은 additive optional 필드, sidecar index, export 누락으로 사용자 가치가 쉽게 깨질 수 있다.
- 레이어 간 계약을 한 번에 고정하는 빠른 테스트는 기존 단위 테스트가 잡기 어려운 회귀를 잡는다.
- 단, 테스트 수와 assertion 범위를 최소로 유지한다.

Tradeoff tension:

- **넓은 회귀 보호** vs **실패 원인 국소성**
  - 넓게 묶으면 사용자 흐름 회귀를 잘 잡는다.
  - 대신 실패 원인 추적은 기존 단위 테스트와 함께 해야 한다.
  - 3개 테스트 분리와 contains 기반 검색 assertion으로 균형을 잡는다.

## Critic Review Synthesis

Verdict: **APPROVE**

주요 판단:

- 세 테스트 모두 임시 디렉터리와 기존 서비스만 사용하므로 네트워크, 모델, UI 런타임 없이 재현 가능하다.
- 수용 기준이 명확하다.
  - 저장 후 reload해도 검색·export 가능
  - 레거시 JSON optional 누락 허용
  - 손상 JSON quarantine 후 유효 record/index 유지
- flaky 위험은 낮다.
- UUID와 날짜는 고정 fixture를 사용한다.
- 손상 파일 테스트는 `corruptedCount == 1`과 quarantine 파일 존재를 함께 확인한다.

추가 acceptance criteria:

1. fixture는 transcript/document 원문을 로그에 남기지 않고 테스트 assertion 문자열로만 둔다.
2. 새 테스트는 `.serialized`와 임시 디렉터리 cleanup 패턴을 기존 테스트와 맞춘다.
3. search assertion은 “검색 결과에 해당 meetingID가 포함됨”을 기본으로 하고, 순위는 별도 목적이 있을 때만 고정한다.

## 구현 계획

### Phase 1 — 회귀 fixture와 테스트 파일 추가

파일 후보: `Tests/MintoTests/CoreServiceRegressionTests.swift`

테스트용 `MeetingRecord` fixture를 파일 내부 private helper로 만든다.

fixture 필드:

- 고정 `UUID`, 고정 `Date`
- title: `제품 출시 회의`
- topic: `출시 리스크 점검`
- summary:
  - leadQuestion / leadAnswer
  - sections
  - decisions
  - actionItems
  - openQuestions
  - keywords
- summaryGlossary: `Minto = 회의 기록 앱`
- document: 첨부 문서 문단 2개, 문서 전용 검색 token 포함
- transcript:
  - speaker 포함 segment 1개
  - speaker 없는 segment 1개
  - timestamp/duration 포함
  - 필요한 경우 word timestamp 1개
- speakerEmbeddings optional 필드 1개
- `audioFileName`은 이번 회귀 목적에 필수는 아니므로 기본 fixture에서는 제외한다. 레거시 JSON 테스트에서 optional 누락 검증으로 충분하다.

검증 기준:

- `swift test --filter CoreServiceRegressionTests`가 컴파일되고 실행된다.
- suite는 `@MainActor`, `.serialized`를 사용한다.
- 임시 디렉터리는 test 종료 시 정리한다.

### Phase 2 — 저장→검색→내보내기 연결 계약 테스트

테스트명 예시:

- `savedMeetingRemainsSearchableAndExportableAfterReload`

흐름:

1. 임시 저장 디렉터리 생성
2. `MeetingStore(directory:)`에 fixture 저장
3. 새 `MeetingStore(directory:)` 인스턴스로 reload 확인
4. sidecar `MeetingSearchIndexStore(directory:)`를 로드해 검색 가능한 chunk 확인
5. `MeetingSearchIndex.search`로 다음 질의가 해당 회의를 찾는지 확인
   - 제목/주제 질의
   - 결정사항 질의
   - 할 일 owner/due 질의
   - 첨부 문서에만 있는 token 질의
   - 전사 질의
6. 검색 검증은 기본적으로 `results.contains { $0.meetingID == record.id }`로 한다.
7. 제목/주제처럼 대표성이 제품 계약인 경우에만 `first?.meetingID`를 제한적으로 확인한다.
8. `MeetingResult.from(loaded)` → `MeetingExporter.markdown(for:)` 실행
9. Markdown에 다음 섹션/내용이 포함되는지 확인
   - 제목
   - 핵심 답변
   - 결정사항
   - 할 일
   - 미해결 질문
   - 회의 자료
   - 전사
   - speaker label

검증 기준:

- 저장/로드/검색/export 중 하나라도 핵심 계약이 깨지면 테스트가 실패한다.
- 테스트는 외부 API와 기본 사용자 저장소를 건드리지 않는다.
- 검색 scoring 변경만으로 불필요하게 실패하지 않는다.

### Phase 3 — schema/backward compatibility 회귀 보강

테스트명 예시:

- `legacyMeetingRecordStillLoadsAndExportsWithoutNewOptionalFields`

흐름:

1. `summaryGlossary`, `document`, `audioFileName`, `speakerEmbeddings`, `transcript.speaker`, `transcript.words`가 없는 레거시 JSON을 임시 디렉터리에 직접 기록
2. `MeetingStore(directory:)`로 로드
3. quarantine 없이 로드되는지 확인
4. 검색 index가 생성되는지 확인
5. export가 크래시 없이 기본 섹션을 생성하는지 확인

검증 기준:

- additive optional 필드 추가가 기존 저장 파일 로드를 깨지 않는다.
- `store.corruptedCount == 0`이다.
- export에 빈 `회의 자료` 섹션이 생기지 않는다.

### Phase 4 — 데이터 보호 회귀 보강

테스트명 예시:

- `corruptRecordDoesNotBlockValidRecordsOrSearchIndex`

흐름:

1. 같은 임시 디렉터리에 유효 record JSON과 손상 JSON을 함께 기록
2. `MeetingStore(directory:)` 로드
3. 유효 record만 `meetings`에 남는지 확인
4. `store.corruptedCount == 1` 확인
5. 손상 파일은 `quarantine/`으로 이동했는지 확인
6. 검색 sidecar가 유효 record 기준으로 생성되는지 확인
7. index chunks가 유효 record만 가리키는지 확인

검증 기준:

- 손상 파일 1개가 전체 회의 목록과 검색을 망가뜨리지 않는다.
- 손상 파일은 삭제가 아니라 quarantine으로 보존된다.

### Phase 5 — 실행 검증

순서:

1. `git diff --check`
2. `swift test --disable-sandbox --scratch-path /private/tmp/claude-501/-Users-d66hjkxwt9-Idea-private-minto2/bf9d2770-bbe5-4d7d-b559-a2304680ff73/scratchpad/minto2-test --filter CoreServiceRegressionTests`
3. 관련 기존 테스트:
   - `swift test --disable-sandbox --scratch-path /private/tmp/claude-501/-Users-d66hjkxwt9-Idea-private-minto2/bf9d2770-bbe5-4d7d-b559-a2304680ff73/scratchpad/minto2-test --filter MeetingStoreTests`
   - `swift test --disable-sandbox --scratch-path /private/tmp/claude-501/-Users-d66hjkxwt9-Idea-private-minto2/bf9d2770-bbe5-4d7d-b559-a2304680ff73/scratchpad/minto2-test --filter MeetingSearchIndexTests`
   - `swift test --disable-sandbox --scratch-path /private/tmp/claude-501/-Users-d66hjkxwt9-Idea-private-minto2/bf9d2770-bbe5-4d7d-b559-a2304680ff73/scratchpad/minto2-test --filter MeetingExporterTests`
4. 가능하면 최종 확인으로 전체 `swift test --disable-sandbox --scratch-path /private/tmp/claude-501/-Users-d66hjkxwt9-Idea-private-minto2/bf9d2770-bbe5-4d7d-b559-a2304680ff73/scratchpad/minto2-test`를 실행한다.

프로젝트 CLAUDE.md의 기본 명령은 `/tmp/minto2-test`를 쓰지만, 현재 세션 지침상 임시 산출물은 scratchpad 아래로 둔다.

## Acceptance Criteria

- `Tests/MintoTests/CoreServiceRegressionTests.swift`가 추가된다.
- 새 회귀 스위트는 `@MainActor`, `.serialized`를 사용한다.
- 새 회귀 스위트는 사용자 실제 저장소, 네트워크, 모델 다운로드, 앱 실행에 의존하지 않는다.
- 저장된 fixture 회의가 reload 후에도 다음을 만족한다.
  - 주요 optional 필드가 보존된다.
  - 검색 sidecar가 로드된다.
  - 제목/주제, 결정사항, 할 일, 문서 전용 token, 전사 query로 검색 가능하다.
  - Markdown export에 제목, 요약, 결정사항, 할 일, 미해결 질문, 회의 자료, 전사, speaker label이 포함된다.
- 레거시 JSON은 quarantine 없이 로드되고 export 가능하다.
- 손상 JSON은 quarantine되고 유효 record와 검색 index를 막지 않는다.
- 검증 명령 결과를 완료 보고에 포함한다.

## Risks and Mitigations

- 리스크: 너무 넓은 end-to-end 테스트가 실패 원인을 흐릴 수 있다.
  - 완화: 회귀 스위트는 3개 테스트로 유지하고, 단계별 `#expect`를 명확히 둔다.
- 리스크: 기존 단위 테스트와 중복된다.
  - 완화: 세부 알고리즘은 기존 테스트에 맡기고, 이 테스트는 서비스 간 연결 계약만 검증한다.
- 리스크: 검색 scoring 개선이 회귀테스트를 불필요하게 깨뜨릴 수 있다.
  - 완화: 기본 검색 assertion은 `contains(meetingID)`로 둔다. top result 검증은 제한적으로만 사용한다.
- 리스크: fixture가 불필요한 side effect를 유발할 수 있다.
  - 완화: `audioFileName`처럼 테스트 목적에 필수 아닌 필드는 기본 fixture에서 제외한다.
- 리스크: `MeetingStore`의 `@MainActor`와 shared 상태로 인한 테스트 간 간섭.
  - 완화: suite를 `.serialized`로 두고, shared singleton이 아니라 주입된 임시 directory store만 사용한다.

## Rollback / Recovery Notes

- production code 변경이 없으므로 rollback은 새 테스트 파일 제거 또는 assertion 완화로 충분하다.
- 테스트가 검색 scoring 변경 때문에 실패하면, 먼저 제품 계약인지 확인한다.
  - 제품 계약이면 implementation 회귀로 본다.
  - 단순 ranking 변경이면 `contains` 기반으로 조정한다.
- 레거시 JSON 테스트 실패는 저장 schema 호환성 회귀로 간주한다.
- 손상 JSON 테스트 실패는 데이터 보호 회귀로 간주한다.

## ADR Section

### Decision

Minto2에 빠른 핵심 서비스 연결 회귀 스위트를 추가한다. 범위는 저장/reload, 검색 sidecar, Markdown export, 레거시 JSON 호환, 손상 JSON quarantine으로 제한한다.

### Drivers

- 기능 추가 시 기존 핵심 기능 보호
- 빠른 CI 실행 가능성
- 기존 단위 테스트와의 역할 분리
- 저장 schema 호환성과 데이터 보호

### Alternatives considered

1. 서비스별 단위 테스트만 추가
   - 실패 원인 국소화는 좋지만 연결 계약 회귀를 놓칠 수 있다.
2. 핵심 서비스 연결 회귀 스위트 추가
   - 사용자 가치 흐름을 직접 보호한다. 채택.
3. 앱 실행 기반 E2E 테스트
   - 실제 사용자 흐름과 가깝지만 flaky하고 느려 기본 회귀 스위트에 부적합하다.

### Why chosen

Option B는 production code 변경 없이, 기존 단위 테스트가 놓치기 쉬운 서비스 경계 회귀를 빠르게 잡는다. 사용자의 목표인 “기능 추가 시 기존 기능이 망가지는 것을 방지”에 가장 직접적이다.

### Consequences

- 회귀 보호 범위가 넓어진다.
- 일부 실패는 기존 단위 테스트와 함께 원인을 좁혀야 한다.
- 검색 ranking 자체를 과도하게 고정하지 않도록 assertion 설계가 중요하다.

### Follow-ups

- 향후 삭제/수정 흐름이 사용자 가치상 더 중요해지면 별도 회귀 테스트를 추가한다.
- UI 앱 실행 회귀는 별도 QA/자동화 계획으로 다룬다.
- STT 품질 회귀는 benchmark framework와 manual tests에서 계속 관리한다.

## Recommended Execution Lane

**Direct implementation in current session**을 추천한다.

이유:

- production code 변경 없이 테스트 파일 1개 추가가 중심이다.
- 범위와 acceptance criteria가 명확하다.
- 검증 명령이 구체적이다.
- 병렬 구현이나 workflow가 필요할 정도로 파일/리스크가 크지 않다.

실행은 별도 명시가 있을 때 시작한다. `/ralplan` 자체는 구현 권한이 아니다.
