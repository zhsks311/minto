# Claude Code CLI provider 구현 계획

작성일: 2026-06-24 · 근거 ADR: `docs/adr/0007-claude-code-cli-llm-provider.md` (상태: Proposed)
관련 조사: 이 세션의 타당성 검토(provider 추상화 매핑·CLI 헤드리스 능력·entitlements).

> **게이트**: 이 계획은 ADR 0007이 다중관점 리뷰를 통과(상태 Accepted)한 뒤에만 구현에 착수한다. 구현 코드는 Codex에 위임, 검증은 main이 워크트리에서 직접(minto-workflow).

## 목표 (검증 가능한 형태)

`claude` 설치·로그인된 사용자가 **API 키 입력 없이** 교정·요약·답변 생성을 Claude Code CLI로 수행할 수 있다.

- Step 1: provider 골격 + 선택지 노출 → verify: 설정에서 "Claude Code (로컬 CLI)"가 교정·요약·답변 provider로 보이고, 미설치 시 명확한 비활성/에러.
- Step 2: 헤드리스 호출·파싱 → verify: 단위 테스트(mock launcher)로 JSON `result` 파싱·에러 매핑 통과.
- Step 3: 연결 확인·경로 발견 → verify: 설정 "연결 확인"이 설치/인증 상태를 정확히 보고.
- Step 4: 실제 왕복 QA → verify: `dev.sh run`으로 띄워 실제 `claude`로 교정 1건과 요약 1건 생성 성공, 로그에 전사 원문 없음.

## Phase 1 — Provider 골격 (코드: Codex)

> ⚠️ **Phase는 순차**다. Phase 1 verify(빌드 통과) 후에만 Phase 2 착수. Codex 위임 단위는 Phase별.

대상 파일(조사·리뷰 확인됨):

1. `Sources/Minto/Services/LLMProvider.swift` — `LLMProviderID`에 `.claudeCodeCLI` 케이스, `isCloudProvider`=true(Anthropic 전송). `LLMProviderAuthKind`에 **`.cliPath` 케이스 추가**(설정 UI 분기 근거).
2. `Sources/Minto/Services/LLMProviderRegistry.swift` — `defaultDescriptors`에 descriptor 1개: `authKind=.cliPath`, **`requiresWarning=true`**(클라우드 전송), **`supportedCapabilities`에 `.correction`, `.summary`, `.answer` 포함**. `textGenerationProvider(for:)`에 분기(또는 새 생성자).
3. `Sources/Minto/Services/LLMProviderSelection.swift` — enum 케이스 + `providerID`/`init?(providerID:)` switch.
4. **`Sources/Minto/UI/SettingsView.swift`** — `LLMProviderSelection`을 열거하는 **모든 exhaustive switch에 새 케이스 처리**: `currentAPIKeyProviderID`(~line 1665), `currentEmail`(~line 1648), `startLogin`(~line 1698) 및 `activeAIProviderAuthKind` 기반 UI 분기. `CaseIterable` ForEach 렌더링에도 노출됨(교정·요약·답변 capability 기준).
5. 신규 `Sources/Minto/Services/ClaudeCodeCLIProvider.swift` — `LLMTextGenerationProvider` 채택(골격: descriptor/isConfigured/modelCatalog/generateText 스텁).
6. **`LLMCorrectionService.swift`는 기존 capability gate와 fail-soft 경로를 재사용한다.** `.claudeCodeCLI`를 위해 `isLoggedIn` 의미를 새로 만들지 않고, 필요하면 테스트로 routing만 확인한다.

**`modelCatalog()` 전략**: live 조회 대신 **bundledFallback으로 Anthropic 모델 ID 고정 목록** 제공(예: opus/sonnet/haiku 별칭) + 사용자가 모델 ID 직접 입력 허용. 설정 모델값이 성공 로그 `model=`에 직결되므로 빈 카탈로그 금지.

> verify: `swift build` 통과(특히 SettingsView switch exhaustive). 새 provider가 교정·요약·답변 capability 조건에서 보이는지 확인.

## Phase 2 — 헤드리스 호출 (코드: Codex, 설계: main)

**`ProcessLauncher` 추상화(인터페이스 명시)** — Codex가 임의 설계하지 않도록 시그니처를 고정:

```swift
struct ProcessResult { let exitCode: Int32; let stdout: Data; let stderr: Data }
protocol ProcessLauncher: Sendable {
    func run(executableURL: URL, arguments: [String], environment: [String: String],
             currentDirectory: URL, stdin: Data, timeout: Duration) async throws -> ProcessResult
}
```
- 실구현 `FoundationProcessLauncher`: `Process` + `Pipe`. **stdout/stderr는 비동기 읽기**(별도 read task)로 파이프 버퍼 deadlock 방지.
- **취소·timeout**: `withTaskCancellationHandler`로 감싸 취소 시 `process.terminate()`. timeout(기본 60s) 초과 시 terminate + `LLMProviderError.network("timeout")`.

