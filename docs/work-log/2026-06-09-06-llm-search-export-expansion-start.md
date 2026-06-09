# LLM/Search/Export 확장 구현 시작

날짜: 2026-06-09
브랜치: `feature/llm-correction-search-export`
상태: 진행 중

## 작업 요약

대규모 기능 확장을 바로 코드에 넣기 전에, 구현 기준이 되는 기능 정의와 프로젝트 컨벤션을 정리했다.
이후 첫 코드 슬라이스로 LLM 공급자 공통 계약을 추가해 로컬 LLM, GPT, Gemini, Claude, OpenRouter, Copilot을 같은 방식으로 붙일 수 있는 기반을 만들었다.
코드리뷰/아키텍처 리뷰에서 `provider registry`, 기능별 protocol 분리, 기존 provider enum과의 bridge가 필요하다는 `WATCH` 의견이 나와 이를 반영했다.
그 다음 기존 Codex/Gemini/Copilot 계정 로그인 경로를 `LegacyAccountLLMTextProvider` adapter로 감싸고, 교정/요약 서비스가 직접 OAuth service를 switch하지 않도록 전환했다.
adapter 전환 코드리뷰에서 provider protocol 전체를 `@MainActor`로 묶으면 로컬 LLM/embedding 확장에 불리하다는 지적이 있어, protocol은 actor 독립으로 되돌리고 legacy adapter 내부에서만 기존 OAuth service로 actor hop 하도록 수정했다.
다음 슬라이스로 공식 API key 기반 GPT/Gemini/Claude/OpenRouter provider를 추가했다. API key는 OAuth 토큰과 다른 Keychain service namespace에 저장하고 메모리 캐시를 둬 설정 화면 렌더링 중 반복 Keychain 접근을 줄였다. 코드리뷰에서 지적된 원문 전사/교정 결과 stderr 노출도 제거해 길이 정보만 남기도록 바꿨다.
후속 코드리뷰에서 지적된 API key 저장/삭제 실패와 cache 불일치, transport 오류 정규화, 설정 화면 모델 목록 UX 불일치도 커밋 전에 반영했다. Keychain 저장/삭제 성공 후에만 cache를 갱신하고, API provider의 transport 오류는 공통 `LLMProviderError.network`로 변환한다. 설정 화면은 저장된 API key가 있으면 live model catalog를 조회하고, 실패하거나 키가 없으면 기본 추천 모델과 직접 입력 fallback을 제공한다. 모델 목록 조회 실패는 인증 실패, 요청 한도, 네트워크 문제를 구분해 사용자에게 보여준다.
그 다음 아키텍처/UX 리뷰 결과에 따라 요약 provider를 교정 provider에서 분리했다. `전사 다듬기`와 `회의록 정리`는 독립 토글로 나누고, provider/API key/model UI는 `AI 연결` 하나로 모아 화면 중복을 줄였다. 기존 사용자는 앱 시작 또는 설정 진입 시 교정 provider를 요약 provider로 한 번 migration해 기존 요약 동작이 갑자기 꺼지지 않도록 했다.
코드리뷰에서 확인된 `전사 다듬기 off + 회의록 정리 on` 라이브 증분 요약 누락도 수정했다. 이제 교정이 꺼져 있거나 실패하면 원문 batch로 증분 요약을 갱신하고, 교정이 성공하면 교정본으로 요약을 갱신한다. migration은 비동기 `Task`가 아니라 앱 시작 main actor 경로에서 동기 실행되도록 옮겼다.
후속 병렬 슬라이스에서 로컬 LLM의 Ollama context window를 앱 설정과 benchmark runner 양쪽에서 통제하도록 했다. DeepSeek 측정 실패가 Ollama model context `131072` 상태에서 발생했기 때문에, 앱 기본값과 runner 기본값은 `4096` tokens로 두고 `512...32768` 범위로 제한한다. OpenAI-compatible endpoint에는 `num_ctx`를 보내지 않는다.

## 변경 파일

- `docs/service-definition.md`
  - 서비스 목적, 현재 기능, 확장 예정 기능, 데이터/UX/아키텍처 원칙 정의
- `AGENTS.md`
  - Codex/agent용 프로젝트 작업 기준
- `CLAUDE.md`
  - Claude/Codex 공유 프로젝트 컨벤션
- `docs/adr/0000-template.md`
  - ADR 작성 템플릿
- `docs/adr/0001-llm-search-export-expansion-governance.md`
  - 확장 작업의 아키텍처 거버넌스 결정
- `docs/work-log.md`
  - 이번 세션 인덱스 추가
- `Sources/Minto/Services/LLMProvider.swift`
  - 모델 카탈로그, 텍스트 생성, 임베딩 provider protocol 분리
  - 요청/응답/모델 정보/오류 타입 추가
  - `LLMProviderError`를 `LocalizedError`로 연결해 UI 오류 문구 유실 방지
  - provider protocol은 로컬 LLM/embedding 확장을 위해 actor 독립 + `Sendable` 경계로 유지
- `Sources/Minto/Services/LocalLLMProvider.swift`
  - `MINTO_LOCAL_LLM_CONTEXT_WINDOW`와 `localLLMContextWindow` 저장값을 추가
  - Ollama `api/generate` 요청 `options`에 `num_ctx`를 포함
  - context window를 `512...32768` 범위로 제한
- `Sources/Minto/Services/LLMProviderRegistry.swift`
  - 공급자 descriptor와 기존 교정 provider raw value bridge 추가
  - 공식 API provider와 계정 로그인 provider를 분리
  - legacy 계정 로그인 provider 생성 경로 추가
  - API key 기반 provider 생성 경로 추가
- `Sources/Minto/Services/LLMProviderSelection.swift`
  - 교정/요약/향후 답변 설정에서 공유할 provider 선택 enum 추가
  - 공식 API provider와 계정 로그인 provider를 동일한 선택 타입으로 표현
- `Sources/Minto/Services/LLMSummarySettingsService.swift`
  - 회의록 정리 on/off와 요약 provider 선택값을 교정 provider와 별도로 저장
  - 기존 교정 provider를 요약 provider로 한 번만 복사하는 migration 제공
- `Sources/Minto/Services/KeychainService.swift`
  - 기존 OAuth service namespace 유지
  - 공식 LLM API key 전용 Keychain service namespace 추가
  - save/delete 결과를 반환해 상위 계층이 Keychain 실패를 숨기지 않도록 변경
- `Sources/Minto/Services/LLMAPIKeyStore.swift`
  - GPT/Gemini/Claude/OpenRouter API key 저장·조회·삭제 담당
  - provider별 account key를 분리하고 메모리 캐시로 반복 Keychain 조회를 방지
  - Keychain 저장/삭제 성공 후에만 cache를 갱신해 UI가 실패 상태를 저장됨/삭제됨으로 오인하지 않도록 변경
  - API key 저장/삭제 성공 시 notification을 발행해 검색 답변 readiness가 stale 상태로 남지 않도록 변경
