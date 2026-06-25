# ADR 0007: Claude Code CLI를 LLM provider로 추가

상태: Accepted
작성일: 2026-06-24

> 리뷰: 다중관점 critic 리뷰 1차 REVISE(Critical 3·Major 4·Minor 4) → 전건 반영 → 재검토 ACCEPT(2026-06-24). 구현 착수 조건 충족.
> **남은 결정(엔지니어링 외)**: 사용자 구독을 앱 백엔드로 호출하는 ToS 적합성은 제품/정책 판단 — 기능 노출 전 확인 대상.

## Context

현재 AI 연결 서비스(교정·요약·답변)는 세 종류 provider로 구성된다.

- `LLMAPIKeyTextProvider` — API 키(Keychain). OpenAI/Gemini/**Claude**/OpenRouter.
- `LocalLLMProvider` — Ollama/OpenAI 호환 로컬 HTTP 서버.
- `LegacyAccountLLMTextProvider` — OAuth 계정(ChatGPT/Gemini/Copilot).

사용자 요청: **OAuth/API 키를 앱이 관리하지 않고**, 로컬에 이미 설치·로그인된 `claude`(Claude Code CLI)에 요청을 보내 LLM 작업을 시키는 선택지를 추가할 수 있는지.

조사 결과(타당성 확인됨):

- **Provider 추상화가 HTTP와 완전 분리**됨. `LLMTextGenerationProvider.generateText(LLMTextRequest) -> LLMTextResponse`는 instructions·userContent·useCase만 받고 URL/헤더 의존이 없다 → CLI 호출형 구현체가 구조적 장벽 없이 끼워진다.
- 앱은 **비샌드박스**(`Minto.entitlements`에 `app-sandbox` 없음, `cs.disable-library-validation`·`cs.allow-jit`만) → `Foundation.Process`로 외부 바이너리 spawn에 추가 entitlement 불필요.
- `claude -p`(--print) 헤드리스 모드가 TTY 없이 동작하고, `--output-format json`(`.result` 필드), `--model`, `--disallowedTools`, `--no-session-persistence`로 순수 텍스트 in→out 호출이 가능하다.
- 코드베이스에 기존 `Process`/`NSTask` 사용처가 없다 → 앱 최초의 subprocess 실행 모델.

제약(아래 Decision/Consequences에서 다룸): 인증 경로 함정(`--bare`↔Keychain), Node 기동 지연, 구독 rate limit, GUI 앱의 PATH 미상속, 그리고 "로컬 CLI라도 Anthropic으로 전송"(로컬 처리 아님).

## Decision

**선택적(opt-in) `ClaudeCodeCLIProvider`(`LLMTextGenerationProvider` 채택)를 추가한다.** `generateText` 내부에서 `Foundation.Process`로 로컬 `claude`를 헤드리스 호출하고 stdout(JSON)의 `result`를 반환한다.

적용·설계 원칙:

- **적용 범위는 교정·요약·답변 생성**이다. 교정은 호출 빈도가 높아 Node 프로세스 기동과 구독 rate limit 영향이 가장 크므로, 사용자가 Claude Code CLI를 명시적으로 선택한 경우에만 열고 UI에 지연 가능성과 Anthropic 전송을 고지한다. 실패는 항상 원문 유지(fail-soft)로 처리한다.
- **인증은 사용자의 기존 `claude` 로그인 재사용을 1순위**로 한다(요청 의도). 이 경로는 `--bare`를 쓸 수 없으므로(=`--bare`는 Keychain 인증을 건너뜀), 컨텍스트 오염은 도구 차단 + 중립 작업 디렉터리(cwd)로 막는다. **앱은 키를 주입하지 않을 뿐 아니라, spawn하는 Process environment에서 `ANTHROPIC_API_KEY`를 명시적으로 제거**한다 — GUI 앱은 셸 env는 상속 안 하지만 **launchd 등록 env는 상속**하므로, 그런 사용자가 의도와 달리 조용히 API 키로 과금되는 것을 차단(가치 제안 보존).
- **호출 형태**: 전사·프롬프트·작업 지시는 **stdin으로만** 전달한다(argv 금지 — `ps`로 원문 노출; **임시파일 경로 전달도 금지** — 원문 디스크 잔존). `--output-format json` 파싱. `--model`로 모델 선택(설정값). 도구 차단은 `--disallowedTools "*"`, 세션 잔존 방지는 지원되는 CLI에서 `--no-session-persistence`를 사용한다.
- **프로세스 수명**: `Process`를 `withTaskCancellationHandler`로 감싸 취소 시 `terminate()`, timeout(기본 60s) 초과 시 terminate + `.network`. stdout/stderr는 비동기 읽기(파이프 버퍼 deadlock 방지). 앱 종료 시 진행 중 프로세스 정리. provider 내부 동시성 상한(직렬화/세마포어)으로 Node 프로세스 폭증 방지.
- **CLI 경로 발견**: GUI 앱은 셸 PATH를 상속하지 않으므로, 공통 설치 위치(`~/.claude/local/claude`, `/opt/homebrew/bin/claude`, `/usr/local/bin/claude`, npm global)를 탐색하고, 설정에서 사용자가 경로를 직접 지정할 수 있게 한다.
- **연결 확인**: 설정 UI에 "연결 확인" 동작 — **실제 trivial 프롬프트 1회 왕복**으로 설치+인증+파싱 전 스택을 진단한다(`claude --version`은 인증을 검증 못 하므로 부적합). Node 기동으로 수초 걸릴 수 있어 대기 카피를 표시한다.
- **fail-soft**: 미설치/미인증/timeout/비정상 종료는 `LLMProviderError.notConfigured`/`.unauthorized`/`.network`로 매핑한다. 교정·요약·답변 실패가 전사·저장을 망치지 않는다. CLI stderr가 프롬프트 일부를 echo해도 원문·주제·용어집·문서 문맥이 로그나 사용자 노출 에러에 남지 않아야 하므로, raw stderr prefix는 모든 Claude CLI use case에서 외부로 내보내지 않는다.

## Alternatives

- **대안 A — 기존 `LLMAPIKeyTextProvider`(Claude API 키)로 충분**: 앱은 이미 Claude를 API 키로 호출한다. 장점: 가장 단순·저지연·중간 레이어 없음. 단점: 사용자가 **API 키를 발급·입력**해야 함. 기각 이유: 요청의 핵심이 "키 없이 기존 로그인 재사용"이라 이 UX 이득을 못 준다. (단 이득이 작다고 판단되면 이 대안이 우월 — Decision의 적용 범위를 좁게 둔 이유)
- **대안 B — Claude Agent SDK(TS/Python)**: 구조화 출력·스트리밍이 네이티브. 단점: Swift에서 직접 호출 불가(별도 런타임 필요). 기각.
- **대안 C — 아무것도 안 함**: 요청된 UX를 제공 못 함. 사용자가 명시적으로 검토를 요청.
- **대안 D — `--bare` + API 키/장기토큰 강제**: 깨끗한 호출이 되지만 키/토큰 관리를 앱이 떠안아 대안 A와 사실상 동일해지고 "기존 로그인 재사용" 의도를 잃는다. 기각.

## Consequences

### Positive

- `claude` 설치·로그인된 사용자는 **키 입력 0으로** 교정·요약·답변 AI를 쓰고, 기존 Claude 구독에 과금된다.
- Provider 추상화 재사용 → 교정/요약/답변 독립 설정 체계와 자연스럽게 통합된다.
- 외부로 나가는 목적지(Anthropic)는 **기존 Claude API provider와 동일** → 개인정보 전송 "범위" 자체는 확대되지 않는다(메커니즘만 다름).

### Negative

