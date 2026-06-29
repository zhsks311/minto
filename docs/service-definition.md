# Minto2 기능 정의서

작성일: 2026-06-09
갱신일: 2026-06-29 (현재 구현 상태 반영 — 근거: `Sources/Minto/Services`·`Sources/Minto/UI` 코드)
상태: 갱신본

## 1. 서비스 목적

Minto2는 Mac에서 회의를 기록하고, 전사와 요약을 사용자가 다시 찾고 공유할 수 있는 회의 지식 도구다.

핵심 가치는 다음이다.

- 회의 중 발화를 가능한 한 빠르게 전사한다.
- 전사 결과를 회의 문맥에 맞게 읽기 좋은 회의록으로 정리한다.
- 저장된 회의를 검색하고, 필요하면 관련 근거를 바탕으로 답변을 생성한다.
- Confluence, Notion 같은 업무 문서와 연결해 회의 전후 맥락을 잇는다.
- 개인정보와 로컬 우선 흐름을 존중하면서, 사용자가 선택한 경우에만 외부 LLM/API를 사용한다.

## 2. 핵심 사용자 흐름

### 2.1 실시간 회의 기록

1. 사용자가 새 회의를 시작한다.
2. 회의 주제, 이번 회의 용어, 참고 문서를 선택적으로 입력한다. 용어는 전역 용어집 분류 선택과 직접 입력을 함께 쓸 수 있다.
3. 앱이 마이크, 시스템 사운드, 또는 둘을 혼합한 입력 소스를 전사한다.
4. 전사는 회의 목록의 현재 회의 항목에 바로 쌓이며, 발화 구간에 화자 라벨이 붙는다.
5. 사용자는 필요할 때 오버레이를 열어 전사 흐름을 볼 수 있다.
6. 회의 종료 시 회의 기록이 저장되고, 요약/목차/회의 내용 정리/결정사항/할 일/미해결 질문/전사/화자별 발화를 볼 수 있다.
7. 저장된 전사는 단어 타임스탬프와 최종 화자분리 결과를 이용해 문장 단위 화자 세그먼트로 정리된다.
8. 화자 라벨은 사용자가 편집·실명 지정할 수 있고, 보이스프린트로 회의 간 화자 매칭을 시도한다.

### 2.2 사후 회의록 작성

1. 사용자가 음성 또는 영상 파일을 넣는다.
2. 앱이 파일을 16kHz mono PCM으로 변환한다.
3. 기존 전사, 교정, 요약, 저장 pipeline을 재사용한다.
4. 결과는 일반 회의와 동일하게 회의 목록에 저장된다.

### 2.3 회의 검색과 답변

1. 사용자가 회의 목록에서 키워드나 질문을 입력한다.
2. 앱은 저장된 회의의 요약, 전사, 결정사항, 할 일, 미해결 질문을 검색한다.
3. 임베딩 인덱스가 준비된 경우 semantic search를 함께 사용한다.
4. 사용자가 답변 생성을 요청하면, 검색된 근거 chunk만 LLM에 전달한다.
5. 답변은 출처 회의, 섹션, 시간 정보와 함께 표시한다.

### 2.4 내보내기

1. 사용자가 회의 상세에서 내보내기를 누른다.
2. 앱은 선택지를 보여준다.
   - Markdown 파일
   - 클립보드 복사
   - Confluence
3. Confluence token이 없으면 Confluence 선택지는 비활성화하고 설정으로 안내한다.
4. token이 있으면 내보낼 위치와 제목을 확인한 뒤 publish한다.

## 3. 현재 기능

> 2026-06-28 기준. 초안의 "확장 예정" 다수가 구현되어 현재 기능으로 이동했고, 화자분리·문서 첨부·Claude Code CLI provider·용어집 메인 관리가 현재 기능에 포함됐다.

