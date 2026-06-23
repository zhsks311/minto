# 다중 소스 문서 수집 구현 계획 (파일·Notion)

작성일: 2026-06-22
개정: 2026-06-22 (다중 관점 리뷰 1차 반영)
브랜치: `feat/document-multi-source`
워크트리: `/Users/d66hjkxwt9/Idea/private/minto2-wt-document-sources`
근거 ADR: `docs/adr/0006-multi-source-document-ingestion.md`

## 목표

회의 시작 시 첨부 문서 소스를 **로컬 파일(md/txt/pdf 텍스트형) + Notion 페이지 링크**로 확장하고(수집), **문서를 프롬프트에 넣는 표현을 단계별로 분리한다**(교정=용어집만, 요약=문서 요약본). 수집의 `combinedDocument` 합류점은 유지하되, downstream 문서 표현(교정/요약)은 이번에 함께 개정한다.

1차 범위(확정): md/txt, pdf(텍스트형), Notion(**기존 NotionMCPService 재사용**).
제외(향후 ADR): docx/doc, pptx/hwpx, hwp(구), ppt, 스캔 PDF OCR, Notion MCP→Internal Token 마이그레이션.

## 선행 게이트

- ADR 0006이 다중 관점 리뷰 1차를 통과(blocker C1 해소)했다. 잔여 합의(텍스트 cap·파일 크기 상한 수치) 후 **구현 착수 직전 ADR을 Accepted로 전환**한다.
- 리뷰 미해결 항목이 남으면 코드 변경 없음.

## 아키텍처 요약

- **공유 값 타입** `AttachedDocument{id, title, text, sourceKind, sourceLabel}` — 모든 소스의 공통 산출물(평문, cap 적용).
- **Infra 어댑터**: `FileDocumentExtractor`(md/txt/pdf + 이미지·스캔PDF는 Vision OCR), `NotionMCPService`(기존 — `fetchPageDocument` 노출), `ConfluenceService`(기존, 유지).
- **Application**: `DocumentIngestionUseCase` — 입력 종류 판별·어댑터 호출·timeout·실패분류(`DocumentIngestionResult`/`DocumentIngestionFailure`)·fail-soft·pending 정책.
- **UI**: `MeetingSetupView`에 파일 선택(fileImporter)·Notion URL 입력 추가. 파싱·HTTP 직접 수행 금지. 클라우드 전송 경계 표시.

## Phase 구성 (각 Phase = 작은 커밋 + 테스트, 검증 통과 후 다음)

> **Phase 순서 원칙**: 추출(텍스트+OCR)을 UI보다 먼저 완성한다 — UI가 이미지 타입을 노출하기 전에 OCR 추출 경로가 있어야 빈손이 안 된다.

### Phase 0 — 공유 타입 + 파일 추출(md/txt) [의존성 0]
- `AttachedDocument`/`SourceKind`/`DocumentIngestionResult`/`DocumentIngestionFailure` 값 타입.
- `FileDocumentExtractor`(Infra): md/txt는 Foundation `String(contentsOf:encoding:)`(UTF-8 우선 + fallback). 텍스트 cap(개당+합산 2단계) 공통 적용.
- `supportedDocumentContentTypes: [UTType]` 단일 출처.
- **검증**: md/txt 픽스처 → 평문, 빈 파일/깨진 인코딩 → 실패 분류, cap 동작. `swift test --filter FileDocumentExtractor`.

### Phase 1 — PDF 텍스트 추출 [의존성 0]
- `.pdf` 분기: PDFKit `PDFDocument(url:)?.string`. 빈 결과 → `.emptyContent`(에러 아님, Phase 2 OCR fallback 대상).
- **동시성 규약(프로브로 확정)**: **백그라운드 추출.** `Task.detached(.userInitiated)` 안에서 PDFDocument 생성·`.string`까지 끝내고 `String`만 반환. `@MainActor` 제약·페이지 상한 **없음**. 파일 크기는 느슨한 sanity 가드(잠정 50MB)만. 근거: `Tests/MintoTests/PDFKitBackgroundProbeTests.swift`(20p 91ms·동시8/8·한글OK).
- **검증**: 텍스트 PDF 픽스처 → 평문, 초대형 파일 → `.tooLarge`. 픽스처는 `Tests/MintoTests/Fixtures/`에 명시 준비.

