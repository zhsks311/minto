# ADR 0005: 다중 소스 문서 수집(파일·Notion) 도입

상태: Proposed
작성일: 2026-06-22
개정: 2026-06-22 (다중 관점 리뷰 1차 반영 — opus critic + Codex)

## Context

회의 시작 시 사용자는 "참고 문맥 문서"를 줄 수 있고, 이 문서는 전사 교정·요약·문서 용어 추출의 참고자료로 쓰인다. 현재 입력 경로는 두 가지뿐이다.

- **수동 텍스트 입력**: `MeetingSetupView`의 `TextEditor(text: $document)` (`Sources/Minto/UI/MeetingSetupView.swift:269`)
- **Confluence 조회**: `ConfluenceService.searchContext(_:)` → `ContextDocument{title,text,url}` (`Sources/Minto/Services/ConfluenceService.swift`)

두 경로의 산출물은 `MeetingSetupView.combinedDocument`(`:409`)에서 **하나의 평문 문자열**로 합쳐져 `onStart(topic, glossary, document, audioInputMode)`로 전달된다. 즉 도메인/파이프라인에 도달하는 문서는 **이미 평문 텍스트**이며, downstream(용어 추출·교정·요약 발췌)은 출처를 모른다. 이 "출처 무관 평문 문자열" 계약이 현재 설계의 안정점이다.

문제: 사용자는 회의 자료를 Confluence가 아닌 다양한 형태로 가진다 — 로컬 파일(md/pdf/Word 등)이나 Notion 페이지. 현재는 수동 복사·붙여넣기 해야 하고 마찰이 크다.

### 기존 자산 (리뷰로 확인 — 이전 초안이 누락했던 사실)

코드베이스에 **이미 Notion 연동이 프로덕션 상태로 존재**한다. 초안은 이를 모른 채 별도 서비스를 추가하려 했고, 다중 관점 리뷰(opus critic + Codex)가 양쪽 독립적으로 이를 Critical blocker로 지적했다.

- `NotionMCPService`(`Sources/Minto/Services/NotionMCPService.swift`): Notion 공식 MCP 서버(mcp.notion.com/mcp)에 **OAuth 2.1(DCR+PKCE)** 로 연결. Keychain `notion-mcp`에 토큰 영속. `connectionState`(connected/needsReconnect/disconnected), fail-soft 보유.
  - `search(_:)` — 키워드 검색(`notion-search` 도구). **LLM 무관, 순수 도구 호출.**
  - `fetchText(for:url:client:)`(`:187`, 현재 private static) — **Notion URL → 본문 텍스트**(`notion-fetch` 도구, url/id 인자 둘 다 시도). **LLM 무관.**
- 사용처: `SettingsView`(Notion 연결/해제 UI), `MeetingLibraryView`, `RelatedInfoService`(전사 키워드로 Notion+Confluence 관련 문서 조회).
- MCP Swift SDK는 이 프로젝트에서 **오직 Notion 때문에** 의존(`Package.swift:10`).

→ Notion 페이지 본문을 가져오는 능력(`fetchText`)이 이미 있다. 새로 만들 게 아니라 **재사용**한다.

### 1차 릴리스 범위 (사용자 확정)

- **포맷**: **md/txt + pdf(텍스트형) + 이미지 파일·스캔 PDF(Vision OCR)**. → 외부 SPM 의존성 0개(Vision 내장).
- **Notion**: **기존 `NotionMCPService`(OAuth+MCP) 재사용.** Internal Integration Token·OAuth 신규 도입 안 함. 새 Keychain 키·별도 설정 UI 없음.
- **OCR**: 1차 포함. Apple Vision `VNRecognizeTextRequest`(ko-KR, on-device, 무의존성)로 이미지 파일(png/jpg/heic 등)과 텍스트 없는 PDF를 처리. Vision은 백그라운드 설계라 프리징 무관, 단 페이지당 추론이 느려 **OCR 페이지 상한 + 진행률/취소**가 필요.
- **파일 다중 선택**: 허용(`allowsMultipleSelection: true`). 단수는 복수의 특수케이스로 흡수.
- **문서 표현 개정 포함**: 교정=용어집만(raw 문서 제거), 요약=문서 요약본 주입(폴백 보유). 모든 소스(파일·Notion·Confluence·수동) 공통 적용.
- **배포**: 직접/사내 배포.
- **제외(향후 ADR)**: docx/doc, pptx/hwpx, hwp(구), ppt, "Notion MCP→Internal Token 마이그레이션"(별도 결정).
- **Obsidian 전용 연동 비대상**: vault의 `.md`는 일반 파일 첨부(md)로 자연 지원되므로 별도 어댑터 없음. URL 경로는 모두 제외 — `obsidian://`(로컬 앱 스킴, 콘텐츠 fetch 불가), Publish(`publish.obsidian.md`)는 SPA로 naive fetch 불가(측정: help.obsidian.md raw HTML 2.7KB 껍데기), Local REST API(플러그인+로컬서버 전제 niche). 구체 수요 시 재검토.

