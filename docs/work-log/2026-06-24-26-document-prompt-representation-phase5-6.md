# 문서 프롬프트 표현 개정 — Phase 5(교정 terms-only)·Phase 6(요약 doc-summary)

작성일: 2026-06-24
브랜치: `feat/document-prompt-representation` (main `17d7019`에서 분기)
근거 계획: `docs/work/2026-06-22-multi-source-document-ingestion-plan.md` Phase 5·6
근거 ADR: `docs/adr/0006-multi-source-document-ingestion.md`

다중 소스 문서 수집(Phase 0~4, main 머지 완료)의 후속. "문서를 프롬프트에 넣는 표현"을
단계별로 분리한다: **교정 = 용어집만**, **요약 = 문서 요약본**.

## Phase 5 — 교정 terms-only (커밋 `dac501a`)

교정 프롬프트에서 raw 문서 본문(`document.prefix(1500)`) 주입을 제거했다. 표기 근거는
문서에서 추출한 용어가 `glossaryForPrompt`로 glossary에 이미 병합돼 흐르므로 충분하다.

### 측정 게이트 (raw-doc 격리 A/B)

계획의 "측정 없이 제거 금지" 게이트를 통과하기 위해, **용어집을 양쪽 arm에 고정하고
raw 문서(`document` 인자)만 토글**하는 격리 A/B를 `MeetingCorpusTests.documentTermInjectionCER`에
일시 플래그(`DOC_RAW_AB=1`)로 추가해 2개 코퍼스에서 측정했다(Codex 교정, release).

| 코퍼스 | 창 | global OFF(terms-only) | global ON(terms+raw) | 델타(ON-OFF) | onHits−offHits | 날조(OFF/ON) |
|---|---|---|---|---|---|---|
| 외교통일위 20260520 | 40(비어있지 않은 35) | 43.0% | 43.3% | **+0.3pp** | 0 | 0/0 |
| 재정경제기획위 20260429 | 40(비어있지 않은 34) | 34.1% | 34.4% | **+0.4pp** | +1 | 0/0 |

- raw 문서는 두 코퍼스 모두 global CER을 **악화**시켰고(net 손해), 용어 복원 이득은
  재정위의 긴 합성 법안명 "전략수출금융지원법안"(off 0 → on 2) 1개뿐이었다.
- 진단: "전략수출금융지원법안"은 추출 용어집에 **포함돼 있었다**(index 1). 즉 용어집에 항목이
  있어도 LLM은 raw 문맥이 있을 때만 이 긴 합성어를 적용했다 — 24개 평면 나열에서 긴 항목의
  앵커링이 약하다는 신호. 그러나 character-level net은 raw가 손해이고 토큰을 매 교정 1500자 늘린다.
- **결정(사용자)**: terms-only로 제거. 긴 합성어 1개 복원 손실은 수용.

측정 후 raw-doc 토글은 production API에서 사라졌으므로 `DOC_RAW_AB` 인프라는 회수했고
(`documentTermInjectionCER`는 Phase 1a term-injection A/B 형태로 복원), 측정 결과는 이 로그·커밋에 영속 기록한다.

### 변경
- `CorrectionPrompt.build` / `BatchCorrectionPrompt.build`: `document` 파라미터·raw 블록 제거.
- `LLMCorrectionService`: `LLMCorrectionContext.document` 필드 + 전달·로그(`documentChars`) 제거.
- `MeetingFileImportUseCase.importChunk`: dead가 된 `document` 파라미터 제거(importFile의 document는 summary·record용 유지).
- 테스트: 교정 context의 document 단언 → `record.document` 적극 단언으로 대체.
- 검증: 전체 718 테스트 통과. 코드리뷰 COMMENT(블로킹 0) — record/summary 경로 보존 단언 강화 반영.

## Phase 6 — 요약 doc-summary (커밋 `edef929`)

요약 프롬프트에 문서를 raw 발췌(excerpt)로 넣던 것을 1회 LLM 압축한 **문서 요약본**으로 대체.
폴백 사슬(모두 fail-soft): **요약본 → (없음/실패/LLM 미설정) excerpt → (문서 없음) 없음**. 용어는 glossary로 별도로 흐른다.

### 설계 결정(사용자 확정)
- 생성 시점: **회의 시작/첨부 즉시** — 라이브는 `MeetingContext.start()`에서 토큰 가드 하 비동기 생성, import는 최종 요약 직전 1회.
- 길이: 중간 ~1000자, 5~10 불릿.
- 실패: **재시도 없음** → excerpt 폴백.

### 변경
- `LLMUseCase.documentSummary` 신규(라우팅·토큰 1200·로그 구분). 두 어댑터 maxOutputTokens switch 갱신.
- `DocumentSummaryPrompt`(신규): 문서 → ~1000자 불릿 압축 순수 빌더, 입력 12000자 상한.
- `SummaryService.generateDocumentSummary(document:)`: `.documentSummary` useCase, 실패 시 nil(재시도 없음). incremental/final이 documentSummary를 SummaryPrompt에 전달. `SummaryGenerationContext.documentSummary` 필드 추가.
- `SummaryPrompt`: buildIncremental/buildFinal에 `documentSummary` 파라미터 + 공유 `documentContextBlock` 헬퍼(요약본→excerpt 폴백, 중복 제거).
- `MeetingContext`: `@Published documentSummary` + start() 비동기 생성(토큰 가드 `documentSummaryGenerationID`), clear() 리셋. async I/O라 `@MainActor Task{}`(documentTerms의 `Task.detached`와 의도적 구분 — 주석 명시).
- `MeetingFileImportUseCase`: 프로토콜에 `generateDocumentSummary` 추가, 최종 요약 직전 1회 생성해 주입.
- 테스트: 폴백 사슬 3종 + DocumentSummaryPrompt 3종 + import 배선 1종(+8).
- 검증: 전체 726 테스트 통과, 빌드 경고 0. 코드리뷰 COMMENT(블로킹 0) — Task 패턴/로그 레벨 주석 반영.

### 아키텍처 메모
- `SummaryService` ↔ `MeetingContext.shared` 양방향 결합은 **기존 패턴 유지**(Phase 6 신규 결함 아님).
  `generateDocumentSummary`는 `document: String` 파라미터형이라 MeetingContext에 비의존(테스트 가능). 향후 `generateIncremental`의 MeetingContext 직접 참조를 파라미터로 분리하는 건 별도 과제.

## 남은 것
- **요약 품질(요약본 vs excerpt) 정성 측정**: 미실시. Phase 6은 fail-soft·additive라 안전성 게이트가 아님(Phase 5의 CER-before-removal과 다름). 실제 코퍼스+문서로 라이브 요약 파이프라인을 돌려 doc-summary 요약 vs excerpt 요약을 비교하는 정성 평가는 선택 사항으로 남김(비용 큼·정성 신호).
- **앱 실행 QA**: 라이브 회의 시작 시 documentSummary 비동기 생성 동작(GUI) 미검증 — 사용자 실행 필요.
- 푸시·PR·main 머지: 미요청.