### Phase 2 — OCR: 이미지 파일 + 스캔 PDF fallback (Vision) [의존성 0]
- **(게이트 — 통과 ✅ 2026-06-23)** Vision ko-KR 프로브(`Tests/MintoTests/VisionOCRProbeTests.swift`, `RUN_OCR_PROBE=1`): 한국어 회의록 합성 이미지 **CER 0.000**(20/28/40pt), 지연 233~248ms(첫 호출 852ms 워밍업)·5장 장당 평균 319ms. → ko-KR 실용 확인, Phase 2 진행. 페이지 상한 30p ≈ 9~10초(진행률 UI 필수). 합성 기준이라 실제 스캔본은 CER 상승 가능(오인식 안내 유지).
- `FileDocumentExtractor` OCR 경로: 이미지(png/jpg/heic/tiff)→`CGImage`→Vision; 텍스트 없는 PDF(`.emptyContent`)→`PDFPage` 렌더→`CGImage`→Vision. `recognitionLanguages=["ko-KR","en-US"]`. **백그라운드 큐** 실행.
- **OCR 페이지 상한**(잠정 30p) + 진행률/취소 + 부분결과 fail-soft. OCR 결과 비면 `.emptyContent`.
- 이미지 UTType을 `supportedDocumentContentTypes`에 추가.
- **검증**: 이미지 픽스처 → OCR 텍스트, 스캔 PDF 픽스처 → OCR fallback, 페이지 상한 초과 동작. Vision ko-KR 정확도/지연 기록.

### Phase 3 — DocumentIngestionUseCase + 파일 첨부 UI (Pencil 게이트 선행, 다중선택)
- **(게이트) Pencil 선설계**: `Resources/designs/`에 `.pen`+export. 상태: 지원 포맷 안내(텍스트/이미지/OCR), 스캔 PDF·OCR 진행률, Notion 연결 필요, 클라우드 전송 경계, 조회/OCR 중 시작 정책, 다중 파일 목록, empty/loading/success/error/disabled.
- `DocumentIngestionUseCase`(Application): 파일 URL(들) → `FileDocumentExtractor` → `[AttachedDocument]`. timeout·실패분류·fail-soft. **pending 정책**: 시작 시 완료된 첨부만 합류, 미완 N개 제외 표시.
- `MeetingSetupView`: fileImporter(`allowsMultipleSelection: true`, allowedContentTypes = supportedDocumentContentTypes), `startAccessingSecurityScopedResource`+`defer`(파일별), 선택 파일 목록·개별 상태(OCR 진행 포함), 클라우드 경계 안내. `combinedDocument` 결합 순서(수동→파일→Notion→Confluence), 2단계 cap.
- 로그: `Log.importer` 시작·성공(sourceKind, 글자수)·실패(사유). 본문·민감경로 금지. `FileHandle.standardError` 미사용.
- **검증**: 앱 실행(`./scripts/dev.sh run`) — md/txt/pdf/이미지 다중 첨부, 상태 5종, OCR 진행률, 수집 중 시작 시 "N개 제외". 회귀: Confluence·수동 텍스트 정상.

### Phase 4 — Notion 페이지 첨부 (기존 MCP 재사용)
- `NotionMCPService`에 **public `fetchPageDocument(url:) async -> DocumentIngestionResult`** 추가: `makeConnectedClient(interactive:false)` → 기존 `fetchText` → `AttachedDocument(sourceKind:.notion)`. 미연결→`.notConnected`, needsReconnect 판별, timeout 12초.
- **새 서비스·Internal Token·Keychain 키·설정 UI 없음.** 기존 Notion 연결(`SettingsView`) 그대로 재사용.
- `DocumentIngestionUseCase`에 Notion 경로 추가. `MeetingSetupView`에 Notion URL 입력 필드(연결 시만 활성, 미연결 시 "설정에서 Notion 연결" 안내).
- 로그: `Log.oauth`/`Log.importer` 시작·성공(http status, 글자수)·실패(사유). 토큰·본문 금지.
- **검증**: 연결/미연결/needsReconnect, fetch 성공/실패/빈본문/timeout. `fetchPageDocument` 단위 테스트(연결 상태별). 실제 앱 QA. 회귀: `RelatedInfoService` Notion 검색 불변.