- `Sources/Minto/Services/LLMAPIKeyTextProvider.swift`
  - OpenAI Responses API, Gemini generateContent, Anthropic Messages API, OpenRouter Chat Completions 호출 adapter 추가
  - provider별 live model list 조회와 bundled fallback 모델 카탈로그 제공
  - HTTP 401/403/404/429 등 provider 오류를 공통 `LLMProviderError`로 변환
  - transport/timeout/cancellation 오류도 공통 네트워크 오류로 정규화
  - live model list 실패 경고를 인증/한도/네트워크/응답 오류별로 구분
- `Sources/Minto/Services/LegacyAccountLLMTextProvider.swift`
  - Codex/Gemini/Copilot 계정 로그인 방식의 기존 교정 API를 `LLMTextGenerationProvider`로 adapter화
  - bundled fallback 모델 카탈로그 제공
  - 기존 OAuth 오류를 `LLMProviderError`로 변환
  - legacy OAuth service 접근 시점에만 `@MainActor`로 hop
- `Sources/Minto/Services/LLMCorrectionService.swift`
  - 기존 "OpenAI Codex" 표시를 사용자에게 더 명확한 "GPT 계정 로그인"으로 변경
  - legacy provider enum이 registry descriptor를 참조하도록 변경
  - 교정 호출을 `LLMTextGenerationProvider.generateText` 경로로 전환
  - GPT/Gemini/Claude/OpenRouter API provider 선택값 추가
  - stderr에 전사 원문/교정 결과를 직접 남기지 않고 문자 수만 기록하도록 변경
- `Sources/Minto/UI/SettingsView.swift`
  - `전사 자동 교정` 섹션을 `AI 처리` / `AI 연결` 구조로 정리
  - `전사 다듬기`와 `회의록 정리`를 독립 토글로 분리
  - 전사 다듬기 또는 회의록 정리가 켜진 경우에만 AI 연결 설정 표시
  - 전사 자동 교정 공급자에 공식 API provider 선택지를 추가
  - API key 입력/삭제 UI와 provider별 기본 모델 선택 UI 추가
  - API key 저장 후 live model catalog를 조회하고, 기본 추천 모델/직접 입력/모델 확인 링크 fallback 제공
  - 클라우드 API 전송 안내 문구 추가
  - 로컬 LLM 설정에 context window stepper 추가
- `Sources/MintoApp/MintoApp.swift`
  - 임시 비동기 migration 제거
- `Sources/Minto/App/AppDelegate.swift`
  - 앱 시작 시 기존 교정 provider를 요약 provider로 main actor에서 동기 migration
- `Sources/Minto/Services/SummaryService.swift`
  - 증분/최종 요약 호출을 `LLMTextGenerationProvider.generateText` 경로로 전환
  - `.incrementalSummary`, `.finalSummary` use case를 명시
  - 교정 provider 대신 `LLMSummarySettingsService`의 요약 provider를 사용
- `Sources/Minto/ViewModels/TranscriptionViewModel.swift`
  - 요약 생성 dependency를 주입 가능하게 분리
  - 교정 off/실패 시 원문 batch로 증분 요약을 호출
  - 교정 성공 시 교정본으로 증분 요약을 호출
- `Tests/MintoTests/LLMProviderTests.swift`
  - 공급자 표시명, 로컬/클라우드 구분, 오류 메시지, legacy bridge, 텍스트/임베딩 계약 분리 테스트 추가
  - legacy 계정 provider 생성과 교정 서비스 선택값 adapter 연결 테스트 추가
  - singleton 상태 변경 테스트가 병렬 실행에서 섞이지 않도록 suite 직렬화
  - API key 미설정 fallback catalog, OpenAI Responses 요청 body, HTTP status 매핑, 모델 목록 인증 실패 경고, transport 오류 매핑, Keychain namespace 분리, 저장/삭제 실패 cache 보호 테스트 추가
- `Tests/MintoTests/SummaryServiceTests.swift`
  - 요약 provider migration 1회성 검증 추가
  - 교정 off + 요약 on 독립 설정 검증 추가
- `Tests/MintoTests/TranscriptionViewModelStopTests.swift`
  - 교정이 꺼져 있어도 원문 batch로 진행 중 요약을 갱신하는 실제 drain 경로 테스트 추가
- `Sources/Minto/Services/MeetingSearchIndex.swift`
  - 저장 회의를 검색 가능한 chunk로 분리하는 순수 검색 계층 추가
  - chunk에 `meetingID`, `kind`, `time`, `sourcePath`, `checksum`, `chunkingVersion`을 포함해 향후 sidecar index/embedding cache와 연결 가능한 형태로 설계
  - 전사 chunk source path는 segment UUID가 아니라 전사 순서를 사용해 동일 내용 재생성 시 chunk id가 흔들리지 않도록 변경
  - 제목, 주제, 요약, 섹션, 결정사항, 할 일, 미해결 질문, 전사를 같은 검색 결과 타입으로 반환
  - 1차 검색은 exact phrase, term coverage, chunk kind weight를 조합한 결정론적 ranking으로 구현
  - 동점 정렬에 chunk kind 우선순위와 chunk id fallback을 추가해 대표 검색 결과가 흔들리지 않도록 보강
- `Sources/Minto/UI/MeetingLibraryView.swift`
  - UI 내부 inline 검색 조건을 `MeetingSearchIndex` 호출로 전환
  - 검색 결과의 badge/preview를 chunk metadata에서 가져오도록 변경
- `Tests/MintoTests/MeetingSearchIndexTests.swift`
  - chunk 생성, chunk id/checksum 안정성, 전사 UUID 비의존성, 빈 검색어 처리, 세부 chunk 검색, `db 스키마 형상 관리` 질의 회의 매칭, 제목 우선순위, 악센트 folding 테스트 추가
- `Sources/Minto/Services/MeetingSearchIndexStore.swift`
  - 기존 회의 JSON schema를 바꾸지 않고 `search-index.v1.mintoindex` sidecar 파일로 검색 index snapshot 저장
  - snapshot에 `schemaVersion`, `chunkingVersion`, `generatedAt`, `chunks`를 담아 향후 embedding cache invalidation 기준을 명시
  - incompatible/corrupt index와 chunk 내부 version mismatch는 fail-soft로 nil 반환하고 MeetingStore reload에서 재생성
