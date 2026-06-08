# Minto2 LLM/Search/Export Expansion Plan

작성일: 2026-06-09
상태: 실행 계획
작업 브랜치: `feature/llm-correction-search-export`
작업 워크트리: `/Users/d66hjkxwt9/Idea/private/minto2-llm-correction-search-export`
기준 커밋: `8e49ef9`

## 1. 목표

Minto2를 "회의를 기록하는 앱"에서 "회의를 정리하고 다시 찾고 공유하는 로컬 우선 회의 지식 도구"로 확장한다.

핵심 목표는 다음이다.

- 전사 자동 교정과 회의 요약/구조화를 공급자 독립 구조로 분리한다.
- 로컬 LLM과 공식 API 기반 LLM을 전사 교정/요약에 사용할 수 있게 한다.
- 저장된 회의를 임베딩해 검색 데이터 소스로 활용한다.
- 검색 결과를 필요할 때 LLM이 종합해 답변하도록 만든다.
- 미리 정의한 용어집을 추가·관리하고, 회의별 임시 용어와 함께 교정/요약 맥락으로 활용한다.
- Confluence 연결/내보내기 UX를 사용자가 막히지 않게 개선한다.
- 음성/영상 파일을 넣어 사후 회의록을 만들 수 있게 한다.
- 화상회의를 위해 시스템 사운드 입력을 지원한다.
- 개발 중 Keychain 비밀번호 요청을 줄인다.
- 기능 정의서, 작업 컨벤션, 디자인 원칙을 문서화한다.

## 2. 현재 코드 기준 근거

- `LLMCorrectionService`는 현재 provider enum이 `none/gemini/copilot/codex`로 고정되어 있고, 교정과 요약이 같은 provider 상태를 공유한다.
- `SummaryService`는 `LLMCorrectionService.selectedProvider`를 그대로 사용한다. 그래서 "전사 자동 교정"을 끄면 최종 요약 LLM 호출도 같이 꺼진다.
- `SettingsView`는 provider별 모델 목록을 하드코딩한다.
- `MeetingSetupView`는 회의 시작 시 회의별 용어집을 입력받지만, 앱 전체에서 재사용하는 용어집 관리 구조는 없다.
- `ConfluenceService`는 REST 검색/본문 조회와 API token 저장을 이미 갖고 있다.
- `MeetingExporter`는 Markdown 파일 내보내기만 갖고 있고 Confluence publish 경로는 없다.
- `MeetingStore`는 회의 JSON 파일 저장 구조이며 임베딩 인덱스는 없다.
- `AudioSourceProtocol`은 마이크 입력만 구현되어 있고 파일/시스템 오디오 입력 구현은 없다.
- `KeychainService`는 단일 Keychain wrapper이며 개발용 secret store 분리는 없다.

## 3. 제품 원칙

사용자 선호: 심플함, 사용 편의성.

Minto2에 적용할 Toss식 UI/UX 원칙:

- 기본값이 좋아야 한다. 사용자가 모델을 몰라도 "추천"을 누르면 쓸 수 있어야 한다.
- 설정은 한 번에 다 보여주지 않는다. 먼저 선택하고, 필요한 입력만 펼친다.
- 전문 용어는 숨긴다. "provider", "embedding", "RAG" 대신 "교정 방식", "회의 검색", "답변 생성"으로 표현한다.
- 상태는 명확해야 한다. 연결됨, 사용 가능, 권한 필요, 토큰 필요, 실행 중, 실패 원인을 즉시 보여준다.
- 신뢰를 해치지 않는다. 클라우드로 나가는 기능은 명확히 표시하고, 로컬 기능은 "기기 안에서 처리"라고 구분한다.
- 장식보다 작업 흐름을 우선한다. 카드 중첩, 과한 radius, 설명문 남발을 피하고 실제 버튼/선택/결과를 앞에 둔다.

## 4. 설계 결정

### 4.1 교정과 요약 설정 분리

현재는 전사 자동 교정을 끄면 요약도 꺼지는 구조다. 사용자 입장에서는 이름과 실제 영향 범위가 다르다.

결정:

- `전사 자동 교정`과 `회의 요약/구조화`를 별도 toggle로 분리한다.
- 둘 다 같은 LLM provider/model을 기본 공유하되, 내부 설정 키는 분리 가능하게 설계한다.
- 회의 요약/구조화는 교정이 꺼져도 원문 전사를 입력으로 실행할 수 있어야 한다.