**입력·전사**
- 메뉴바 앱 및 회의 목록 메인 윈도우
- 실시간 마이크 입력, 시스템 사운드 입력, 마이크+시스템 혼합 입력 (`SystemAudioSource`, `MixedAudioSource`, `SystemAudioReadinessChecker`)
- 음성/영상 파일로 사후 회의록 작성 (`MeetingFileImportUseCase`, `FileImportSetupSheet`)
- WhisperKit 기반 로컬 STT, Apple SpeechAnalyzer/SFSpeechRecognizer 계열 STT 후보, STT 엔진 선택 (`SpeechEngine`)
- VAD 기반 chunking과 preview/final transcript 분리 (기본 Silero VAD, 에너지 VAD 폴백)
- 전사 오버레이 표시와 접기

**화자분리 (신규)**
- 실시간 화자 배정과 종료 시 확정 (`LiveSpeakerAssignmentUseCase`, `LiveDiarizationFinalizeUseCase`, `Diarization/LiveDiarizationReconciler`)
- 실시간 화자 라벨 표시와 저장 시 최종 VBx 화자분리 결과로 재배정. 저장 재조정은 라이브 미리보기보다 오프라인 결과를 우선한다.
- 단어 타임스탬프 기반 문장 단위 화자 분할 (`SentenceSpeakerSplitter`). 저장·파일 임포트 시 한 전사 청크 안에 여러 화자가 섞이면 문장/화자 전환 단위로 쪼개고, 각 문장에 단어 단위 다수결 화자를 붙인다. 라이브 화면은 미리보기 역할이라 기존 청크 단위 라벨을 유지한다.
- 화자분리 provider 실패 시 채널 기반 라벨로 자동 강등하는 fail-soft 경로
- 채널 기반 화자 라벨링 (`ChannelSpeakerLabeler`)
- 화자 라벨 편집·실명 지정, 보이스프린트로 회의 간 화자 매칭 (`VoiceprintMatching`, `VoiceprintStore`)

**교정·요약**
- LLM 기반 전사 교정과 증분/최종 요약 (교정 설정과 요약 설정 분리 — `LLMSummarySettingsService`)
- 회의 시작 시 주제, 용어집, 문서 문맥 입력
- 교정 prompt에는 raw 문서 본문을 직접 넣지 않고, 문서에서 추출한 용어를 용어집으로 병합해 사용한다.
- 요약 prompt에는 첨부 문서 요약본을 우선 사용하고, 실패 시 문서 excerpt와 용어로 fail-soft fallback한다.
- 전역/회의별 용어집 관리와 관련 용어 선별 (`GlossaryStore`, `GlossaryQueryExpander`, `GlossaryAliasPrefillService`)
- 전역 용어집 관리는 메인 회의 목록의 `용어집` 버튼에서 열며, 새 회의·파일 가져오기·다시 요약은 회의별 용어 선택 흐름을 유지한다.

**LLM provider**
- 로컬 LLM provider (`LocalLLMProvider`), API provider(OpenAI/Gemini/Claude/OpenRouter), 계정 로그인 provider(ChatGPT/Gemini/Copilot), Claude Code CLI provider 레지스트리·선택 (`LLMProviderRegistry`, `LLMProviderSelection`, `LLMAPIKeyTextProvider`, `ClaudeCodeCLIProvider`)
- Claude API provider는 앱 설정/Keychain의 API 키 경로를 사용하고, Claude Code CLI provider는 사용자가 명시적으로 선택한 로컬 `claude` 로그인·구독 경로를 사용한다. CLI provider 실행 시 `ANTHROPIC_API_KEY`는 제거해 API 키 경로로 조용히 전환되는 일을 막는다.
- 교정·요약·검색 답변 provider는 기능별 capability에 따라 노출되며, 실행 중 선택 provider 변경도 반영한다.

**검색·답변**
- 회의 목록 검색, 저장 회의 embedding index 기반 semantic search (`MeetingSearchIndex`, `MeetingSearchEmbeddingIndex`)
- 검색 근거 기반 LLM 답변 생성 (`MeetingSearchAnswerController`, `MeetingSearchAnswerSettingsService`)

**연동·내보내기**
- 회의 시작 참고 문서로 로컬 파일(md/txt/pdf), Notion 페이지, Confluence 페이지 링크를 첨부한다. 스캔 PDF는 OCR fallback을 사용하고 OCR 인식 언어는 자동 감지한다.
- 관련 문서 탭에서 Notion/Confluence 조회 (`NotionMCPService`, `RelatedInfoService`)
- Markdown / 클립보드 / Confluence 내보내기 (`MeetingExporter`, `ConfluenceService`, `ConfluenceExportSheet`)