- `Sources/Minto/Services/MeetingStore.swift`
  - save/delete/reload 후 현재 회의 목록 기준으로 sidecar index 재생성
  - 회의 저장 자체와 검색 index 저장 실패를 분리해 index 저장 실패가 회의 저장 실패로 번지지 않도록 유지
  - `MeetingStore`가 `@MainActor`라 save/delete/reload에서 sidecar write가 같은 executor에서 직렬화됨
- `Tests/MintoTests/MeetingStoreTests.swift`
  - 중복 저장 시 index chunk 중복 없음, 삭제 시 chunk 제거, 손상/version mismatch/missing sidecar reload 재생성 테스트 추가
- `Sources/Minto/Services/LocalHashEmbeddingProvider.swift`
  - 네트워크 없이 회의 chunk를 vector화하는 로컬 deterministic embedding provider 추가
  - `LLMEmbeddingProvider` 계약을 실제 구현으로 검증해 향후 로컬 모델/API embedding provider 교체 지점 마련
  - 의미 유사도 모델이 아닌 `lexicalHash` fallback으로 명시해 UI/랭킹에서 semantic embedding과 구분 가능하게 함
- `Sources/Minto/Services/MeetingSearchEmbeddingIndex.swift`
  - chunkID와 embedding vector를 연결하는 `MeetingSearchEmbeddingRecord`/`MeetingSearchEmbeddingIndex` 추가
  - `MeetingSearchEmbeddingBuilder`가 `MeetingSearchIndex`의 chunk를 provider로 embedding하도록 구성
  - cosine similarity helper를 추가해 hybrid ranking 단계에서 재사용 가능하게 준비
  - provider/model/kind/dimension consistency 검증 경로 추가
- `Sources/Minto/Services/LLMProviderRegistry.swift`
  - `.local`에 대해 embedding provider를 반환하는 registry 경로 추가
  - 아직 로컬 텍스트 LLM adapter가 없으므로 `.local`은 구현된 `.embedding` capability만 노출하도록 정리
- `Tests/MintoTests/MeetingSearchEmbeddingIndexTests.swift`
  - 로컬 embedding 결정론성, registry 연결, chunk별 vector 생성, cosine similarity, 빈 입력 zero vector, dimension mismatch 테스트 추가
- `Sources/Minto/Services/ConfluenceService.swift`
  - Confluence Cloud REST v2 페이지 생성 경로 추가
  - 사용자가 입력한 공간 키를 v2 space id로 해석한 뒤 `POST /wiki/api/v2/pages`로 publish
  - Markdown 회의록을 Confluence storage HTML로 변환
  - publish 대상 URL을 `https://*.atlassian.net`로 제한해 token과 회의록이 임의 호스트로 전송되지 않도록 차단
  - 공간 키는 응답 key가 정확히 일치할 때만 사용하고, 불일치 시 fail-closed
  - 401/403/413/429 오류를 사용자가 이해할 수 있는 메시지로 분리
- `Sources/Minto/UI/MeetingLibraryView.swift`
  - 상세 화면의 내보내기를 선택지 흐름으로 변경
  - Markdown 저장, 전체 복사, Confluence 내보내기 선택지를 제공
  - Confluence 미연결 시 설정 창으로 바로 이동하는 액션 제공
  - Confluence 내보내기 sheet에서 페이지 제목, 공간 키, 선택 부모 페이지 ID를 확인 후 publish
- `Sources/Minto/UI/SettingsView.swift`
  - Confluence 연결 안내를 검색/문맥 조회/내보내기 용도로 명확히 정리
  - Atlassian API token 발급 링크와 페이지 작성 권한 안내 추가
  - token은 이 Mac의 비밀 저장소에 저장되고 기본 저장소는 Keychain이라는 안내 추가
- `Tests/MintoTests/RelatedInfoTests.swift`
  - Confluence v2 publish payload, storage HTML 변환, 공간 key 해석, publish URL 조립, Cloud URL allowlist 테스트 추가
- `Sources/Minto/Models/GlossaryEntry.swift`
  - 전역 기본 용어집 항목 모델 추가
  - canonical, aliases, description, category, tags, enabled, updatedAt 필드 정의
- `Sources/Minto/Services/GlossaryStore.swift`
  - 전역 용어집을 `Application Support/Minto/glossary.json`에 별도 저장
  - `GlossarySnapshot(schemaVersion, entries)` envelope로 저장해 향후 migration 경로 확보
  - 기존 raw `[GlossaryEntry]` 배열 파일은 읽은 뒤 snapshot으로 재저장하는 legacy migration 제공
  - 후보 추천은 회의 주제와 관련도 점수가 1 이상인 enabled 용어만 반환
  - 저장 성공 후에만 UI 상태를 publish해 파일 저장 실패와 화면 상태 불일치 방지
  - `GlossaryContextResolver`로 선택 용어와 회의별 입력을 병합하고 최종 병합 결과 기준 max entries/characters 제한
  - `=`, `—` 앞 canonical 기준으로 중복 용어를 제거해 같은 용어 반복 주입 방지
- `Sources/Minto/UI/MeetingSetupView.swift`
  - 회의별 용어 입력을 유지하면서 주제와 관련된 기본 용어 후보를 선택할 수 있게 변경
  - `추천 선택`은 관련 후보만 선택하고, 선택된 기본 용어와 이번 회의 용어를 resolver로 병합해 기존 `MeetingContext.glossary`로 전달
  - 주제 변경으로 추천 목록에서 사라진 선택 용어도 `선택된 용어`로 노출해 사용자가 해제할 수 있게 변경
- `Sources/Minto/UI/SettingsView.swift`
  - 설정에 용어집 섹션 추가
  - 정확한 표기, 오인식 표현, 설명, 태그를 입력해 기본 용어를 추가
  - 용어 추가 폼은 기본 접힘 상태로 두고, 각 용어는 “회의 시작 때 추천에 포함”으로 활성 여부를 표현
- `Tests/MintoTests/GlossaryStoreTests.swift`
  - 저장/재로드, snapshot envelope, legacy migration, 저장 실패 rollback, canonical 중복 교체, 관련 후보 추천, 0점 후보 제외, resolver 병합/중복 제거/제한 테스트 추가
- `Sources/Minto/Services/AnswerPrompt.swift`
  - 저장된 회의 근거만 사용해 답하도록 하는 검색 답변 prompt를 순수 타입으로 분리
- `Sources/Minto/Services/MeetingSearchAnswerSettingsService.swift`
  - 검색 답변 on/off와 답변 provider 선택을 전사 다듬기/회의록 정리 설정과 별도 저장