## Decision

**(1) 모든 문서 소스를 "→ 평문 텍스트(`AttachedDocument`)" 로 수렴시키는 소스 어댑터 + 수집 use-case 구조를 도입하고, (2) 그 평문을 프롬프트에 넣는 "문서 표현"을 단계별로 분리한다.** 수집(ingestion)은 `combinedDocument` 단일 합류점을 유지하지만, **downstream의 문서 표현은 이번 ADR에서 함께 개정한다**(교정=용어집만, 요약=문서 요약본). 용어 추출(`DocumentTermExtractor`) 경로는 유지된다.

### 아키텍처 (CLAUDE.md 경계 준수)

```
UI (MeetingSetupView)
  └ 파일 선택(fileImporter) / Notion URL 입력 / Confluence 조회(기존)
        │  (UTType·URL 문자열만 넘김. 파싱·HTTP 없음)
        ▼
Application/Use-case: DocumentIngestionUseCase
  └ 입력 종류 판별 → 어댑터 호출, timeout·실패분류(DocumentIngestionResult)·fail-soft·pending 정책
        │
        ▼
Infrastructure/Adapter
  ├ FileDocumentExtractor   (md/txt: Foundation, pdf: PDFKit)
  ├ NotionMCPService(기존)   (fetchPageText 노출 — OAuth/MCP 재사용)
  └ ConfluenceService(기존)
        │  각 어댑터가 AttachedDocument 반환
        ▼
combinedDocument: String  ← (기존 합류점, 변경 없음)
        ▼
DocumentTermExtractor / 교정 / 요약 (변경 없음)
```

### 핵심 결정

1. **공유 값 타입 `AttachedDocument`** 도입:
   ```
   struct AttachedDocument: Identifiable, Sendable, Hashable {
       let id: String            // 안정 식별(파일 경로 해시 / Notion url / confluence url)
       let title: String
       let text: String          // 평문 (cap 적용 후)
       let sourceKind: SourceKind  // .file / .notion / .confluence / .manual
       let sourceLabel: String?  // 파일명·URL 등 표시용(민감경로 금지: lastPathComponent)
   }
   enum SourceKind: Sendable { case file, notion, confluence, manual }
   ```
   - **텍스트 cap**: 소스별 본문은 공통 상한(잠정 4000자, 기존 Confluence `contextBlock` 3500자·`contextText` 1200자 정책과 정합)으로 잘라 `combinedDocument` 비대화·LLM 토큰 초과를 막는다. 공통 formatter가 cap·구분 헤더를 적용.
   - **Confluence 관계**: 이번 ADR에서 `ConfluenceService.ContextDocument`를 마이그레이션하지 **않는다**(수술적 변경). Confluence는 기존 `contextBlock`을 유지하고, `combinedDocument` 합류 시점에서만 결과를 합친다. `AttachedDocument`로의 통합은 향후 과제로 남긴다(중복은 인지된 비용).