**저장·보안**
- 회의 저장 JSON
- 비밀값 저장은 기본 Keychain, 개발 opt-in으로 file 기반 SecretStore (`KeychainTokenStorage`)

**개발/연구 도구 (사용자 기능 아님)**
- STT 엔진 비교 벤치마크 프레임워크 (`tools/stt-benchmark/`) — 어느 STT 엔진을 채택할지 신뢰성 있게 측정. 사용법: `tools/stt-benchmark/README.md`, 방법론: ADR 0004.

## 4. 확장 예정 / 개선 방향

> 초안의 확장 예정 항목 대부분은 §3으로 이동. 남은 방향은 아래. 세부 구현 현황은 `docs/work/`·`docs/work-log.md` 참조.

- provider별 모델 목록 fetch/cache와 수동 입력 fallback (부분 구현, 확장 여지)
- Confluence token 발급 가이드 보강
- 화자분리 경계 정확도 추가 검수, 보이스프린트 등록 UX 개선
- STT 엔진 채택 결정 (벤치마크 프레임워크 실측 후 — speech_analyzer 등)
- 검색 답변 품질·근거 표시 고도화

## 5. 데이터 원칙

- 원본 전사, 교정 전사, 요약, export 결과는 구분한다.
- 검색과 내보내기에는 사용자가 읽기 쉬운 정규화 전사를 사용한다.
- CER 같은 STT 정확도 측정에는 원문과 정규화/교정을 분리한다.
- 외부 LLM으로 전송되는 데이터는 UI에서 사용자가 이해할 수 있어야 한다.
- token, prompt, transcript 원문은 로그에 남기지 않는다.
- 저장 schema 변경은 backward-compatible 하거나 migration/rollback 계획을 둔다.

## 6. 아키텍처 경계

기본 방향은 다음이다.

> Domain/Core <- Application/Use-case <- Infrastructure/Adapter <- UI

- Domain/Core
  - 전사 정규화, 용어 매칭, 검색 scoring, export 변환 규칙
  - IO, HTTP, Keychain, UserDefaults에 직접 의존하지 않는다.
- Application/Use-case
  - 전사, 교정, 요약, 검색, 내보내기 workflow orchestration
  - retry, timeout, idempotency, job 상태 전이를 소유한다.
- Infrastructure/Adapter
  - LLM provider, Confluence, Notion, Keychain, 파일 변환, embedding backend
  - domain rule을 넣지 않는다.
- UI
  - 상태 표시와 사용자 명령 전달
  - prompt 생성, provider request 구성, 저장 schema 변환을 직접 하지 않는다.

## 7. 사용자 경험 원칙

- 첫 화면은 새 회의, 검색, 파일로 회의록 만들기를 바로 이해할 수 있어야 한다.
- 설정은 progressive disclosure를 사용한다.
- 비개발자에게 모델명만 던지지 않는다. 추천, 빠름, 품질 우선, 저비용, 로컬 처리 같은 언어를 사용한다.
- Confluence, LLM API, 시스템 사운드처럼 권한/토큰이 필요한 기능은 상태와 다음 행동을 분명히 보여준다.
- 검색 답변은 반드시 근거 회의와 시간을 함께 보여준다.
- 클라우드로 나가는 기능과 기기 안에서 처리되는 기능을 구분한다.

## 8. 완료 기준

이 문서의 기능은 다음 증거가 있을 때 완료로 본다.

- 관련 코드가 계획된 Phase에 맞게 구현되어 있다.
- 단위/통합 테스트가 통과한다.
- UI 변경은 Pencil 산출물 또는 앱 실행 QA 증거가 있다.
- benchmark가 필요한 기능은 `docs/benchmark/`에 결과가 있다.
- 아키텍처 변경은 ADR과 코드리뷰 기록이 있다.
- 작업 내용은 `docs/work-log.md`와 세션별 `docs/work-log/` 문서에 기록되어 있다.