- `Sources/Minto/Services/MeetingSearchAnswerService.swift`
  - `MeetingSearchAnswerUseCase` 추가
  - 검색 query와 `MeetingSearchIndex` 상위 chunk를 근거 block으로 만들고 `LLMUseCase.answer`로 provider 호출
  - 빈 검색어, 검색 결과 없음, provider 미설정, answer 미지원, 빈 응답을 호출 전후에서 방어
  - context는 max chunks/max characters로 제한하고 citation에 `meetingID`, `meetingTitle`, `kind`, `sourcePath`, `time`, `preview` 포함
- `Sources/Minto/Services/MeetingSearchAnswerController.swift`
  - 검색 답변 UI 상태, provider readiness, generation task cancellation 담당
  - API key/로그인 미설정 provider는 버튼 활성화 전 차단
  - 검색어/회의/설정 변경 시 진행 중 generation/readiness task 취소
  - API key 저장/삭제 notification을 받아 provider readiness 재계산
  - 검색어/회의 목록 변경 시에는 provider readiness를 유지하고 답변 generation만 취소하도록 reset 범위 분리
- `Sources/Minto/UI/MeetingLibraryView.swift`
  - 검색 중 `AI 답변` 카드를 추가
  - 설정된 검색 답변 provider가 준비된 경우에만 답변 생성 버튼 표시
  - 답변과 citation을 복사/선택 가능하게 표시하고, citation 클릭 시 해당 회의와 요약/전사 탭으로 이동
  - citation 전체, 시간, 미리보기를 표시하고 기본 복사는 답변과 근거 목록을 함께 복사
  - 긴 답변은 검색 목록을 밀어내지 않도록 프리뷰로 시작하고 필요할 때 펼치기
- `Sources/Minto/UI/SettingsView.swift`
  - `AI 처리`에 `검색 답변` 토글 추가
  - 검색 답변 provider를 전사 다듬기/회의록 정리 provider와 별도 row로 선택
  - 검색 답변 사용 시 상위 회의 근거가 선택한 AI 서비스로 전송된다는 안내 추가
  - 검색 답변 provider가 일반 AI provider와 다르면 해당 provider의 모델/API key 연결 UI를 별도 표시
  - 서로 다른 API provider를 동시에 설정할 때 입력값이 섞이지 않도록 provider별 API key 입력 state 분리
- `Tests/MintoTests/MeetingSearchAnswerServiceTests.swift`
  - 검색 답변 use-case, prompt, 설정 분리, provider readiness gate, context cap, citation metadata, 같은 검색어 재생성 stale update 방지 테스트 추가
- `Tests/MintoTests/LLMProviderTests.swift`
  - local provider가 구현된 embedding capability만 노출하는지 테스트 추가
  - API provider cancellation이 네트워크 오류로 바뀌지 않는지 테스트 추가
  - 로컬 LLM context window 저장값/환경변수 우선순위, 안전 범위 제한, Ollama `num_ctx` 요청 body, OpenAI-compatible 미적용 테스트 추가
- `scripts/run_local_llm_benchmarks.py`
  - `--num-ctx` 옵션과 `MINTO_LOCAL_LLM_CONTEXT_WINDOW` fallback 추가
  - Ollama request body, manifest, metrics, summary에 context window 기록
  - dry-run에서 `request_bodies.json` preview 생성
- `docs/benchmark/local-llm-benchmark-runner.md`
  - `--num-ctx 4096` 예시와 Ollama 전용 적용 범위 문서화
- `docs/benchmark/local-llm/README.md`
  - 후보 판정 기준에 context window 통제와 manifest 기록 조건 추가
- `docs/benchmark/local-llm/2026-06-09-deepseek-r1-8b/notes.md`
  - 기존 timeout이 context `131072` 상태였음을 명시하고 `--num-ctx 4096` 재측정 명령 추가

## 검증 계획

- `git diff --check` 통과
- `swift test --disable-sandbox --scratch-path /tmp/minto2-llm-provider-test --filter LLMProviderTests` 통과
- `swift build --disable-sandbox --scratch-path /tmp/minto2-llm-provider-build` 통과
- `swift test --disable-sandbox --scratch-path /tmp/minto2-llm-provider-boundary-test --filter LLMProviderTests` 통과
- `swift build --disable-sandbox --scratch-path /tmp/minto2-llm-provider-boundary-build` 통과
- `swift test --disable-sandbox --scratch-path /tmp/minto2-llm-adapter-test --filter LLMProviderTests` 통과
- `swift test --disable-sandbox --scratch-path /tmp/minto2-llm-adapter-test --filter SummaryServiceTests` 통과
- `swift build --disable-sandbox --scratch-path /tmp/minto2-llm-adapter-build` 통과
- `swift test --disable-sandbox --scratch-path /tmp/minto2-api-provider-test --filter LLMProviderTests` 통과: 15 tests
- `swift test --disable-sandbox --scratch-path /tmp/minto2-api-provider-summary-test --filter SummaryServiceTests` 통과: 10 tests
- `swift build --disable-sandbox --scratch-path /tmp/minto2-api-provider-build` 통과
- `swift test --disable-sandbox --scratch-path /tmp/minto2-summary-provider-test --filter SummaryServiceTests` 통과: 12 tests
- `swift test --disable-sandbox --scratch-path /tmp/minto2-summary-llm-provider-test --filter LLMProviderTests` 통과: 15 tests
- `swift build --disable-sandbox --scratch-path /tmp/minto2-summary-provider-build` 통과
- `swift test --disable-sandbox --scratch-path /tmp/minto2-summary-viewmodel-test --filter TranscriptionViewModelStopTests` 통과: 8 tests
- `swift test --disable-sandbox --scratch-path /tmp/minto2-search-index-test --filter MeetingSearchIndexTests` 통과: 8 tests
- `swift build --disable-sandbox --scratch-path /tmp/minto2-search-index-build` 통과
- `swift test --disable-sandbox --scratch-path /tmp/minto2-search-store-test --filter MeetingStoreTests` 통과: 10 tests
- `swift test --disable-sandbox --scratch-path /tmp/minto2-embedding-index-test --filter MeetingSearchEmbeddingIndexTests` 통과: 6 tests
- `swift test --disable-sandbox --scratch-path /tmp/minto2-confluence-export-test --filter Confluence` 통과: 21 tests
- `swift build --disable-sandbox --scratch-path /tmp/minto2-confluence-export-build` 통과
- Confluence 내보내기 코드리뷰:
  - Architecture/UX 리뷰 상태: `WATCH`
  - 조치: 미연결 시 설정 열기 액션 추가, 공간 키 불일치 fail-closed, HTTP 오류 메시지 분리
  - 남은 watch: export 대상이 늘어나면 `ConfluenceExportService` 또는 export use case 분리 필요