2. **파일 추출 `FileDocumentExtractor`(Infra)**:
   - md/txt: Foundation `String(contentsOf:encoding:)`(UTF-8 우선, 실패 시 fallback).
   - pdf: PDFKit `PDFDocument(url:)?.string`. 빈 결과(스캔본/CJK 매핑 누락)는 `.emptyContent`로 구분 → **OCR fallback**(아래)으로 넘어감.
   - **이미지 파일·OCR**: 이미지(png/jpg/heic/tiff 등) 및 텍스트 없는 PDF는 Vision `VNRecognizeTextRequest`(`recognitionLanguages = ["ko-KR","en-US"]`, on-device)로 OCR. 경로: 이미지→`CGImage`→Vision; PDF→`PDFPage.thumbnail`/렌더→`CGImage`→Vision. Vision은 백그라운드 큐에서 실행(프리징 무관). **OCR 페이지 상한**(잠정 30p)으로 지연을 bound하고, 초과/지연 시 진행률·취소 + 부분 결과 fail-soft. OCR 결과가 비면 `.emptyContent`.
   - `supportedDocumentContentTypes: [UTType]` 단일 출처(md/txt/pdf + 이미지 UTType). 기존 `FileAudioExtractor.supportedContentTypes` 패턴.
   - **다중 선택**: `FileDocumentExtractor`는 단일 URL→`DocumentIngestionResult`를 다루고, 복수 파일은 use-case/UI가 `[AttachedDocument]`로 모은다(2단계 cap: 개당 + 합산).
   - **동시성(실측으로 확정)**: **백그라운드 추출을 채택한다.** `PDFDocument`는 `Task.detached(.userInitiated)` 클로저 안에서 생성·`.string` 접근까지 끝내고 **반환값은 `String`(Sendable)만** 경계를 넘긴다(PDFDocument 인스턴스는 actor 경계 밖으로 내보내지 않음). `@MainActor` 제약은 두지 않는다.
     - 근거: PDFKit 백그라운드 프로브(`Tests/MintoTests/PDFKitBackgroundProbeTests.swift`, 2026-06-23) — Swift 6 strict concurrency에서 위 패턴 컴파일·실행, 20p 추출 91ms·크래시 없음·한글/ASCII 추출 OK, 동시 8건 8/8 성공(thread-safety), 50p 추출 background 64.7ms ≈ mainActor 63.2ms.
     - 따라서 "메인스레드 프리징 방지용 페이지 상한"은 **불필요**(폐기). 파일 크기는 **느슨한 sanity 가드**(잠정 50MB, 거대 파일 메모리 적재 방지)만 둔다.
     - 단, 한글 추출 OK는 *합성 PDF* 기준 — 임의 제작도구의 실제 한글 PDF는 빈 텍스트(producer별 ToUnicode 누락) 가능 → `.emptyContent`로 분류, 향후 OCR fallback 분기 유지.

3. **Notion `NotionMCPService` 재사용(C1 해소)**:
   - 기존 private `fetchText`를 감싸는 **public `func fetchPageDocument(url:) async -> DocumentIngestionResult`** 를 추가. `makeConnectedClient(interactive: false)`로 비대화형 연결 → `fetchText` → `AttachedDocument(sourceKind: .notion)`.
   - **새 서비스·Internal Token·새 Keychain 키·별도 설정 UI 없음.** 이미 Notion 연결한 사용자는 추가 설정 0. 미연결·needsReconnect는 기존 `connectionState`로 판별해 fail-soft.
   - 블록 재귀·pagination·rate limit·URL→id 파싱은 **Notion MCP 서버가 처리** — 우리 코드 밖. (초안에서 우려했던 M4·URL 파싱 복잡도 소거.)

4. **수집 use-case `DocumentIngestionUseCase`(Application)** — 실패 분류·timeout·pending 정책 소유:
   ```
   enum DocumentIngestionResult: Sendable {
       case success(AttachedDocument)
       case failure(DocumentIngestionFailure)
   }
   enum DocumentIngestionFailure: Sendable {
       case unsupportedFormat, accessDenied, tooLarge, readFailed   // 파일
       case emptyContent                                            // 빈 PDF 등
       case notConnected, needsReconnect, fetchFailed, timeout      // Notion/네트워크
   }
   ```
   - **timeout(확정)**: Notion fetch 등 네트워크는 12초(Confluence `:317` 패턴 재사용). 파일은 timeout 대신 **크기 상한**으로 통제.
   - 각 failure는 UI 문구 + Log 필드(사유)로 매핑. **본문·토큰·민감경로는 로그 금지.**