`ClaudeCodeCLIProvider.generateText`:

- 호출: `claude -p` + `--model <설정>` + `--output-format json` + `--disallowedTools "*"` + 지원되는 CLI에서 `--no-session-persistence`. **작업지시와 userContent는 모두 stdin 전용**.
- **cwd = 전용 빈 디렉터리**(앱 지원 디렉터리 하위 `claude-cli-cwd`, 1회 생성). TMPDIR·홈 사용 금지(CLAUDE.md 미로딩 + 임시파일 혼선 회피).
- **stdin으로만** 전사·userContent 전달(argv 금지 — `ps` 노출). **임시파일 폴백 없음**: 회의 전사가 10MB(stdin 상한)를 넘는 일은 사실상 없고, 파일 경로 전달은 원문이 디스크에 잔존해 CLAUDE.md 금지값 위반. 초과 시 호출 전 잘라내고 `LLMTextResponse`에 truncation 경고.
- **자격증명**: 앱이 키를 주입하지 않는다. **Process environment에서 `ANTHROPIC_API_KEY`를 명시적으로 제거**해 "기존 `claude` 로그인 재사용"을 강제(launchd 상속 키가 조용히 과금 주체를 바꾸는 것 차단). 이 결정은 ADR Decision에 반영.
- stdout JSON 파싱 → `.result` → `LLMTextResponse`. 비정상 종료/빈 출력/미설치 → `LLMProviderError`(.unauthorized/.network/.notConfigured) 매핑. `result` 필드 부재 시 badResponse + bodyLen만 로그(원문 금지). **Claude CLI stderr 원문은 어떤 use case에서도 로그/에러에 싣지 않는다**(CLI가 프롬프트를 echo할 수 있음).
- **동시성 상한**: provider 내부에 actor 기반 직렬화 또는 `maxConcurrent=1~2` semaphore — 요약+답변 동시/연속 요청 시 Node 프로세스 폭증 방지.

> verify: 단위 테스트(mock `ProcessLauncher`) — (1) 정상 JSON 파싱, (2) exit≠0+stderr→에러, (3) 빈 stdout, (4) 경로 없음→.notConfigured, (5) **취소 시 terminate 호출됨**, (6) **stdin에만 전사 주입·argv엔 없음**(인자 검사). `swift test --filter ClaudeCodeCLIProvider`.

## Phase 3 — 경로 발견 + 연결 확인 (코드: Codex)

- CLI 경로 탐색 순서: 설정값 > `~/.claude/local/claude` > `/opt/homebrew/bin/claude` > `/usr/local/bin/claude` > npm prefix. 없으면 `.notConfigured`.
- 설정 UI(`SettingsView.swift`): `.cliPath` auth kind = "CLI 경로" 필드 + "연결 확인" 버튼. (`.buttonStyle(.borderedProminent)` 금지 — `ProminentActionButtonStyle` 사용)
- **연결 확인 = 실제 trivial 프롬프트 1회 왕복**으로 확정(`claude --version`은 인증을 검증 못 함). 설치+인증+파싱 전 스택을 확인. **Node 기동으로 수초 걸릴 수 있음** → UI 카피 "Claude Code 확인 중…(수초)" + 스피너.
- **상태머신은 기존 `isLoggedIn` 패턴(SettingsView ~line 884)과 동일 형태로** 표현(별도 상태머신 신설 금지): empty/checking/ok/fail. 실패 시 `LLMProviderError`를 기존 provider 에러 카피 패턴으로.

> verify: 미설치/미인증/정상 3상태에서 버튼 결과·에러 카피 확인. 대기 중 UI가 멈춘 듯 보이지 않는지.

## Phase 4 — 로깅·경계·실 QA (main 검증)