- Confluence 내보내기 보안 코드리뷰:
  - 초기 추천: `REQUEST CHANGES`
  - 조치: publish/search URL을 `https://*.atlassian.net`로 제한, 공간 키 정확 매칭, 사용자 오류 메시지 분리, 테스트 추가
  - 조치 후 검증: Confluence 21 tests + build 통과
- `swift test --disable-sandbox --scratch-path /tmp/minto2-glossary-store-test --filter GlossaryStore` 통과: 10 tests
- `swift build --disable-sandbox --scratch-path /tmp/minto2-glossary-build` 통과
- 용어집 아키텍처/UX 리뷰:
  - 상태: `WATCH`
  - blocking: 관련도 0점 용어가 추천 선택으로 프롬프트에 들어갈 수 있음
  - 조치: `candidates`를 score > 0으로 제한, `GlossaryContextResolver` 추가, prompt max entries/characters 제한, snapshot envelope 추가, 설정 UI 접힘 처리
- 용어집 코드리뷰:
  - 초기 추천: `REQUEST CHANGES`
  - blocking: 주제 변경 후 숨은 선택 용어가 프롬프트에 남음, 최종 병합 기준 제한 미흡, 저장 실패 시 UI 상태 불일치
  - 조치: 선택된 비추천 용어 노출/해제 UI 추가, 최종 병합 기준 max entries/canonical dedupe 적용, 저장 성공 후 publish, legacy/save failure/final cap 테스트 추가
  - 재리뷰: blocker/high/medium 없음, `COMMENT`
- `swift test --disable-sandbox --scratch-path /tmp/minto2-search-answer-test --filter MeetingSearchAnswerService` 통과: 12 tests
- `swift test --disable-sandbox --scratch-path /tmp/minto2-llm-provider-test --filter LLMProviderTests` 통과: 19 tests
- `swift build --disable-sandbox --scratch-path /tmp/minto2-search-answer-build` 통과
- `git diff --check` 통과
- `python3 -m py_compile scripts/run_local_llm_benchmarks.py` 통과
- `python3 scripts/run_local_llm_benchmarks.py --dry-run --model deepseek-r1:8b --cases correction --num-ctx 4096 --output-root /tmp/minto2-local-llm-context-dryrun` 통과
  - `run_manifest.json`에 `num_ctx=4096` 기록
  - `request_bodies.json`의 Ollama `options.num_ctx=4096` 확인
- `python3 scripts/run_local_llm_benchmarks.py --mock --model mock-model --repeat 1 --num-ctx 4096 --output-root /tmp/minto2-local-llm-context-mock` 통과: 3 mock cases
- `swift test --disable-sandbox --scratch-path /tmp/minto2-local-llm-context-test --filter LLMProviderTests` 통과: 28 tests
- `swift build --disable-sandbox --scratch-path /tmp/minto2-local-llm-context-build` 통과
- 검색 답변 아키텍처 리뷰:
  - 초기 추천: `REQUEST CHANGES`
  - blocking: local capability 불일치, UI가 provider orchestration 소유, citation metadata 부족, 검색 답변 provider gate 미분리, prompt private string
  - 1차 조치: local은 embedding만 노출, `AnswerPrompt` 분리, answer 전용 settings/use-case/controller 추가, citation `sourcePath/time` 확장, raw prompt/transcript/token 로그 없음 확인
  - 2차 리뷰 high: 미설정 provider에서 버튼 활성화, 진행 중 클라우드 요청 취소 불가
  - 2차 조치: provider readiness async check, generation/readiness task cancellation, cancellation error 미노출, 검색 답변 provider 별도 row, citation 클릭 이동 추가
  - 3차 리뷰 medium: API key 저장/삭제 후 readiness 자동 갱신 신호 부족
  - 3차 조치: `LLMAPIKeyStore` 변경 notification 추가, 컨트롤러 notification observer와 테스트 추가
  - 4차 리뷰 medium: 검색어/회의 목록 변경 reset 중 readiness가 false로 남을 수 있음
  - 4차 조치: `reset(clearReadiness:)`로 답변 상태 reset과 provider readiness reset을 분리, 검색 변경 기본 reset은 readiness 유지
- 검색 답변 코드리뷰:
  - 초기 추천: `REQUEST CHANGES`
  - high: 답변 prompt에는 최대 8개 citation이 들어가지만 UI는 3개만 보여줘 `[4]` 이후 근거 검증이 불가능
  - medium: citation 클릭/표시가 실제 근거 확인에 부족, prompt injection 방어 문구와 delimiter 부족, 검색 결과 없음보다 provider 설정 확인이 먼저 실행됨
  - low: controller readiness 테스트가 고정 `Task.sleep(20ms)`에 의존
  - 조치: citation 전체 표시와 preview/time 노출, 근거 내부 명령 무시 규칙과 delimiter 추가, 검색 결과 없음 gate를 provider readiness보다 앞에 배치, polling helper 기반 readiness 테스트로 변경
- 검색 답변 재리뷰:
  - architecture high: 검색 답변 provider와 `AI 연결`의 active provider가 다를 때 잘못된 키/로그인 UI가 보일 수 있음
  - 조치: 일반 AI 연결과 검색 답변 연결을 분리하고, 검색 답변 provider가 다르면 전용 모델/API key 상태/저장 UI 표시
  - code high: 같은 검색어로 재생성할 때 취소된 이전 task가 새 요청 UI 상태를 덮을 수 있음
  - 조치: `generationToken`으로 최신 요청만 UI 반영, `CancellationError` rethrow, provider cancellation 변환 제거, 회귀 테스트 추가
  - 재리뷰 block: 회귀 테스트가 Task 스케줄링에 따라 continuation 순서를 잘못 가정할 수 있음
  - 조치: 첫 요청이 provider에 진입한 것을 확인한 뒤 두 번째 요청을 시작하도록 테스트 안정화
  - UX medium: 답변 카드가 검색 결과를 밀어낼 수 있고, 답변 복사에서 근거 목록이 빠짐
  - 조치: 답변 프리뷰/펼치기 적용, 기본 복사를 답변+근거로 변경
  - 재리뷰 medium: 일반 AI와 검색 답변이 서로 다른 API provider일 때 단일 `apiKeyInput` state 공유로 오입력 가능
  - 조치: `apiKeyInputs`를 provider별 dictionary로 분리
- 문서 경로와 링크 확인
- 기존 경고:
  - `MicrophoneSource.swift`의 `nonisolated(unsafe)` 관련 경고
  - 일부 기존 테스트 파일의 미사용 변수 경고

## 다음 단계

1. 음성·영상 파일 import 후 사후 회의록 생성
2. 화상회의용 시스템 사운드 입력 설계와 구현
3. 로컬 텍스트 LLM adapter 후보 검증과 적용

## 음성/영상 파일 import 슬라이스

