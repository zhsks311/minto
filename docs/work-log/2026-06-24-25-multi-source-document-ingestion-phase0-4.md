# 다중 소스 문서 수집 Phase 0~4 (수집 레이어)

날짜: 2026-06-24

근거 ADR: `docs/adr/0005-multi-source-document-ingestion.md` (Accepted)
계획: `docs/work/2026-06-22-multi-source-document-ingestion-plan.md`
브랜치: `feat/document-multi-source`

## 변경 요약

회의 시작 첨부 문서를 Confluence+수동텍스트 외에 **로컬 파일(md/txt/pdf/이미지) + Notion 링크**로 확장하는 수집 레이어(Phase 0~4)를 구현했다.

- **Phase 0** — 공유 값 타입 `AttachedDocument`(`id`/`title`/`text`/`sourceKind`/`sourceLabel`) + `SourceKind`, 실패 분류 `DocumentIngestionResult`/`DocumentIngestionFailure`(9케이스), `FileDocumentExtractor`(md/txt, async, UTF-8→인코딩 자동감지 fallback, SHA-256 경로 안정 id, cap/size 가드).
- **Phase 1** — PDF 텍스트 추출(PDFKit). `PDFDocument`를 `Task.detached`에 가두고 `String`만 반환(백그라운드 안전성은 `PDFKitBackgroundProbeTests`로 확인). 못 엶→`.readFailed`, 빈 텍스트(스캔본)→OCR fallback.
- **Phase 2** — 이미지 파일·스캔 PDF OCR(Apple Vision `VNRecognizeTextRequest`, ko-KR+en-US, on-device, 백그라운드). 이미지는 ImageIO로 CGImage 로드, 스캔 PDF는 페이지 렌더(2x)→OCR. OCR 페이지 상한(기본 30p) + 부분 결과 fail-soft.
- **Phase 3a** — `DocumentIngestionUseCase`(Application): `ingest([URL])→BatchResult`(성공 문서 + 분류된 실패), 보안 범위 자원 start/stop, per-file timeout(기본 30s), 입력 순서 유지.
- **Phase 3b** — `MeetingSetupView` "Confluence 문맥 조회" → "참고 문서"로 reframe. fileImporter 다중선택 → UseCase → 첨부 목록(파일명·완료 글자수·제거), 처리 중 표시, `combinedDocument` 결합 순서 수동→파일→Notion→Confluence(완료분만), 하단 클라우드 경계 안내, 빈 상태 힌트.
- **Phase 4** — `NotionMCPService.fetchPageDocument(url:)` public 노출(기존 private `fetchText` 재사용, 새 토큰/Keychain/UI 없음). 연결 가드(notConnected/needsReconnect/emptyContent/fetchFailed). UI에 Notion 링크 입력(연결 시만 활성).

## 측정 (게이트)

- **PDFKit 백그라운드 프로브**(`PDFKitBackgroundProbeTests`, 기존): Swift 6에서 백그라운드 추출 안전·페이지 상한 불필요 확정.
- **Vision ko-KR OCR 프로브**(`VisionOCRProbeTests`, `RUN_OCR_PROBE=1`): 한국어 회의록 합성 이미지 **CER 0.000**(20/28/40pt), 지연 233~248ms(첫 호출 852ms 워밍업), 5장 장당 평균 ~319ms. → Phase 2 진행 확정, 페이지 상한 30p ≈ 9~10초.

## 결정

- 타입 계약은 critic 리뷰 반영(`id: String` 안정 식별, `sourceLabel: String?`, `Hashable`) — ADR §70-79 정합.
- 추출 API는 `async`로 통일(Phase 1/2 백그라운드 수용). 합산 cap·문자열 결합은 UseCase가 아니라 호출자(`combinedDocument`)가 담당.
- Notion은 **새 서비스 없이 기존 MCP 연결 재사용**(ADR blocker C1 해소 방향).
- `FileDocumentExtractor`는 로깅하지 않음(상위 UseCase/UI가 담당). 새 Notion 코드는 `Log.oauth`/`Log.importer`만 사용(기존 `FileHandle.standardError` 미재사용).

## 검증

- `swift build` exit 0(경고 0).
- `FileDocumentExtractor`(16) + `DocumentIngestionUseCase`(5) + `NotionMCPService.fetchPageDocument`(6) = **27 테스트 GREEN**.
- 100% 추가 코드(기존 동작 파일 무수정, MeetingSetupView/NotionMCPService만 surgical 확장).

## 미결 (사용자 자원/판단 필요)

- **앱 실행 QA**: Phase 3b/4 UI는 컴파일만 검증됨. empty/loading/success/error/disabled + 파일·이미지·스캔PDF·Notion 첨부 흐름·처리 중 제외 안내를 `./scripts/dev.sh run`으로 시각 확인 필요.
- **Phase 5 교정 terms-only**: `CorrectionPrompt`의 raw `document.prefix(1500)` 제거 전, `documentTermInjectionCER` A/B로 CER 회귀 없음 측정 선행(LLM provider·corpus 필요).
- **Phase 6 요약 doc-summary**: 첨부 시 문서 요약본 1회 생성·캐시(LLM 필요), 폴백 사슬 요약본→excerpt→terms.
- determinate OCR 진행바: 현재 indeterminate. UseCase 진행률 방출 plumbing이 필요한 후속.