- **`Log.swift`에 `static let llm = Logger(...)` 카테고리 추가**(현재 없음 — CLAUDE.md "새 서브시스템은 Log.swift에 추가"). 그 후 사용.
- 로깅(`Log.llm`): 시작/성공(`provider=claudeCodeCLI`, `model=`, exit code)/실패(reason category). **전사·프롬프트·자격증명 금지**. 성공 로그에 실제 적용 model 포함. exit≠0은 모든 use case에서 raw stderr prefix를 남기지 않고, result 부재 등 2xx성 파싱 실패는 bodyLen+누락필드명만.
- 아키텍처 경계: prompt 조립·provider 선택은 use-case(`SummaryService`/`MeetingSearchAnswerUseCase`)가 소유, UI는 선택값만.
- UI에 **클라우드 전송 표시** + **ToS 고지**: `requiresWarning` 경고 문구에 "사용자 본인 기기·본인 `claude` 로그인으로 Anthropic에 전송됨. 구독 약관 확인 권장"을 포함.
- **앱 종료/창 정리 시 진행 중 Process terminate**: 종료 시그널에서 실행 중 launcher 작업 취소(좀비 방지).
- 실 QA: `./scripts/dev.sh run` → 교정 1건과 요약 1건 생성 성공, **로그에 원문 없음**(하이브리드 QA). 추가로 자동 검증으로 보완: mock launcher 호출 인자에 전사가 stdin에만 있고 argv에 없음을 단위 테스트로(Phase 2 verify #6).

> verify: `swift build`+`swift test` 통과, `git diff --check`, 수동 QA 통과.

## 미해결(구현 중 확정) — 리뷰 open questions

- `--output-format json`의 `result` 필드가 claude 버전별로 안정적인가 → 파싱은 **방어적**으로(필드 부재 시 badResponse), 지원 확인된 CLI 최소 버전을 README/설정 안내에 기록.
- `claude -p`가 로그인 사용자의 Projects 컨텍스트를 끌어오지 않는지 → 전용 빈 cwd + tool 차단으로 격리, 연결 확인 응답으로 경험적 확인.

## 리뷰 (minto-workflow)

- self-review → diff 규모에 맞춰 code-reviewer + 크로스모델 critic(provider 보안·프로세스 수명·에러 매핑 중점).
- ADR 0007은 **다중관점 리뷰 필수**(거버넌스). 리뷰 지적 반영/미반영 근거를 이 문서 또는 work-log에 남긴다.
- 병합 게이트는 사람.

## 리뷰 결과 및 후속 (2026-06-24)

구현 후 code-reviewer 크로스모델 리뷰: **COMMENT(병합 가능)** — CRITICAL 0, HIGH 2, MEDIUM 4, LOW 5.

**반영(커밋 c852b29):**
- HIGH1 — `instructions`를 `--system-prompt`(argv) 노출 → **stdin 전용**으로 이동(주제·용어집·문서 문맥이 ps 노출되는 프라이버시 결함, ADR과 일치화).
- HIGH2 — npm prefix 경로 탐색 확인 + 테스트 assertion 정정(포함 검증).
- 테스트 보강: timeout→network, 10MB truncation, instructions argv 미노출 회귀(총 11건).

**보류(미반영, 사유) — 후속 폴리시:**
- MED: stdin write 실패 `try?` 무시 로깅 / terminate() TOCTOU 단순화 / 모델 변경 시 연결확인 초기화(설계 의도일 수 있음) → 동작 정상, 위험 낮아 보류.
- LOW: `applicationWillTerminate`에도 정리 추가 / sanitizeForPublicLog 비-홈 경로 / 지원 CLI 최소버전 README 기록 → 견고성·문서 개선, 별도 후속.

**후속 변경(2026-06-25, Ultragoal G001):**
- Claude Code CLI provider 범위를 교정까지 확장하기로 계획 변경. 기존 "실시간 교정 제외" 비목표는 제거하고, 지연·rate limit은 UI 경고와 fail-soft 검증 대상으로 둔다.
- Claude CLI stderr echo는 교정·요약·답변 모두에서 prompt 문맥을 유출할 수 있으므로 raw stderr prefix 로그/에러 전파를 provider 전체에서 금지, `--no-session-persistence` 사용, `LLMProviderTests`/`LLMCorrectionService`/`ClaudeCodeCLIProvider` 회귀 테스트를 필수 게이트로 추가.

**남은 게이트(사람/사용자 환경):**
- 실 GUI QA: `./scripts/dev.sh run` → 설정에서 Claude Code CLI를 교정·요약·답변 provider로 선택 → "연결 확인" → 실제 교정 1건과 요약 1건. **확인 포인트: `claude -p`가 stdin-only 프롬프트를 읽는지(real CLI 미검증분), 로그에 전사 무유출, 클라우드 고지 표시.** 사용자의 실제 `claude` 로그인 필요 + 본인 구독으로 전송되므로 하이브리드 QA.
- ToS: 구독을 앱 백엔드로 쓰는 약관 적합성(출시 전 확인).
- main 병합(사람).

## 비목표 (이번 범위 아님)

- 새 correction 전용 provider abstraction 추가(기존 Registry capability와 `LLMCorrectionService` 경로 재사용).
- `--bare` + API 키 경로(대안 D, 기각).
- 스트리밍(`stream-json`) 출력 — 1차는 단발 JSON.