### 4.2 LLM provider adapter 도입

현재 provider별 구현이 UI와 서비스에 흩어져 있다.

결정:

- `LLMProvider` 프로토콜을 도입한다.
- 교정/요약 호출은 `LLMRequest`와 `LLMResponse`로 표준화한다.
- 모델 목록은 `ModelCatalogService` 또는 provider adapter의 `listModels()`로 통합한다.
- 실패는 공통 오류로 정규화한다: notConfigured, unauthorized, modelUnavailable, rateLimited, network, badResponse.

### 4.3 공식 API와 비공식 계정 연동 분리

현재 `CodexOAuthService`와 `GeminiOAuthService` 일부 경로는 공식 API key 방식이 아니라 CLI/내부 endpoint와 가까운 흐름이다.

결정:

- 신규 API provider는 공식 API key 방식으로 추가한다.
- GPT는 공식 OpenAI API provider를 기본 의미로 사용한다.
- 기존 Codex/ChatGPT 계정 연동은 유지가 필요하면 "GPT 계정 로그인(실험)"처럼 내부적으로 분리한다.
- UI에서 기존 "OpenAI Codex" 표기는 "GPT"로 바꾸되, 실제 연결 방식이 공식 API인지 계정 로그인인지 명확히 표시한다.

### 4.4 모델 목록 정책

공식 모델 목록 API가 있는 provider:

- OpenAI: `GET https://api.openai.com/v1/models`
- Gemini: `GET https://generativelanguage.googleapis.com/v1beta/models`
- Anthropic: `GET https://api.anthropic.com/v1/models`
- OpenRouter: `GET https://openrouter.ai/api/v1/models`

결정:

- 공식 API provider는 모델 목록을 fetch하고 24시간 캐시한다.
- 캐시 실패 시 수동 입력과 문서 링크를 제공한다.
- 모델은 "추천", "빠름", "품질 우선", "저비용", "긴 문맥" 같은 사용자 언어로 필터링한다.
- 비공식/내부 연동 provider는 자동 목록화를 강제하지 않고 수동 입력 + 안내 링크로 처리한다.

### 4.5 로컬 LLM은 먼저 adapter, 모델 번들링은 나중

로컬 LLM은 모델 품질, 용량, RAM, 배포 방식 변수가 크다.

결정:

- 1차는 `LocalLLMProvider` adapter와 설정 UI를 만든다.
- 런타임 후보는 외부 런타임 우선: Ollama, llama.cpp server, MLX sidecar.
- 앱 번들 모델 다운로드/관리 UI는 측정 후 별도 단계로 둔다.
- 기본 후보는 4B-8B급 quantized 모델부터 제공하고, 14B급은 "품질 우선/고RAM" 옵션으로 둔다.
- 실제 기본값은 `docs/benchmark`의 한국어 회의 교정/요약 벤치마크 결과로 정한다.

RAM 안내 기준 초안:

- 가벼운 로컬: 4B Q4, 약 3-5GB RAM 여유 권장
- 균형 로컬: 7B/8B Q4, 약 6-8GB RAM 여유 권장
- 품질 우선 로컬: 14B Q4, 약 10-16GB RAM 여유 권장

### 4.6 용어집은 전역 + 회의별을 함께 둔다

회의별 용어집만 두면 사용자는 매 회의마다 같은 회사명, 제품명, 프로젝트명, 기술 용어를 반복 입력해야 한다. 반대로 앱이 만든 전역 용어집만 자동으로 넣으면 회의 맥락과 무관한 용어가 LLM 교정에 들어가 과교정이 생길 수 있다.

결정:

- 앱 전체에서 관리하는 `기본 용어집`을 둔다.
- 회의 시작 시에는 `이번 회의 용어`를 별도로 추가할 수 있게 한다.
- 회의 시작 화면에서는 기본 용어집 중 관련 후보를 보여주고, 사용자가 이번 회의에 쓸 항목을 선택하거나 끌 수 있게 한다.
- LLM에는 전체 기본 용어집을 항상 넣지 않는다.
- LLM prompt에는 회의 주제, 사용자가 선택한 용어, 최근 자주 쓰인 용어, Confluence/검색 문맥에 매칭된 용어만 제한된 개수로 넣는다.
- 저장된 회의에서 새 용어 후보를 발견하면 자동 등록하지 않고 "용어집에 추가" 제안만 한다.

초기 데이터 모델:

- `GlossaryEntry`
  - `canonical`: 정확한 표기
  - `aliases`: 잘못 인식되기 쉬운 표현, 음성식 표현, 약어
  - `description`: 짧은 설명
  - `category`: 회사, 프로젝트, 제품, 기술, 사람, 기타
  - `tags`: 검색/추천용 태그
  - `enabled`: 기본 사용 여부
  - `updatedAt`

예시:

- canonical: `Liquibase`
- aliases: `리퀴베이스`, `liqui base`, `liquibase`
- description: `DB 스키마 변경 이력 관리 도구`
- category: `기술`

프롬프트 주입 원칙:

- "정확한 표기" 중심으로 짧게 넣는다.
- 설명은 필요한 경우만 1문장으로 제한한다.
- 30-50개 이상 대량 주입하지 않는다.
- 회의 주제와 무관한 용어는 제외한다.
- 용어집은 지시가 아니라 참고 자료로 취급한다.

## 5. 아키텍처 거버넌스

이 확장은 provider, 저장소, 검색, 내보내기, 입력 소스가 모두 얽힌다. 유지보수가 쉬운 구조를 위해 기능 구현보다 아키텍처 경계와 리뷰 절차를 먼저 고정한다.

### 5.1 변경 결정 기준

아키텍처 변경은 다음 기준을 모두 설명할 수 있을 때만 허용한다.

- 사용자 가치: 현재 구조로는 달성하기 어려운 기능 또는 위험 감소가 있는가
- 유지보수성: 인지 부하를 줄이고 소유 경계를 더 명확히 하는가
- 테스트 가능성: IO 없이 domain logic을 테스트할 수 있게 되는가
- 되돌리기 쉬움: 데이터 마이그레이션 없이 롤백 가능한가
- 기존 패턴과 일관성: 현재 SwiftUI/서비스/스토어 구조와 충돌하지 않는가
- 개인정보/보안: prompt, transcript, token, export 데이터 흐름이 명확한가
- 운영 영향: timeout, retry, idempotency, 로그, 비용 추적이 설계되어 있는가

하나라도 약하면 기본값은 "현재 경계를 보존한 최소 변경"이다.

### 5.2 보존할 경계

기본 dependency direction은 다음을 따른다.

> Domain/Core <- Application/Use-case <- Infrastructure/Adapter <- UI

- Domain/Core
  - 전사 정규화, 용어 매칭, 검색 scoring, export 변환 규칙처럼 순수한 비즈니스 규칙
  - HTTP client, Keychain, UserDefaults, LLM SDK, 파일 IO에 직접 의존하지 않는다.
- Application/Use-case
  - 교정, 요약, 검색, 내보내기 workflow를 조합한다.
  - retry, timeout, idempotency, job 상태 전이를 소유한다.
- Infrastructure/Adapter
  - OpenAI/Gemini/Claude/OpenRouter, Confluence, Keychain, 파일 변환, embedding backend 같은 구체 구현
  - domain rule을 넣지 않고 interface 뒤에서 교체 가능하게 둔다.
- UI
  - 상태를 보여주고 명령을 전달한다.
  - provider request 조립, prompt 생성, 저장 schema 변환을 직접 하지 않는다.

### 5.3 ADR 필요 조건

다음 중 하나라도 해당하면 `docs/adr/`에 ADR을 먼저 작성한다.

- 새 외부 dependency 또는 저장소를 도입한다.
- provider adapter, pipeline, job runner처럼 여러 기능이 공유할 core abstraction을 만든다.
- sync에서 async/batch/worker 구조로 실행 모델을 바꾼다.
- 저장 schema, embedding index, export contract를 비호환 방식으로 변경한다.
- domain 책임을 infrastructure나 UI로 옮기거나 반대로 옮긴다.
- 개인정보가 외부 provider로 나가는 범위가 달라진다.

ADR에는 다음을 포함한다.

- Context: 문제와 제약
- Decision: 선택한 방식
- Alternatives: 실제로 고려한 대안과 기각 이유
- Consequences: 장점, 단점, 비용, 운영 영향
- Migration/Rollback: 기존 데이터/설정 호환과 되돌리기 방법
- Verification: 테스트, 수동 QA, benchmark, observability

### 5.4 리팩터링 기준

리팩터링을 해도 되는 경우:

- 같은 취약 영역을 두 번 이상 반복 수정해야 한다.
- 현재 구조 때문에 unit test가 어렵다.
- retry/idempotency/error handling이 여러 곳에 흩어진다.
- provider, export, search가 서로 직접 의존하기 시작한다.
- 성능 문제가 구조적 원인으로 반복된다.