5. **pending 시작 정책(확정)**: 녹음 시작은 **막지 않는다**(fail-soft). 단,
   - 시작 시점에 **수집 완료된 `AttachedDocument`만** `combinedDocument`에 포함한다(빈/미완 텍스트를 downstream에 흘리지 않음).
   - 수집 중(loading)인 첨부가 있으면 시작 버튼 영역에 **"처리 중인 첨부 N개는 제외됩니다"** 를 명시.
   - 이 케이스를 UI 상태 + 단위 테스트로 검증.

6. **개인정보·클라우드 경계 명시**: 첨부 문서(파일·Notion) 본문은 회의 자료로 다뤄지며, **교정/요약이 켜져 클라우드 LLM을 쓰면 본문이 선택된 provider로 전송될 수 있다.** (모든 소스·기존 동작에 공통 — fetch 방식과 무관.) `MeetingSetupView`의 첨부 영역에 로컬 처리/클라우드 전송 경계를 표시(CLAUDE.md UI 원칙 "클라우드 전송 여부 명확히 구분").

7. **로깅(확정)**: 새 file/Notion ingestion 코드는 **`Log.importer`/`Log.oauth`만** 쓴다. 시작·성공(sourceKind, 글자수, http status)·실패(사유 prefix). **`ConfluenceService`/`NotionMCPService`의 기존 `FileHandle.standardError`는 재사용하지 않는다**(레거시 위반은 별도 이슈로 트래킹). 본문·토큰·민감경로 로그 금지.

8. **파일 접근(확정)**: `fileImporter` 반환 URL은 `startAccessingSecurityScopedResource()` 호출 + `defer`로 해제. 회의 시작 직전 즉시 추출이라 bookmark 영속은 불필요. 대형 파일은 크기 상한 초과 시 `.tooLarge`로 안내.

9. **확장 가능성을 코드로 박제하지 않는다**: 1차는 md/txt/pdf/notion만. docx·ZIPFoundation·hwp는 어댑터 추가 지점만 열어두고 **구현·의존성 추가 안 함**(speculative 금지).

### 문서 표현(프롬프트 주입) — 단계별 분리

현재 코드는 교정·요약 모두에 문서 본문을 넣지만 방식이 다르다: 교정은 **raw `document.prefix(1500)`**(`CorrectionPrompt.swift:45`), 요약은 **용어밀도 발췌**(`SummaryPrompt` → `DocumentContextSelector.excerpt`). 멀티소스로 큰 PDF가 들어오면 "앞 1500자"는 표지·목차일 뿐이라 교정에 무용하고 오염·토큰만 늘린다. 단계 성격에 맞춰 표현을 분리한다.

10. **교정 = 용어집만 (raw 문서 제거)**: `CorrectionPrompt`에서 raw `document` 주입(`prefix(1500)`)을 **제거**한다. 교정의 정밀 도구는 용어의 정확한 표기(`glossaryForPrompt`=용어집+문서용어)이고, 안건 산문은 노이즈·오염(문서 문구를 교정 결과로 끌어옴) 위험. Phase 1a 측정에서 교정 문서주입 이득은 이미 marginal로 확인됨. **CER A/B(prefix 있음 vs 없음)로 회귀 없음을 검증한 뒤 제거**한다(기존 `documentTermInjectionCER` 하니스 재사용).

11. **요약 = 문서 요약본 주입 (excerpt 대체, fallback 보유)**: 첨부 문서를 **첨부 시점에 1회 LLM으로 요약**해 `MeetingContext`에 캐시하고(`documentSummary`), 요약 단계 프롬프트에 raw excerpt 대신 이 **요약본**을 넣는다. 더 응축·오염 적음. **fail-soft 폴백 사슬(필수)**: 요약본 생성 실패/LLM 미설정/미완(첨부 직후 시작) → 기존 `DocumentContextSelector.excerpt` → 그것도 불가 시 terms만. 요약본 생성은 best-effort이며 **회의 시작·전사·저장을 막지 않는다**(CLAUDE.md 요약 fail-soft). 아키텍처: 요약본 생성은 Application/use-case가 기존 LLM provider로 수행(어댑터는 fetch만). 품질(요약본 vs excerpt)은 구현 중 측정.

## Alternatives