상태: 구현/검증 완료

### 설계 결정

- 파일 import는 live recording 상태를 가진 `TranscriptionViewModel`에 얹지 않는다.
- 별도 `MeetingFileImportUseCase`가 파일 분석, chunk별 전사/교정, 최종 요약, `MeetingRecord` 저장을 조합한다.
- 파일 변환은 infrastructure adapter인 `FileAudioExtractor`가 담당하며, 전체 오디오를 한 번에 `[Float]`로 반환하지 않고 chunk callback으로 전달한다.
- 저장 schema는 변경하지 않고 기존 `MeetingRecord`와 `MeetingStore.save`를 재사용한다.
- 저장이 성공하면 기존 `MeetingStore`의 sidecar search index 재생성 경로를 그대로 탄다.
- 1차 구현은 VAD 재사용보다 예측 가능한 고정 window 전사를 우선한다. 파일용 VAD 최적화와 `AVAudioConverter` 기반 고품질 resampling은 실제 fixture 품질/속도 측정 후 별도 작업으로 둔다.
- 코드리뷰 결과 긴 파일 전체 메모리 적재가 BLOCKER로 확인되어 streaming callback 구조로 변경했다.
- 파일 import 교정은 live `MeetingContext`를 읽지 않고 `LLMCorrectionContext`를 명시적으로 주입한다.
- 재리뷰에서 `Task.detached` reader 취소 전파가 HIGH로 확인되어 부모 import task cancellation을 detached reader task로 전달하도록 수정했다.
- extractor callback은 source order로 순차 await하는 계약으로 고정했다.
- ADR: `docs/adr/0002-file-import-streaming-architecture.md`
- Pencil 목업 `Resources/designs/2026-06-09-file-import-flow.pen`과 export 이미지 `Resources/designs/2026-06-09-file-import-flow.png`를 생성했다.

### UI 기준

- `새 회의`는 primary action으로 유지한다.
- `파일 가져오기`는 보조 action으로 배치한다.
- 처리 상태는 파일 분석, 전사, 요약, 저장 단계를 구분해 보여준다.
- 실패 시 사용자에게 파일 형식/전사/요약/저장 중 어느 단계에서 실패했는지 보여준다.

### 검증

- `MeetingFileImportUseCase` 단위 테스트: chunking, timestamp, title fallback, summary fallback, 저장 성공
- 취소 테스트: 추출 전 취소와 chunk 처리 중 취소 모두 저장하지 않음
- 파일 변환 테스트: 지원하지 않는 파일 형식 오류
- 실제 작은 wav fixture를 생성해 `FileAudioExtractor`의 AVFoundation 경로 검증
- 실제 `FileAudioExtractor` 부모 task 취소 전파 테스트 추가
- `swift test --disable-sandbox --scratch-path /tmp/minto2-file-import-test --filter MeetingFileImport` 통과: 9 tests
- `swift build --disable-sandbox --scratch-path /tmp/minto2-file-import-build` 통과
- `git diff --check` 통과
- 재리뷰: BLOCKER/HIGH/MEDIUM/LOW 없음

## Keychain 권한 요청 최소화 슬라이스

상태: 구현/검증 중

### 변경 요약

- UI 상태 표시와 실제 비밀값 사용을 분리했다.
- `KeychainService.exists(provider:service:)`를 추가해 상태 확인에서는 `kSecReturnData` 없이 item 존재 여부만 조회한다.
- `LLMAPIKeyStore.hasAPIKey`는 비밀값을 읽지 않고 존재 여부만 확인한다. 실제 API 호출에서 `apiKey(for:)`를 호출할 때만 원문 key를 로드한다.
- Confluence는 설정/목록 상태 표시 시 token 원문을 읽지 않고, 검색/내보내기 실행 시에만 lazy load한다.
- Notion MCP 연결 상태는 `KeychainTokenStorage.hasToken()`으로 확인해 앱/설정 진입 시 token 원문 decode를 피한다.
- GPT/Gemini/Copilot 계정 로그인 상태는 Keychain item 존재 여부로 표시하고, 실제 교정/요약 호출 때 credentials를 로드한다.
- Gemini/Copilot email은 credentials가 이미 캐시된 경우에만 표시해 email 표시 때문에 Keychain prompt가 뜨는 일을 피한다.

### 검증

- `swift test --disable-sandbox --scratch-path /tmp/minto2-keychain-provider-test --filter LLMProviderTests` 통과: 20 tests
- `swift test --disable-sandbox --scratch-path /tmp/minto2-keychain-related-test --filter RelatedInfoTests` 통과: 34 tests
- `swift build --disable-sandbox --scratch-path /tmp/minto2-keychain-build` 통과
- Keychain 보안/아키텍처 리뷰:
  - 상태: `COMMENT`, `WATCH`
  - BLOCK/HIGH 없음
  - MEDIUM: 존재 여부 기반 상태 확인은 저장값 유효성을 검증하지 않음
  - 조치: LLM API key는 실제 load 후 빈/invalid 값이면 `knownProviderStatus`를 false로 내리는 경로를 테스트로 고정
  - 후속: OAuth/Confluence의 corrupt token은 실제 호출 실패 시 “다시 연결 필요” 상태를 남기는 UX로 별도 처리
- 기존 경고:
  - `MicrophoneSource.swift`의 `nonisolated(unsafe)` 관련 경고
  - `MicrophoneSourceTests`의 미사용 `receivedError` 경고
  - `MeetingCorpusTests`의 미사용 `index` 경고

## 시스템 사운드 입력 foundation 슬라이스

상태: 구현/검증 완료

### 변경 요약

- `AudioInputMode`를 추가해 `마이크`, `시스템`, `마이크+시스템` 입력 모드를 표현했다.
- `AudioSourceFactory`를 추가해 녹음 시작 전 선택한 입력 모드에 맞는 `AudioSourceProtocol` 구현체를 만든다.
- `SystemAudioSource`를 추가해 macOS ScreenCaptureKit `SCStream`의 system audio output을 기존 VAD pipeline으로 전달한다.
- ScreenCaptureKit configuration은 system audio capture를 켜고, 현재 앱 프로세스 audio는 제외하며, 16kHz mono 입력으로 맞춘다.
- `SystemAudioSource`는 sample handler queue에서 audio callback을 전달하고, `TranscriptionViewModel`이 MainActor로 hop해 기존 state 경계를 유지한다.
- `마이크+시스템`은 후속 mixed audio 슬라이스에서 `MixedAudioSource`로 열었다. Echo cancellation과 장시간 drift는 후속 측정 대상으로 둔다.
- `SystemAudioSource`는 stop 이후 들어오는 ScreenCaptureKit sample/error callback을 capture state gate로 무시한다.
- 회의 시작 시트에 입력 모드 segmented control을 추가하고, 선택값을 `AppDelegate`에서 `TranscriptionViewModel.startNewRecordingSession(inputMode:)`로 전달한다.
- `NSAudioCaptureUsageDescription`을 Info.plist에 추가했다.
- ADR: `docs/adr/0003-system-audio-input-foundation.md`