리팩터링을 하지 않는 경우:

- 미적 취향이나 막연한 future-proofing이 주된 이유다.
- 현재 milestone과 직접 관련 없는 framework/library를 들여온다.
- 여러 layer를 한 번에 바꾸지만 측정 가능한 이득이 없다.
- 기능 구현과 무관한 파일 이동/이름 변경이 커진다.

### 5.5 다중 관점 리뷰 게이트

아키텍처 경계를 넘거나 ADR 조건에 해당하는 변경은 다음 관점 리뷰를 통과해야 한다.

- PM/Product 리뷰
  - 사용자가 실제로 얻는 가치와 scope creep 여부를 본다.
- Architecture 리뷰
  - 경계, dependency direction, interface 안정성, migration 가능성을 본다.
- UI/UX 리뷰
  - 단순함, progressive disclosure, 설정 피로도, Pencil 필요 여부를 본다.
- Security/Privacy 리뷰
  - transcript, prompt, token, export 데이터가 어디로 나가는지 본다.
- QA/Code Review
  - 테스트 증거, edge case, 실패 처리, 회귀 위험을 본다.
- Docs 리뷰
  - docs/work, docs/benchmark, ADR, AGENTS/CLAUDE 업데이트 여부를 본다.

리뷰 중 하나라도 blocking 이슈를 내면, 해당 PR은 merge하지 않는다. 예외는 ADR에 남기고 사용자가 승인해야 한다.

### 5.6 UI 아키텍처 기준

Pencil 작업이 필요한 경우:

- 3단계 이상 multi-step flow가 생긴다.
- 설정 화면에 4개 이상의 상태가 추가된다.
- 검색, 답변, 용어집처럼 사용자의 mental model이 바뀐다.
- 내보내기, 파일 입력, 시스템 오디오처럼 실패/권한/진행 상태가 많은 화면이다.

설정 비대화 원칙:

- 핵심 설정만 기본으로 노출한다.
- 고급 모델 파라미터는 접는다.
- export 관련 설정은 전역 설정이 아니라 export sheet 안에 둔다.
- input source 관련 설정은 녹음/파일 입력 흐름 근처에 둔다.

### 5.7 코드리뷰 단계

각 구현 PR 또는 커밋 묶음은 다음 순서로 닫는다.

1. 작성자가 self-review를 먼저 한다.
2. 자동 검증을 통과한다.
3. 변경 scope에 맞는 agent/code-owner 리뷰를 받는다.
4. 리뷰 지적을 반영하거나, 반영하지 않는 이유를 계획/ADR/작업 로그에 남긴다.
5. 최종 QA 증거를 남긴다.

코드리뷰 체크리스트:

- 변경이 계획의 어느 Phase와 연결되는지 명확하다.
- 새 abstraction은 두 개 이상의 실제 사용처 또는 명확한 near-term 사용처가 있다.
- domain logic은 IO 없이 테스트 가능하다.
- provider/network 오류는 timeout, rate limit, auth, malformed response로 구분된다.
- token, prompt, transcript 원문이 로그에 남지 않는다.
- 저장 schema 변경은 backward-compatible 하거나 migration/rollback이 있다.
- UI 변경은 empty/loading/error/success/disabled 상태를 가진다.
- 관련 문서와 benchmark 위치가 업데이트되어 있다.

## 6. 구현 단계

### Phase 0. 기반 문서와 디자인 원칙

목표:

- 기능 정의서와 컨벤션을 먼저 정리해 이후 작업 기준을 고정한다.

작업:

- `docs/service-definition.md` 추가
- `AGENTS.md` 추가
- `CLAUDE.md` 추가
- `docs/work-log.md`에 이번 확장 작업 인덱스 추가
- `docs/work/` 사용 규칙 문서화
- `docs/benchmark/` 사용 규칙 문서화
- `Resources/designs/`를 Pencil 결과물 저장 위치로 명시

검증:

- 문서에 현재 기능, 신규 기능, 비기능 요구사항, 보안/개인정보 원칙이 들어 있는지 자체 리뷰
- 기존 global AGENTS와 충돌하는 규칙이 없는지 확인

### Phase 1. LLM 설정/Provider 기반 정리

목표:

- 교정과 요약을 분리하고, provider 확장을 위한 내부 API를 만든다.

작업:

- `LLMCorrectionService`를 provider adapter 기반으로 리팩터링
- `SummaryService`가 교정 toggle과 독립적으로 동작하도록 변경
- `LLMProvider`, `LLMProviderID`, `LLMModelInfo`, `LLMProviderError` 추가
- provider별 secret/config 저장 모델 정리
- UI에서 "전사 자동 교정"과 "회의 요약/구조화"를 분리
- "OpenAI Codex" 표기를 "GPT" 계열로 변경
- provider 목록: 로컬, GPT, Gemini, Claude, OpenRouter, Copilot(선택/기존 유지)
- 전역 용어집/회의별 용어집을 함께 읽어 `CorrectionPrompt`와 `SummaryPrompt`에 넣는 context resolver 추가

검증:

- provider none이어도 전사 저장과 파일 내보내기가 동작
- 교정 off + 요약 on이면 원문 전사로 요약 생성
- 교정 on + 요약 off이면 교정 전사만 저장
- 전역 용어집 off/회의별 용어집 on 조합과 전역 용어집 on/회의별 용어집 off 조합이 모두 동작
- 기존 저장 회의 JSON 디코딩 유지
- `swift test --disable-sandbox --scratch-path /tmp/minto2-llm-phase1 --filter SummaryServiceTests`
- `swift test --disable-sandbox --scratch-path /tmp/minto2-llm-phase1 --filter CorrectionPromptTests`

### Phase 2. 공식 API provider 추가

목표:

- API key 방식으로 GPT/Gemini/Claude/OpenRouter를 사용할 수 있게 한다.

작업:

- `OpenAIAPIProvider` 추가
- `GeminiAPIProvider` 추가. 기존 Gemini OAuth 흐름과 분리한다.
- `AnthropicAPIProvider` 추가
- `OpenRouterAPIProvider` 추가
- provider별 모델 목록 fetch/cache 구현
- 모델 목록 fetch 실패 시 수동 입력 fallback 구현
- API key 저장은 `SecretStore` 추상화 뒤 Keychain에 저장
- 네트워크 로그에 prompt/API key/토큰이 남지 않도록 redaction 규칙 추가

검증:

- 각 provider 모델 목록 response fixture parser 테스트
- API key 미설정 시 버튼/실행 비활성화
- 401/403/429/5xx 오류 메시지 구분
- 모델 직접 입력이 request에 정확히 반영되는지 테스트
- 실 API 테스트는 env key가 있을 때만 실행

### Phase 3. 개발 Keychain 프롬프트 감소

목표:

- 개발 중 macOS Keychain 비밀번호 요청 반복을 줄인다.

작업:

- `SecretStore` 프로토콜 추가
- 기본 구현은 `KeychainSecretStore`
- 개발 opt-in 구현은 `LocalDevSecretStore`
- 환경변수 예: `MINTO_DEV_SECRET_STORE=file`
- 로컬 dev secret 파일은 Application Support 하위에 저장하고 git ignore 대상 문서화
- Keychain read/write를 앱 실행 중 캐시하고, SwiftUI render path에서 직접 Keychain 접근 금지
- Keychain OSStatus 로깅을 추가해 prompt 원인을 진단 가능하게 한다.

검증:

- 기본 모드에서 기존 토큰 사용 가능
- dev store 모드에서 Keychain 호출 없이 provider configured 상태 계산
- 로그에 secret 원문이 남지 않음
- 앱 재실행 후 dev token 유지

중단 조건:

- Keychain prompt가 code signing/TCC 정책 때문에 완전히 사라지지 않으면, 코딩 우회가 아니라 "개발 서명 고정" 절차를 문서화한다.

### Phase 3b. 용어집 관리

목표:

- 반복 입력 없이 회의 도메인 용어를 재사용하고, 회의별로 필요한 용어만 LLM에 전달한다.

작업:

- `GlossaryStore` 추가
- `GlossaryEntry` 모델 추가
- 설정에 "용어집" 관리 화면 추가
- 회의 시작 시트에 "기본 용어집에서 가져오기" 추가
- `GlossaryContextResolver` 추가
- `CorrectionPrompt`와 `SummaryPrompt`에 선별된 glossary context를 주입
- 저장 회의 상세에서 선택 텍스트를 "용어집에 추가"할 수 있는 후속 진입점 검토

검증:

- 용어집 항목 CRUD 테스트
- alias가 prompt에 포함되는지 테스트
- disabled 용어는 prompt에 들어가지 않는지 테스트
- 회의별 용어가 전역 용어보다 우선하는지 테스트
- prompt에 너무 많은 용어가 들어가지 않도록 상한 테스트