### Phase 5 — 교정 문서 표현: 용어집만 (raw prefix 제거)
- 측정 선행: `documentTermInjectionCER` A/B(`CorrectionPrompt` raw `document.prefix(1500)` 있음 vs 없음)로 CER 회귀 없음 확인.
- 확인되면 `CorrectionPrompt.build`에서 raw `document` 주입 제거(용어집=`glossaryForPrompt`만 유지). `LLMCorrectionService`의 document 전달 정리.
- **검증**: CER A/B 회귀 없음, 교정 단위 테스트, 로그에 문서 본문 미포함.

### Phase 6 — 요약 문서 표현: 문서 요약본 주입 (폴백 보유)
- `MeetingContext`에 `documentSummary: String?` + 첨부 시점 1회 생성(Application use-case가 기존 LLM provider 사용, async·캐시). 생성 토큰 가드(stale 방지)는 기존 `documentTermExtractionID` 패턴 참고.
- `SummaryPrompt`(incremental/final): 요약본 있으면 excerpt 대신 주입. **폴백 사슬**: 요약본 없음/실패/LLM미설정 → `DocumentContextSelector.excerpt` → terms. fail-soft(회의 시작·전사·저장 무영향).
- 로그: summary 카테고리 시작·성공(글자수)·실패(사유). 본문 금지.
- **검증**: 요약 품질(요약본 vs excerpt) 측정, 폴백 사슬 단위 테스트(요약본 실패→excerpt→terms), LLM 미설정 시 동작.

### Phase 7 — 문서·로그 마무리
- 작업 로그(`docs/work-log/`) 작성, ADR 상태 Accepted(착수 시점에 이미 전환했으면 구현완료 note만).
- 지원 포맷 안내·미지원 포맷 처리(향후 확장 표시) 정리.

## 검증 게이트(공통)

- `git diff --check`
- `swift build --disable-sandbox --scratch-path /tmp/minto2-docsrc-build`
- `swift test --disable-sandbox --scratch-path /tmp/minto2-docsrc-test`
- UI 변경: 앱 실행 후 empty/loading/success/error/disabled + pending(수집 중 시작) 확인
- 연동 변경: Notion 미연결/오류/네트워크 오류, 로그 민감정보 부재 확인

## 작업 규범

- 조사/문서 = 나, 코드 변경 = Codex 위임, 리뷰 = 크로스모델(opus critic + Codex). ([[work-pipeline]])
- 기능 변경과 리팩터링을 한 커밋에 섞지 않는다.
- speculative 금지: 1차 범위 밖 포맷(docx/hwp)·Notion 마이그레이션을 미리 만들지 않는다.

## 잔여 확인(착수 전 합의)

- 텍스트 cap: 교정은 raw 문서 제거로 무관해짐. 요약은 요약본(짧음)/excerpt budget으로 통제. 파일 크기 sanity 가드(잠정 50MB)만 — PDF 페이지 상한은 백그라운드 추출 확정으로 폐기.
- 요약본 생성 시점(첨부 즉시 vs lazy)·요약 길이 목표·생성 실패 시 재시도 여부.
- Notion fetch가 반환하는 본문 형태(마크다운/평문)와 cap 적용 위치.
- OCR 페이지 상한 수치(잠정 30p)·진행률 UI 형태 — Vision 프로브 지연 결과로 확정.
- 결정됨: 파일 다중 선택 = 허용(`allowsMultipleSelection: true`), 2단계 cap.

## 리뷰에서 해소된 항목 (기록)

- **C1(blocker)**: 새 Notion 서비스 → 기존 `NotionMCPService` 재사용으로 전환.
- 개인정보 경계(본문→LLM) 명시, PDFKit concurrency 확정, timeout 수치 확정, 실패 enum 도입, pending 시작 정책 확정, Pencil 게이트 추가, security-scoped URL·대형파일 정책 추가, 로깅 `Log.*` 한정.
- M4(블록 재귀·rate limit)·URL→id 파싱: MCP 서버가 처리 → 우리 코드 밖으로 소거.