### 검증

- `swift build --disable-sandbox --scratch-path /tmp/minto2-system-audio-build` 통과
- `swift test --disable-sandbox --scratch-path /tmp/minto2-system-audio-test --filter 'AudioInputMode|TranscriptionViewModelStopTests'` 통과: 13 tests
- `swift test --disable-sandbox --scratch-path /tmp/minto2-mixed-audio-test --filter AudioInputMode` 통과: 13 tests
- `swift test --disable-sandbox --scratch-path /tmp/minto2-mixed-audio-test --filter 'AudioInputMode|TranscriptionViewModelStopTests'` 통과: 21 tests
- `swift build --disable-sandbox --scratch-path /tmp/minto2-mixed-audio-build` 통과
- `git diff --check` 통과
- 아키텍처 재리뷰: BLOCKER/HIGH 없음. system audio callback main queue dispatch 제거와 `마이크+시스템` fan-in 차단 확인

### 남은 항목

- 사전 readiness check는 후속 `c295d17`에서 구현 완료
- 실제 화상회의 앱 출력으로 system audio와 mixed level meter 동작 수동 QA
- `마이크+시스템` mode의 echo/mix 품질, 장시간 drift 측정

## 병렬 릴리즈 lane 통합

상태: 구현/검증 완료

### 기준 브랜치와 worktree

- 릴리즈 기준 브랜치: `release/llm-search-export-2026-06-09`
- 기준 커밋: `4bcff6d feat: add system audio input foundation`
- 통합 브랜치: `integration/llm-search-export-2026-06-09`
- 통합 보고서: `docs/reports/2026-06-09-parallel-release-execution.md`

### 병렬 lane 결과

- `feature/system-audio-readiness`
  - 커밋: `c295d17 feat: show system audio readiness before recording`
  - 녹음 전 system audio readiness, 권한 안내, 시작 버튼 비활성화 조건, 관련 테스트 추가
- `feature/local-llm-adapter`
  - 커밋: `7972535 feat: add local HTTP LLM provider`
  - Ollama `/api/generate`와 OpenAI-compatible `/v1/chat/completions` local runtime adapter 추가
  - provider/response/error mapping 테스트 추가
- `feature/keychain-reconnect-ux`
  - 커밋: `6a96d21 fix: mark integrations needing reconnect`
  - Confluence/Notion token load/decode/API 인증 실패 후 `다시 연결 필요` 상태 표시
  - Settings 렌더링 경로에서는 token 원문을 읽지 않는 기존 목표 유지

### 통합 검증

- 기준선 검증:
  - `git diff --check` 통과
  - `swift build --disable-sandbox --scratch-path /tmp/minto2-release-baseline-build` 통과
  - `swift test --disable-sandbox --scratch-path /tmp/minto2-release-baseline-test --filter 'LLMProviderTests|MeetingSearchAnswerService|AudioInputMode|RelatedInfoTests|MeetingFileImportUseCaseTests'` 통과: 81 tests
- 병합 후 검증:
  - `git diff --check` 통과
  - `swift build --disable-sandbox --scratch-path /tmp/minto2-integration-build` 통과
  - `swift test --disable-sandbox --scratch-path /tmp/minto2-integration-smoke-test --filter 'AudioInputMode|LLMProviderTests|MeetingSearchAnswerService|RelatedInfoTests'` 통과: 86 tests

## 로컬 LLM 설정 연결 슬라이스

상태: 구현/검증 완료

### 변경 요약

- `LLMProviderSelection.local`을 추가해 로컬 LLM을 전사 다듬기, 회의록 정리, 검색 답변 provider로 선택할 수 있게 했다.
- `LocalLLMProviderConfiguration`은 UserDefaults 저장값을 먼저 읽고, 저장값이 없으면 기존 `MINTO_LOCAL_LLM_*` 환경변수로 fallback한다.
- Settings의 AI 연결 화면에 로컬 runtime 설정을 추가했다.
  - endpoint URL
  - model ID
  - Ollama generate / OpenAI-compatible chat mode
  - response timeout
- local provider에는 API key/login UI를 표시하지 않는다.
- endpoint URL은 `http` 또는 `https` scheme과 host가 있어야 유효한 설정으로 본다.

### 검증

- `git diff --check` 통과
- `swift test --disable-sandbox --scratch-path /tmp/minto2-local-llm-settings-test --filter LLMProviderTests` 통과: 27 tests
- `swift test --disable-sandbox --scratch-path /tmp/minto2-local-llm-settings-test --filter 'LLMProviderTests|MeetingSearchAnswerService|SummaryServiceTests'` 통과: 51 tests
- `swift build --disable-sandbox --scratch-path /tmp/minto2-local-llm-settings-build` 통과

### 남은 항목

- 실제 Ollama 또는 llama.cpp/OpenAI-compatible endpoint로 교정, 요약, 검색 답변 호출 수동 QA
- 로컬 모델별 한국어 회의 교정 품질, 요약 구조화 성공률, 검색 답변 근거 충실도, latency, RAM benchmark

## 마이크+시스템 입력 연결 슬라이스

상태: 구현/검증 완료

### 변경 요약

- `AudioInputMode.selectableCases`에 `마이크+시스템`을 다시 열어 회의 시작 시트에서 선택할 수 있게 했다.
- `MixedAudioSource`를 추가해 `MicrophoneSource`와 `SystemAudioSource`를 함께 시작/정지한다.
- `DualAudioBufferMixer`는 두 입력의 누적 PCM buffer에서 같은 길이만큼 꺼내 0.5 gain으로 섞고, -1.0...1.0 범위로 clipping한다.
- 한쪽 입력만 계속 들어올 때는 약 0.25초 pending buffer만 남기고 오래된 샘플을 passthrough해 live 입력 지연과 메모리 증가를 제한한다.
- mixed readiness는 system audio와 같은 화면/시스템 오디오 권한과 availability gate를 사용한다.
- level meter는 child source level과 mixed buffer level을 모두 전달해 입력 감지 상태가 끊기지 않게 했다.
- `STTAudioUtilities.normalizedLevel`을 공통 유틸로 올려 system audio와 mixed audio가 같은 level 계산을 쓴다.

### 검증