- **대안 A — UI에서 직접 파싱**: CLAUDE.md "UI는 schema 변환 직접 안 함" 위반, 테스트 불가. **기각**.
- **대안 B — 1차부터 ZIPFoundation(docx/pptx/hwpx)**: 외부 의존성·OOXML 파서·MainActor 부담을 1차에 떠안음, 사용자가 범위에서 제외. **기각(향후 ADR)**.
- **대안 C — Notion에 Internal Integration Token 신규 서비스 추가**(초안 결정): 코드베이스에 이미 OAuth/MCP Notion 연동이 있어 **사용자가 Notion 로그인 2개**를 관리하게 됨. 두 리뷰가 blocker로 지적. **기각 → 기존 MCP 재사용.**
- **대안 D — Notion MCP를 제거하고 Internal Token으로 전면 전환**: 작동 중인 `RelatedInfoService` 검색 교체 + MCP SDK 제거 + 블록 재귀·검색 재구현이라 "문서 첨부"를 "Notion 연동 아키텍처 교체"로 확대. UX도 역행(브라우저 OAuth → 수동 토큰 발급·페이지별 공유). **이번 범위에서 기각**(원하면 별도 ADR. 단 토큰 만료 없음·SDK 의존 감소라는 장점은 기록).
- **대안 E — Notion 공개 페이지 스크래핑**: 공개 페이지가 React SPA라 순수 HTTP로 본문 추출 불가 + 약관 위반. **기각**.

## Consequences

### Positive

- 회의 자료를 복사·붙여넣기 없이 파일/링크로 첨부 → 마찰 감소.
- 기존 `combinedDocument`·downstream **무변경** — 새 소스는 평문으로 흡수.
- 1차 **새 SPM 의존성 0개**. Notion은 **기존 연결 재사용**이라 추가 설정 0.
- 소스 어댑터 구조라 docx/hwp 등은 후속 ADR에서 어댑터만 추가(확장점 명확).
- 교정 입력에서 raw 문서 제거 → 토큰·오염(문서 문구 전이) 감소, 교정은 용어 정밀도에 집중.
- 요약은 raw 발췌 대신 응축 요약본 → 더 적은 토큰으로 더 깨끗한 맥락(측정으로 확인 예정).

### Negative

- PDFKit이 스캔본/일부 한글 PDF에서 빈 텍스트면 → Vision OCR fallback. OCR 자체도 비면 `.emptyContent` 안내.
- OCR(Vision)은 페이지당 신경망 추론이라 느림(수백 ms~초/p) → 백그라운드 + 페이지 상한 + 진행률/취소로 통제. 정확도는 입력 품질(해상도·기울기·손글씨)에 민감 → 오인식이 참고자료에 섞일 수 있음(안내).
- 이미지 파일(스크린샷·문서 사진)도 소스로 추가됨.
- 파일 IO·Notion fetch가 회의 시작 직전 흐름에 끼어 지연 가능 → 비동기·timeout·pending 정책·진행 표시로 통제.
- 지원 포맷 한정("왜 pptx는 안 되나") → 기대 관리(안내 문구) 필요.
- 첨부 본문이 LLM provider로 갈 수 있음 → UI 경계 표시로 투명화(기능 자체는 기존과 동일 범위).
- `AttachedDocument`와 `ContextDocument` 이중 타입 일시 공존(인지된 비용, 향후 통합 과제).
- 요약본 생성에 첨부 시점 LLM 호출 1회 추가(비용·지연·실패경로) → 캐시·fail-soft 폴백으로 통제.
- 문서 본문이 요약본 생성을 위해 LLM provider로 전송(기존 "문서→LLM" 경계와 동일 범위, 새 경계 아님).

## Migration

- 기존 수동 텍스트·Confluence·Notion(MCP) 경로 모두 유지(첨가만). `combinedDocument` 시그니처·`onStart`·저장 schema 변경 없음(수집 계약 유지).
- **문서 표현 변경의 backward-compat**: 교정에서 raw 문서 제거는 CER A/B 통과 후 적용. 요약본 주입은 폴백 사슬(요약본→excerpt→terms)로 기존 동작이 항상 하한선으로 보장 — 요약본이 없거나 실패해도 현행 excerpt 동작과 동일.
- **combinedDocument 결합 순서(확정)**: 수동 텍스트 → 첨부 파일 → Notion 페이지 → Confluence 검색결과. (사용자가 직접 입력/선택한 것을 앞에 두어 LLM 참조 가중치를 높임.)
- Notion은 기존 Keychain `notion-mcp` 연결 그대로. 신규 토큰·키 없음.

