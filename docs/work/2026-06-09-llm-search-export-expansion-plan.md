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
- Confluence 연결/내보내기 UX를 사용자가 막히지 않게 개선한다.
- 음성/영상 파일을 넣어 사후 회의록을 만들 수 있게 한다.
- 화상회의를 위해 시스템 사운드 입력을 지원한다.
- 개발 중 Keychain 비밀번호 요청을 줄인다.
- 기능 정의서, 작업 컨벤션, 디자인 원칙을 문서화한다.

## 2. 현재 코드 기준 근거

- `LLMCorrectionService`는 현재 provider enum이 `none/gemini/copilot/codex`로 고정되어 있고, 교정과 요약이 같은 provider 상태를 공유한다.
- `SummaryService`는 `LLMCorrectionService.selectedProvider`를 그대로 사용한다. 그래서 "전사 자동 교정"을 끄면 최종 요약 LLM 호출도 같이 꺼진다.
- `SettingsView`는 provider별 모델 목록을 하드코딩한다.
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

## 5. 구현 단계

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

검증:

- provider none이어도 전사 저장과 파일 내보내기가 동작
- 교정 off + 요약 on이면 원문 전사로 요약 생성
- 교정 on + 요약 off이면 교정 전사만 저장
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

## 6. UI/Pencil 작업 계획

Pencil 산출물 위치:

- `.pen`: `Resources/designs/minto-intelligence-settings.pen`
- export 이미지: `Resources/designs/minto-intelligence-settings/`

필수 mockup:

- 설정: 교정/요약/LLM provider/local/API/source 연결을 하나의 "지능 설정" 흐름으로 정리
- Confluence token guide: 연결 전/입력 중/연결됨/오류
- 검색: 일반 검색 결과와 답변 생성 결과의 차이
- 내보내기 sheet: 파일/클립보드/Confluence
- 파일 입력: 드롭/선택/진행/완료
- 시스템 사운드 권한: 사용 가능/권한 필요/입력 감지

디자인 검토 기준:

- 사용자가 첫 화면에서 "새 회의", "검색", "파일로 회의록 만들기"를 바로 이해하는가
- 설정 화면에서 기본 추천 경로가 한눈에 보이는가
- 공급자/모델 선택이 비개발자에게도 이해되는가
- 클라우드 전송 여부가 명확한가
- 연결 실패 시 다음 행동이 보이는가

## 7. 병렬 작업 운영

작업은 한 브랜치에서 무작정 병렬 편집하지 않는다. 다음 lane으로 분리한다.

- Lane A: Provider/Secret/ModelCatalog
- Lane B: Settings/UX/Pencil
- Lane C: MeetingSearchIndex/Embedding
- Lane D: Confluence export
- Lane E: File/System audio input
- Lane F: Docs/AGENTS/CLAUDE

병렬 규칙:

- 같은 파일을 동시에 수정하지 않는다.
- `SettingsView`, `MeetingLibraryView`, `AppDelegate`는 통합 충돌 가능성이 크므로 integration pass에서 한 번에 합친다.
- 각 lane은 자기 테스트를 먼저 통과한 뒤 integration branch에 병합한다.
- 큰 provider/API 변경은 fixture parser 테스트를 먼저 만든다.

## 8. 검증 게이트

필수:

- `swift build --disable-sandbox --scratch-path /tmp/minto2-expansion-build`
- `swift test --disable-sandbox --scratch-path /tmp/minto2-expansion-test`

단계별:

- Provider: 모델 목록 parser fixture, auth error mapping
- Summary/Correction: provider off/on 조합 테스트
- Search: chunking/idempotency/search ranking 테스트
- Export: Markdown/Confluence payload 테스트
- File import: fixture 파일 전사 job 테스트
- System audio: 권한/availability unit 테스트 + 수동 QA
- UI: 앱 실행 후 설정, 회의 목록, 내보내기, 파일 입력 화면 수동 QA

벤치마크:

- 로컬 LLM 후보별 교정 품질, 요약 구조화 성공률, latency, RAM 사용량을 `docs/benchmark/`에 기록
- benchmark 없는 모델을 기본값으로 올리지 않는다.

## 9. 리스크와 대응

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

## 10. 1차 실행 범위 제안

처음 구현은 다음까지로 끊는다.

1. 문서/컨벤션 정비
2. 교정/요약 toggle 분리
3. provider adapter skeleton
4. GPT/Gemini/Claude/OpenRouter API key 설정 UI skeleton
5. ModelCatalog fetch/cache fixture 테스트
6. Confluence token guide UI 개선
7. Keychain 개발 편의 설계와 SecretStore skeleton

임베딩, Confluence publish, 파일 입력, 시스템 사운드는 기반이 안정된 다음 별도 커밋으로 진행한다.

## 11. PM 리뷰 반영

아키텍처 리뷰 결론:

- big-bang 구현 금지
- provider adapter와 job/pipeline 경계를 먼저 고정
- 임베딩/Q&A/Confluence publish/system audio는 기반 안정 후 진행
- 교정 output과 요약 output은 내부 구조를 안정화해야 search/export가 흔들리지 않음

UIUX 리뷰 반영:

- 설정은 "Intelligence Hub"처럼 묶되, 한 화면에 모든 필드를 드러내지 않는다.
- Confluence는 wall of text가 아니라 3단계 guide로 만든다.
- 검색 답변은 일반 검색과 구분하고 source chip을 둔다.
- 내보내기는 sheet에서 명확한 선택지로 보여준다.
- "Auto-select best" 또는 "추천" 기본값을 제공한다.

## 12. 완료 정의

전체 작업 완료 조건:

- 저장된 회의 검색과 LLM 답변이 동작한다.
- 교정과 요약을 각각 켜고 끌 수 있다.
- 로컬/API provider 설정이 사용자 언어로 이해 가능하다.
- Confluence token 발급/연결/내보내기 흐름이 앱 안에서 막히지 않는다.
- 음성/영상 파일로 회의록을 만들 수 있다.
- 시스템 사운드 입력 가능 여부가 기기/권한 기준으로 정확히 표시된다.
- 개발 중 Keychain prompt를 줄이는 opt-in 경로가 있다.
- 기능 정의서와 작업 컨벤션이 docs/AGENTS/CLAUDE에 반영되어 있다.
- 모든 변경은 테스트와 수동 QA 증거를 남긴다.
