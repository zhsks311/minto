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
  - token은 Keychain에만 저장된다는 안내 추가
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
- 문서 경로와 링크 확인
- 기존 경고:
  - `MicrophoneSource.swift`의 `nonisolated(unsafe)` 관련 경고
  - 일부 기존 테스트 파일의 미사용 변수 경고

## 다음 단계

1. 검색 결과 기반 답변 생성 prompt/service 구현
2. 음성·영상 파일 import 후 사후 회의록 생성
3. 개발 중 Keychain 권한 요청 최소화
4. 화상회의용 시스템 사운드 입력 설계와 구현