- `swift test --disable-sandbox --scratch-path /tmp/minto2-mixed-audio-test --filter AudioInputMode` 통과: 13 tests
- `swift test --disable-sandbox --scratch-path /tmp/minto2-mixed-audio-test --filter 'AudioInputMode|TranscriptionViewModelStopTests'` 통과: 21 tests
- `swift build --disable-sandbox --scratch-path /tmp/minto2-mixed-audio-build` 통과

### 남은 항목

- 실제 화상회의 앱에서 `마이크+시스템` 선택 후 양쪽 입력이 모두 전사/VAD pipeline으로 들어오는지 수동 QA
- 스피커 출력이 마이크로 재유입되는 echo 상황과 장시간 녹음 drift 측정

## 로컬 LLM benchmark runner 슬라이스

상태: 구현/검증 완료

### 변경 요약

- `scripts/run_local_llm_benchmarks.py`를 추가했다.
- 앱의 `LocalLLMProvider`와 같은 endpoint 호환 모드를 지원한다.
  - Ollama: `/api/generate`
  - OpenAI-compatible: `/v1/chat/completions`
- benchmark case는 correction, structured summary JSON, grounded search answer 3개로 시작한다.
- 각 run은 latency, output length, expected term recall, summary JSON validity, required field recall을 기록한다.
- `--server-pid`가 있으면 요청 중 model server RSS를 sampling해 RAM 비교 근거를 남긴다.
- `--dry-run`과 `--mock`을 제공해 실제 model server 없이 runner 자체를 검증할 수 있게 했다.
- 실행 문서는 `docs/benchmark/local-llm-benchmark-runner.md`에 추가했다.

### 검증

- `python3 -m py_compile scripts/run_local_llm_benchmarks.py` 통과
- `python3 scripts/run_local_llm_benchmarks.py --dry-run --model mock-model --cases correction --output-root /tmp/minto2-local-llm-bench-dryrun` 통과
- `python3 scripts/run_local_llm_benchmarks.py --mock --model mock-model --repeat 1 --output-root /tmp/minto2-local-llm-bench-mock` 통과: 3 mock cases

### 남은 항목

- 실제 Ollama 또는 OpenAI-compatible endpoint로 후보 모델별 benchmark 실행
- 실측 결과를 `docs/benchmark/local-llm/`에 기록하고 기본값 후보 결정

## 로컬 LLM 실제 benchmark 1차

상태: 실행 완료, 기본 후보 보류

### 변경 요약

- Ollama에 설치된 `deepseek-r1:8b`로 실제 benchmark를 실행했다.
- 결과는 `docs/benchmark/local-llm/2026-06-09-deepseek-r1-8b/`에 기록했다.
- `correction_terms` 첫 case가 120초 timeout으로 실패했다.
- 재현 확인용 16-token 직접 요청도 60초 timeout이었다.
- 현재 환경의 `deepseek-r1:8b`는 Minto 기본 로컬 LLM 후보로 올리지 않는다.

### 검증

- `python3 scripts/run_local_llm_benchmarks.py --compatibility ollama --base-url http://127.0.0.1:11434 --model deepseek-r1:8b --repeat 1 --server-pid 58693 --output-root docs/benchmark/local-llm/2026-06-09-deepseek-r1-8b --fail-fast` 실행: 120초 timeout으로 실패 결과 기록
- 직접 요청 `curl --max-time 60 ... num_predict=16` 실행: 60초 timeout

### 남은 항목

- 더 빠르고 domain-term 보존이 좋은 instruct 모델로 후보 benchmark 재실행

## 로컬 LLM 실제 benchmark 2차: DeepSeek context cap

상태: 실행 완료, timeout 해소, 기본 후보 보류

### 변경 요약

- 같은 `deepseek-r1:8b` 모델을 `--num-ctx 4096` 조건으로 재측정했다.
- 결과는 `docs/benchmark/local-llm/2026-06-09-deepseek-r1-8b-numctx4096/`에 기록했다.
- 이전 `context=131072` 조건의 120초 timeout은 해소됐다.
- `correction_terms`, `summary_json`, `grounded_answer` 세 case 모두 응답했다.
- 다만 correction case의 expected domain term recall이 `0.0`이라 기본 후보 보류 판단을 유지한다.

### 검증

- `python3 scripts/run_local_llm_benchmarks.py --compatibility ollama --base-url http://127.0.0.1:11434 --model deepseek-r1:8b --num-ctx 4096 --repeat 1 --server-pid 58693 --output-root docs/benchmark/local-llm/2026-06-09-deepseek-r1-8b-numctx4096 --fail-fast` 통과
  - success rate: `3/3`
  - mean latency: `29.916s`
  - max latency: `50.723s`
  - correction term recall: `0.0`
  - summary JSON valid rate: `1.0`
  - grounded answer term recall: `1.0`
- `ollama ps` 확인: `deepseek-r1:8b`, context `4096`, model size `5.9 GB`, processor `100% GPU`

### 남은 항목

- correction term recall이 높은 instruct 모델을 같은 runner와 같은 `num_ctx=4096` 조건으로 비교

## SecretStore 개발 모드 슬라이스

상태: 구현/검증 완료

### 변경 요약

- `SecretStore` protocol을 추가하고 기본 구현으로 `KeychainSecretStore`를 연결했다.
- `MINTO_DEV_SECRET_STORE=file`이면 `LocalDevSecretStore`를 선택한다.
- `MINTO_DEV_SECRET_STORE_ROOT`를 추가해 개발 file store root를 `/tmp` 같은 격리 경로로 바꿀 수 있게 했다.
- 개발 file store는 `Application Support/Minto/dev-secrets` 아래에 0700 directory, 0600 file permission으로 저장한다.
- LLM API key, OAuth token, Confluence API token storage가 공통 `SecretStore` backend를 쓰도록 전환했다.
- Codex/Gemini/Copilot OAuth service의 직접 Keychain 호출도 공통 store 경로로 모았다.
- Settings 안내 문구는 `Keychain` 고정 표현 대신 기본 저장소가 Keychain인 `비밀 저장소` 표현으로 정리했다.

### 검증

- `swift test --disable-sandbox --scratch-path /tmp/minto2-secret-store-root-test --filter SecretStore` 통과: 6 tests
- `swift test --disable-sandbox --scratch-path /tmp/minto2-secret-store-root-related-test --filter 'SecretStore|LLMProviderTests|RelatedInfoTests'` 통과: 71 tests
- `swift build --disable-sandbox --scratch-path /tmp/minto2-secret-store-root-build` 통과
- `git diff --check` 통과

### 남은 항목

- 실제 개발 실행에서 `MINTO_DEV_SECRET_STORE=file MINTO_DEV_SECRET_STORE_ROOT=/tmp/minto-dev-secrets`로 API key/token 저장, 재시작 후 load, delete 수동 QA