## Rollback

- 어댑터·use-case·UI 진입점은 가산적(additive). 문제 시 `MeetingSetupView`의 파일/Notion-URL 입력 진입점만 숨기면 기존 동작(수동+Confluence+Notion검색)으로 즉시 복귀.
- `NotionMCPService`에 추가한 `fetchPageDocument`는 신규 public 메서드일 뿐 기존 search/connect 경로 무영향 → 제거만으로 롤백.
- 새 저장 schema·migration 없음 → 데이터 롤백 불필요.

## Verification

- **단위 테스트**: `FileDocumentExtractor`(md/txt/pdf 픽스처 → 평문, 빈/손상 PDF → `.emptyContent`, 대형 파일 → `.tooLarge`), `NotionMCPService.fetchPageDocument`(미연결→`.notConnected`, needsReconnect, fetch 성공→AttachedDocument), `AttachedDocument` cap·combinedDocument 결합 순서.
- **문서 표현 측정**: 교정 terms-only는 `documentTermInjectionCER` A/B(prefix 있음 vs 없음)로 CER 회귀 없음 확인 후 제거. 요약본 주입은 요약 품질(요약본 vs excerpt) 측정 + 폴백 사슬(요약본 실패→excerpt→terms) 단위 테스트.
- **OCR 측정(착수 전 프로브)**: Vision `VNRecognizeTextRequest`의 한국어(ko-KR) 지원·실제 인식 정확도·페이지당 지연을 실제 회의 스캔본/이미지 1~2개로 실측(PDFKit 프로브와 동형). 이미지 파일·스캔 PDF fallback 단위 테스트.
- **fail-soft·pending 테스트**: 파일 권한거부/빈PDF/대형파일/Notion 미연결/timeout에서 회의 시작이 막히지 않고 사유 안내. 수집 중 시작 → 미완 첨부 제외 + "N개 제외" 표시.
- **Pencil 선설계(게이트)**: UI 구현 전 `Resources/designs/`에 `.pen` + export. 상태: 지원 포맷 안내, 스캔 PDF 빈 텍스트, Notion 연결 필요, 클라우드 전송 경계, 조회 중 시작 정책, empty/loading/success/error/disabled.
- **수동 QA**: 실제 앱(`./scripts/dev.sh run`)에서 md·txt·pdf 첨부, Notion URL 첨부(연결/미연결/needsReconnect). LLM/연동 변경 게이트(provider 없음/미로그인/토큰 오류/네트워크 오류).
- **로그/관측**: importer/oauth 카테고리 시작·성공·실패. **본문·토큰·민감경로 미포함** 확인. 새 코드에 `FileHandle.standardError` 없음.
- **회귀**: 기존 Confluence·수동 텍스트·Notion 검색(RelatedInfoService) 경로, 문서 용어 추출(CER) 테스트 불변.

## ADR 상태 전환

- 현재 `Proposed`. **다중 관점 리뷰 1차 반영 완료**(이 개정). 잔여 확인(텍스트 cap 수치·파일 크기 상한 수치) 합의 후 **구현 착수 직전 `Accepted`** 로 전환한다. 구현 완료는 작업 로그로 기록(상태를 "구현 완료"로 오용하지 않음).

## 다중 관점 리뷰 기록

- 1차 리뷰(opus critic + Codex, 2026-06-22): C1(기존 NotionMCPService 충돌, blocker) 양쪽 독립 적발 → 기존 MCP 재사용으로 해소. 개인정보 경계·PDFKit concurrency·timeout·실패 enum·pending 정책·Pencil 게이트·security-scoped URL·로깅 규약 반영. 판정 REVISE → 본 개정으로 blocker 해소.
- CLAUDE.md "ADR 필요 조건" 해당: 공유 추상화(`AttachedDocument`/소스 어댑터) 추가, 개인정보가 외부 provider로 나가는 범위(첨부 본문→LLM) 명시. (Notion은 기존 연동 재사용이라 "새 외부 dependency"에는 해당 안 함.)