### Phase 4. 검색 인덱스와 임베딩

목표:

- Minto에 저장한 회의가 검색 데이터 소스가 되도록 한다.

작업:

- `MeetingSearchIndex` 추가
- 회의 저장 시 transcript/summary/decisions/actionItems/openQuestions를 chunk로 분리
- chunk metadata: meetingID, section, time, text, checksum
- 1차 검색은 keyword + lightweight semantic scoring 혼합
- embedding provider는 로컬 우선, 원격 provider 선택 가능
- 초기 저장 방식은 기존 JSON MeetingStore와 충돌을 줄이기 위해 sidecar index 파일로 시작
- 회의 삭제 시 index chunk 삭제
- index schema version 추가

검증:

- 같은 회의를 두 번 저장해도 중복 chunk가 생기지 않음
- 회의 삭제 시 index도 정리
- "db 스키마 형상 관리" 같은 질의가 관련 회의 chunk를 반환
- index 손상 시 앱이 크래시하지 않고 rebuild 안내

### Phase 5. 검색 답변 생성

목표:

- 검색 결과를 LLM이 종합해 답할 수 있게 한다.

작업:

- 검색 UI에 "답변 생성" mode 추가
- retrieval 결과 chunk를 근거로 `AnswerPrompt` 생성
- 답변에는 출처 chip: 회의 제목, 시간, 섹션
- 로컬 LLM이 설정되어 있으면 로컬 우선 사용
- 클라우드 LLM 사용 시 외부 전송 안내 표시
- 답변 생성은 search와 분리된 명령으로 둔다. 검색만 해도 충분히 유용해야 한다.

검증:

- provider 없음이면 답변 생성 버튼 비활성화, 일반 검색은 동작
- 답변이 검색 결과에 없는 내용을 출처 없이 말하지 않도록 prompt/test fixture 구성
- 출처 chip 클릭 시 해당 회의 상세/타임스탬프로 이동

### Phase 6. Confluence 연결 가이드와 내보내기

목표:

- Confluence 연결과 내보내기를 사용자가 이해하기 쉽게 만든다.

작업:

- 설정의 Confluence 섹션을 3단계 guide로 변경
  - 사이트 URL 입력
  - 이메일 입력
  - API token 발급 링크/붙여넣기
- Atlassian API token 발급 링크를 버튼으로 제공
- "연결 테스트" 버튼 추가
- `ConfluenceExportService` 추가
- 내보내기 버튼 클릭 시 선택 sheet 표시
  - Markdown 파일
  - 클립보드 복사
  - Confluence
- Confluence 미설정이면 disabled 상태로 보여주고 설정으로 이동
- Confluence 설정됨이면 space/page destination 선택
- destination UX: 최근 내보낸 위치, 검색으로 parent page 선택, 기본 제목 미리보기
- dry-run preview 추가: 실제 publish 전에 제목/위치/본문 확인

검증:

- token 없음: Confluence export disabled + 설정 이동
- token 있음: destination 선택 가능
- create/update payload fixture 테스트
- 401/403/404/rate limit 오류 메시지 구분
- Markdown과 Confluence storage 변환에서 결정사항/할 일/질문/전사가 누락되지 않음

### Phase 7. 음성/영상 파일 입력

목표:

- 녹음이 끝난 뒤 파일을 넣어 회의록을 만들 수 있게 한다.

작업:

- 회의 목록 첫 화면에 "파일로 회의록 만들기" 추가
- `NSOpenPanel`로 audio/video 선택
- `AVAssetReader` 기반 `FileTranscriptionJob` 추가
- 16kHz mono PCM 변환 후 기존 STT/VAD/요약 pipeline 재사용
- 긴 파일 진행률/취소 지원
- 생성된 회의는 MeetingStore에 일반 회의와 동일하게 저장

검증:

- 짧은 wav/mp4 fixture 처리
- 지원하지 않는 파일 형식 메시지
- 긴 파일 취소 시 partial artifact 정리
- 전사 실패해도 앱 크래시 없음

### Phase 8. 시스템 사운드 입력

목표:

- 화상회의 앱의 상대방 소리를 Minto가 입력으로 받을 수 있게 한다.

작업:

- `SystemAudioSource` 추가
- macOS 14 기준 ScreenCaptureKit 오디오 캡처 검토
- 입력 모드 추가: 마이크, 시스템 사운드, 마이크+시스템
- 권한 상태 UI: 화면 기록/오디오 캡처 권한 필요 안내
- level meter로 현재 입력이 들어오는지 즉시 확인
- echo/mix 이슈는 1차에서 안내와 선택으로 처리하고 자동 제거는 후속으로 둔다.

검증:

- 권한 없음: 비활성화 + 설정 열기 안내
- 권한 있음: level meter 동작
- 녹음 시작/종료와 기존 VAD pipeline 호환
- 마이크만 선택한 기존 흐름 회귀 없음

## 7. UI/Pencil 작업 계획

Pencil 산출물 위치:

- `.pen`: `Resources/designs/minto-intelligence-settings.pen`
- export 이미지: `Resources/designs/minto-intelligence-settings/`

필수 mockup:

- 설정: 교정/요약/LLM provider/local/API/source 연결을 하나의 "지능 설정" 흐름으로 정리
- 설정: 용어집 목록, 추가, 편집, 비활성화, 회의에 적용 상태
- Confluence token guide: 연결 전/입력 중/연결됨/오류
- 검색: 일반 검색 결과와 답변 생성 결과의 차이
- 내보내기 sheet: 파일/클립보드/Confluence
- 파일 입력: 드롭/선택/진행/완료
- 시스템 사운드 권한: 사용 가능/권한 필요/입력 감지

디자인 검토 기준:

- 사용자가 첫 화면에서 "새 회의", "검색", "파일로 회의록 만들기"를 바로 이해하는가
- 설정 화면에서 기본 추천 경로가 한눈에 보이는가
- 용어집을 모르는 사용자도 "자주 나오는 고유명사/전문용어를 미리 등록한다"는 의미를 이해하는가
- 공급자/모델 선택이 비개발자에게도 이해되는가
- 클라우드 전송 여부가 명확한가
- 연결 실패 시 다음 행동이 보이는가

## 8. 병렬 작업 운영

작업은 한 브랜치에서 무작정 병렬 편집하지 않는다. 다음 lane으로 분리한다.

- Lane A: Provider/Secret/ModelCatalog
- Lane B: Settings/UX/Pencil
- Lane C: MeetingSearchIndex/Embedding
- Lane D: Confluence export
- Lane E: File/System audio input
- Lane F: Docs/AGENTS/CLAUDE
- Lane G: Review/QA/ADR

병렬 규칙:

- 같은 파일을 동시에 수정하지 않는다.
- `SettingsView`, `MeetingLibraryView`, `AppDelegate`는 통합 충돌 가능성이 크므로 integration pass에서 한 번에 합친다.
- 각 lane은 자기 테스트를 먼저 통과한 뒤 integration branch에 병합한다.
- 큰 provider/API 변경은 fixture parser 테스트를 먼저 만든다.
- 아키텍처 경계를 넘는 lane은 구현 전에 ADR 초안을 작성하고, merge 전에 다중 관점 리뷰를 통과한다.

## 9. 검증 게이트

필수:

- `swift build --disable-sandbox --scratch-path /tmp/minto2-expansion-build`
- `swift test --disable-sandbox --scratch-path /tmp/minto2-expansion-test`

단계별:

- Provider: 모델 목록 parser fixture, auth error mapping
- Summary/Correction: provider off/on 조합 테스트
- Glossary: CRUD, alias matching, prompt injection cap, meeting override 테스트
- Search: chunking/idempotency/search ranking 테스트
- Export: Markdown/Confluence payload 테스트
- File import: fixture 파일 전사 job 테스트
- System audio: 권한/availability unit 테스트 + 수동 QA
- UI: 앱 실행 후 설정, 회의 목록, 내보내기, 파일 입력 화면 수동 QA
- Code review: self-review, agent/code-owner review, QA evidence, ADR 필요 여부 확인

벤치마크:

- 로컬 LLM 후보별 교정 품질, 요약 구조화 성공률, latency, RAM 사용량을 `docs/benchmark/`에 기록
- benchmark 없는 모델을 기본값으로 올리지 않는다.

## 10. 리스크와 대응

- 리스크: provider API 모델명이 자주 바뀜
  - 대응: 자동 목록 + 캐시 + 수동 입력 fallback + 공식 문서 링크
- 리스크: 로컬 LLM 품질이 회의 교정에 부족함
  - 대응: 기본값을 측정 후 결정, 로컬은 "개인정보 우선" 옵션으로 명확히 설명