- **앱 최초의 subprocess 실행 모델** 도입 — 프로세스 수명·timeout·zombie 관리 필요.
- **지연·rate limit**: Node 기동 오버헤드 + 구독 동시호출 제한. 교정은 요약·답변보다 호출 빈도가 높아 체감 지연과 rate limit 위험이 가장 크며, UI 경고와 fail-soft가 필수다.
- **PATH·버전 드리프트**: `claude` 위치·플래그가 버전마다 바뀔 수 있어 깨지기 쉬움. 연결 확인·경로 설정으로 완화하나 근본 취약성.
- **ToS 의문**: 구독 자격증명을 앱 백엔드로 호출하는 것이 Claude Code 이용약관에 부합하는지 불확실 — 사용자 본인 기기·본인 로그인 한정으로 한정하고, 약관 확인을 문서에 남긴다.
- **로컬 아님**: "로컬 CLI"라도 Anthropic으로 전송 → UI에 클라우드 전송임을 명시해야 한다(앱 원칙: 로컬/클라우드 구분 표시).
- **인증 경로 불투명**: 연결 확인이 성공해도 그것이 Keychain 로그인인지 (제거 못 한) 다른 자격증명 경로인지 사용자가 구분할 방법이 없다. env 키 제거로 주요 충돌은 막으나, `apiKeyHelper` 등 다른 경로는 남는다 → 설정 경고에 "인증은 로컬 `claude` 설정을 따른다"를 고지.
- **유지보수 취약**: `claude` CLI는 버전마다 플래그·출력 구조가 바뀐다. 어댑터를 팀이 장기 유지할 의지가 전제 — 지원 최소 버전을 기록하고 파싱을 방어적으로 둔다.

## Migration

- 순수 추가(additive). 저장 schema·기존 provider·기존 설정 변경 없음.
- `LLMProviderID`에 케이스 1개, `LLMProviderSelection`·`LLMProviderRegistry`에 분기 추가, 새 `ClaudeCodeCLIProvider.swift`, 설정 UI의 새 auth kind(CLI 경로) 분기. 기존 사용자 흐름은 그대로.
- 교정/요약/답변 provider는 독립 키(`llmProvider`/`llmSummaryProvider`/`meetingSearchAnswerProvider`)라, 새 provider를 capability 기반으로 노출한다. `.claudeCodeCLI`는 `.correction`, `.summary`, `.answer`를 지원하되 SettingsView의 기존 CLI 경로/연결 확인 상태를 사용자-facing 상태로 유지한다.

## Rollback

- `LLMProviderID` 케이스 + 분기 + `ClaudeCodeCLIProvider.swift` + 설정 UI 분기 제거. 데이터 마이그레이션 없음(설정값만 무효화 — 선택돼 있던 사용자는 기본 provider로 폴백).

## Verification

- **선행**: `Log.swift`에 `llm` 카테고리 추가(현재 없음), `LLMProviderAuthKind`에 `.cliPath` 추가, `LLMProviderSelection`을 열거하는 **SettingsView의 모든 exhaustive switch에 새 케이스 처리**(누락 시 컴파일 실패).
- **단위 테스트**(주입 가능한 `ProcessLauncher` mock, 실제 `claude` 호출 없음): (1) JSON `result` 파싱, (2) 비정상 종료/빈 stdout → `LLMProviderError`, (3) 미설치 경로 → `.notConfigured`, (4) **취소 시 `terminate()` 호출**, (5) **전사가 stdin에만 있고 argv엔 없음**(인자 검사), (6) `result` 부재 → badResponse(원문 미로그).
- **수동 QA**: `claude` 미설치 / 설치+미로그인 / 설치+로그인 세 상태에서 교정·요약·답변 동작·에러 메시지 확인. 설정 "연결 확인" 동작·대기 카피.
- **보안/로그 점검**: 전사 원문이 argv·임시파일·로그 어디에도 안 남는지, 자격증명 미로그. 성공 로그=provider/model/exit code/counts. 실패 로그/에러에는 raw stderr prefix 금지(프롬프트 echo 유출 방지), 대신 exit code와 고정 reason code만 남긴다. Process env에서 `ANTHROPIC_API_KEY` 제거 확인.
- **경계 점검**: UI가 provider request를 조립하지 않고 use-case가 소유하는지. 교정 노출은 Registry capability로만 결정한다.
- 빌드/테스트 게이트: `swift build`/`swift test` 통과. 앱 실행 검증은 `./scripts/dev.sh run`.