- 리스크: 설정 화면이 복잡해짐
  - 대응: 단계적 disclosure, 추천 기본값, 고급 설정 접기
- 리스크: Keychain prompt가 앱 코드만으로 완전히 해결되지 않음
  - 대응: SecretStore 분리와 개발용 opt-in store, 서명 고정 문서화
- 리스크: 시스템 사운드 캡처 권한/OS 차이
  - 대응: availability 검사와 비활성화 상태 표시, 마이크 경로 회귀 테스트
- 리스크: Confluence publish가 잘못된 위치에 생성됨
  - 대응: dry-run preview, 최근 위치, 명시적 parent page 선택
- 리스크: 기능 확장 중 무리한 리팩터링으로 기존 녹음/전사 흐름이 흔들림
  - 대응: ADR 조건, hard boundary, self-review, code-owner review, 회귀 테스트를 merge gate로 둔다.

## 11. 1차 실행 범위 제안

처음 구현은 다음까지로 끊는다.

1. 문서/컨벤션 정비
2. 교정/요약 toggle 분리
3. provider adapter skeleton
4. GPT/Gemini/Claude/OpenRouter API key 설정 UI skeleton
5. ModelCatalog fetch/cache fixture 테스트
6. 전역 용어집 관리 skeleton과 회의별 용어집 선택 흐름
7. Confluence token guide UI 개선
8. Keychain 개발 편의 설계와 SecretStore skeleton
9. 아키텍처 ADR/코드리뷰/QA 게이트 문서화

임베딩, Confluence publish, 파일 입력, 시스템 사운드는 기반이 안정된 다음 별도 커밋으로 진행한다.

## 12. 전문가 리뷰 반영

아키텍처 리뷰 결론:

- big-bang 구현 금지
- provider adapter와 job/pipeline 경계를 먼저 고정
- 임베딩/Q&A/Confluence publish/system audio는 기반 안정 후 진행
- 교정 output과 요약 output은 내부 구조를 안정화해야 search/export가 흔들리지 않음
- architecture boundary를 넘는 변경은 ADR과 다중 관점 리뷰를 통과해야 함
- aesthetic refactor나 speculative abstraction은 금지하고, 반복 수정/테스트 불가/운영 위험이 있을 때만 리팩터링

UIUX 리뷰 반영:

- 설정은 "Intelligence Hub"처럼 묶되, 한 화면에 모든 필드를 드러내지 않는다.
- Confluence는 wall of text가 아니라 3단계 guide로 만든다.
- 검색 답변은 일반 검색과 구분하고 source chip을 둔다.
- 내보내기는 sheet에서 명확한 선택지로 보여준다.
- "Auto-select best" 또는 "추천" 기본값을 제공한다.
- 3단계 이상 flow, 상태 4개 이상, mental model 변화가 있는 UI는 Pencil mockup을 먼저 만든다.
- 설정은 80/20 원칙과 progressive disclosure로 비대화를 막는다.

문서/프로세스 리뷰 반영:

- ADR, docs/work, docs/benchmark, QA evidence를 PR 완료 조건에 포함한다.
- 구현 PR은 conventional commit 단위로 작게 유지한다.
- 인터페이스 변경 시 서비스 정의서와 AGENTS/CLAUDE 컨벤션을 함께 업데이트한다.

## 13. 완료 정의

전체 작업 완료 조건:

- 저장된 회의 검색과 LLM 답변이 동작한다.
- 교정과 요약을 각각 켜고 끌 수 있다.
- 전역 용어집과 회의별 용어집을 추가·관리하고, 관련 용어만 교정/요약에 반영할 수 있다.
- 로컬/API provider 설정이 사용자 언어로 이해 가능하다.
- Confluence token 발급/연결/내보내기 흐름이 앱 안에서 막히지 않는다.
- 음성/영상 파일로 회의록을 만들 수 있다.
- 시스템 사운드 입력 가능 여부가 기기/권한 기준으로 정확히 표시된다.
- 개발 중 Keychain prompt를 줄이는 opt-in 경로가 있다.
- 기능 정의서와 작업 컨벤션이 docs/AGENTS/CLAUDE에 반영되어 있다.
- 아키텍처 변경은 ADR과 다중 관점 리뷰를 거쳐 결정된다.
- 각 구현 단위는 코드리뷰와 QA evidence를 통과한다.
- 모든 변경은 테스트와 수동 QA 증거를 남긴다.
