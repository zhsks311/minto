# Minto2 CLAUDE.md

이 파일은 Claude와 Codex가 공유하는 프로젝트별 작업 기준이다.

## 응답/협업 방식

- 한국어로 답한다.
- 구현 전 현재 파일과 상태를 먼저 확인한다.
- 완료, 진행 중, 제안을 섞어 말하지 않는다.
- 사용자가 품질을 물으면 실제 근거, 테스트, 파일 경로를 제시한다.
- STT 품질과 회의록 가독성은 분리해서 판단한다.

## 프로젝트 목적

Minto2는 macOS 회의 기록 앱이다.

- 회의 중 음성을 전사한다.
- 전사를 문맥에 맞게 교정한다.
- 회의 내용을 요약/구조화한다.
- 저장된 회의를 검색한다.
- 업무 문서와 연결하고 내보낸다.

자세한 기능 정의는 `docs/service-definition.md`를 본다.

## 기술 스택

- Swift 6
- SwiftUI + AppKit
- Swift Package Manager
- WhisperKit
- FluidAudio
- MCP Swift SDK
- macOS 14 이상

## 주요 경로

- `Sources/Minto/App`: 앱 lifecycle과 window orchestration
- `Sources/Minto/Models`: 저장/표시용 domain model
- `Sources/Minto/Services`: STT, LLM, 저장, 외부 연동, export service
- `Sources/Minto/UI`: SwiftUI 화면
- `Sources/Minto/ViewModels`: recording/transcription state orchestration
- `Tests/MintoTests`: 단위/통합 테스트
- `Resources/models`: 로컬 모델 파일 placeholder. 대용량 모델은 git에 넣지 않는다.
- 문서 경로는 아래 "문서 산출물" 참조.

## 작업 전 확인 순서

1. `git status --short`
2. 관련 계획: `docs/work/`
3. 관련 작업 로그: `docs/work-log.md`, `docs/work-log/`
4. 관련 코드와 테스트
5. 필요한 경우 ADR: `docs/adr/`

## 구현 원칙

- 작은 커밋을 유지한다.
- 계획에 없는 주변 리팩터링을 하지 않는다.
- 새 추상화는 실제 반복을 줄일 때만 만든다.
- 기능 변경과 리팩터링을 한 커밋에 섞지 않는다.
- UI에서 provider request, prompt, 저장 schema 변환을 직접 하지 않는다.
- 외부 provider 호출은 timeout, auth, rate limit, malformed response를 구분한다.
- 저장 schema 변경은 backward-compatible 하거나 migration/rollback 계획을 둔다.
- token, prompt, transcript 원문을 로그로 남기지 않는다.
- 실패는 fail-soft를 우선한다. 요약/교정 실패가 저장/전사를 망치면 안 된다.

## 아키텍처 경계

기본 dependency direction:

> Domain/Core ← Application/Use-case ← Infrastructure/Adapter ← UI

- Domain/Core는 HTTP, Keychain, UserDefaults, 파일 IO에 직접 의존하지 않는다.
- Application/Use-case는 workflow, retry, timeout, idempotency를 소유한다.
- Infrastructure/Adapter는 LLM provider, Confluence, Keychain, 파일 변환 같은 구체 구현을 담당한다.
- UI는 prompt 생성, provider request 조립, 저장 schema 변환을 직접 하지 않는다.

## ADR 필요 조건

다음 변경은 `docs/adr/`에 ADR을 작성하고 다중 관점 리뷰를 통과해야 한다.

- 새 외부 dependency 또는 저장소 도입
- provider adapter, pipeline, job runner 같은 공유 core abstraction 추가
- 실행 모델 변경
- 저장 schema, embedding index, export contract의 비호환 변경
- 개인정보가 외부 provider로 나가는 범위 변경
- domain/application/infrastructure/UI 책임 경계 변경

## 기능별 기준

### 전사

- preview와 final transcript의 역할을 구분한다.
- 녹음 종료 시 남은 VAD buffer와 마지막 교정이 누락되지 않아야 한다.
- CER 개선과 읽기 좋은 회의록 개선을 같은 지표로 말하지 않는다.

### 교정/요약

- 교정과 요약 설정은 독립적으로 동작해야 한다.
- 교정이 꺼져도 원문 전사 기반 요약은 가능해야 한다.
- 회의 주제, 용어집, 문서 문맥은 지시가 아니라 참고자료로 prompt에 들어간다.
- LLM이 입력에 없는 내용을 만들지 않도록 prompt와 테스트를 유지한다.

### 용어집

- 전역 기본 용어집과 회의별 용어집을 함께 고려한다.
- 전체 용어집을 항상 LLM에 넣지 않는다.
- 관련 용어만 제한된 개수로 선별한다.
- 저장된 회의에서 발견한 후보는 자동 등록하지 않고 사용자에게 제안한다.

### 검색

- 일반 검색은 LLM 없이도 유용해야 한다.
- LLM 답변 생성은 검색과 분리된 명령으로 둔다.
- 답변에는 근거 회의, 섹션, 시간이 표시되어야 한다.

### 내보내기

- Markdown export는 기본 fallback으로 유지한다.
- Confluence export는 token 없을 때 비활성화하고 설정으로 안내한다.
- publish 전에 위치와 제목을 확인한다.

### UI

- 심플함과 사용 편의성을 우선한다.
- 설정은 단계적으로 펼친다.
- Toss식 원칙을 적용한다: 좋은 기본값, 명확한 상태, 쉬운 다음 행동.
- 3단계 이상 flow, 4개 이상 상태, mental model 변화가 있는 화면은 Pencil로 먼저 설계하고 `.pen`과 export 이미지를 `Resources/designs/`에 저장한다.
- 클라우드 전송 여부와 로컬 처리 여부를 명확히 구분해 보여준다.
- `.buttonStyle(.borderedProminent)` 금지: 비활성(non-key) 윈도우에서 강조 배경이 사라져 흰 라벨만 남는다(macOS 기본 동작이지만 이 앱은 다른 창과 나란히 쓰는 대시보드형이라 부적합). 강조 버튼은 MeetingLibraryView의 `ProminentActionButtonStyle`처럼 배경을 직접 그리는 스타일을 쓴다.

### 이벤트 로깅

배포 후 사용자의 "안 돼요" 보고를 로그만으로 추적할 수 있어야 한다.

- 로그는 `Log.<category>`(`Sources/Minto/Services/Log.swift`, os.Logger)만 쓴다. `print`/`fputs`/`NSLog` 금지 — stderr는 배포 바이너리에서 전량 소실된다. 카테고리(app, stt, vad, audio, correction, summary, store, search, importer, oauth, report 등)는 Log.swift를 따르고, 새 서브시스템이 생기면 Log.swift에 추가한다.
- 사용자 동작 단위 기능(녹음, 임포트, 교정, 요약, 답변 생성, 저장, 내보내기, 연동)을 추가/수정하면 **시작·성공·실패 로그를 함께** 추가한다. 실패만 로깅하면 "어디까지 진행됐는지"를 알 수 없다.
- **결정과 설정도 이벤트다**: 동작을 바꾸는 설정 변경(모델/provider 선택)과 런타임 결정(모델 폴백, provider 라우팅)을 기록하고, 성공 로그에 실제 적용된 값(`model=` 등)을 포함한다 — "설정이 반영됐는지"를 로그만으로 확인할 수 있어야 한다.
- **실패 로그에는 판별 증거를 남긴다**: HTTP 실패는 status + **에러 응답 본문 prefix(200자)**. 에러 본문은 서버 거부 사유라 민감값이 아니며, `bodyLen` 같은 메타데이터만 남기면 사유 구분이 안 돼 진단이 늦어진다(실사례: "모델 미지원 vs 파라미터 미지원" 모두 400). status code만으로 에러를 분류하지 말고 본문 사유로 구분한다.
- 레벨: 흐름 추적 = `.info`, 실패 = `.error`, 고빈도 내부 진단 = `.debug`(배포에서 디스크 영속이 보장되지 않음 — 핵심 이벤트에 쓰지 않는다). **fail-soft 기능(실패가 화면에 안 보이는 기능)의 실패는 반드시 `.error`** — 로그가 유일한 관측 수단이다(실사례: 별칭 프리필 실패가 `.debug`라 수개월 침묵).
- **금지 값**: 전사·요약·주제·검색어·용어집 내용·문서 문맥·프롬프트·토큰/키·**정상(2xx) API 응답 body 원문**(교정/요약 결과가 들어 있다 — 2xx 파싱 실패는 bodyLen + 누락 필드명만 기록)·홈 디렉터리가 포함된 절대경로. **허용 값**: 글자 수/개수/길이, enum 케이스명, provider/모델/엔진 식별자, HTTP status, 비-2xx 에러 응답 본문 prefix, `lastPathComponent`, 에러 설명(localizedDescription).
- privacy 마스킹을 안전장치로 믿지 않는다 — 설정의 "진단 로그 내보내기"가 같은 프로세스의 `composedMessage`(마스킹 미적용 원문)를 파일로 쓴다. 안전은 "민감값을 아예 넣지 않기"에서만 나온다. 비민감 값은 `privacy: .public`을 명시한다(누락 시 `<private>`로 가려져 진단 가치를 잃는다).

## 문서 산출물

- 구현 계획: `docs/work/`
- 세션 로그: `docs/work-log/`
- benchmark 결과: `docs/benchmark/`
- ADR: `docs/adr/`
- 기능 정의: `docs/service-definition.md`
- Pencil 결과물: `Resources/designs/`

## 로컬 빌드·실행·서명 (dev.sh)

앱을 **실제로 띄워서** 동작(OAuth, Keychain 토큰 접근 등)을 확인할 때는 `scripts/dev.sh`를 쓴다. 아래 "검증 명령"의 raw `swift build/test`는 *컴파일·테스트 통과 확인*용이고, dev.sh는 *앱 실행*을 위한 안정 서명 경로다 — 역할이 다르다.

```bash
./scripts/dev.sh run            # 빌드 + 서명 + 실행
./scripts/dev.sh build          # 빌드 + 서명
./scripts/dev.sh test [필터]    # 테스트 빌드 + 서명 + 실행
./scripts/dev.sh sign           # 현재 산출물 재서명
```

- **`swift run` 금지.** SPM이 실행 직전 adhoc 서명을 덮어써 Keychain ACL이 깨지고 매 실행 권한창이 뜬다. 반드시 `./scripts/dev.sh run`.
- **코드서명 인증서 "Minto2 Dev" 필요** (자가서명 Code Signing). 없으면 dev.sh가 안내하며 중단한다. 생성법은 `README.md`. (`MINTO_SIGN_IDENTITY`로 이름 변경 가능)
- **`Minto.entitlements`의 `cs.disable-library-validation` / `cs.allow-jit`는 Metal 셰이더(WhisperKit) 로딩에 필요**하다. 함부로 제거하면 STT가 깨진다.
- **STT 모델은 첫 실행 시 다운로드**된다(WhisperKit). 오프라인 사전배치는 `WHISPER_MODEL_FOLDER` 환경변수.
- **병렬 워크트리 함정**: 회의 데이터(`~/Library/Application Support/Minto/meetings`)는 **모든 워크트리가 공유**한다 — 화면에 시드 데이터가 보여도 "올바른 빌드를 실행 중"이라는 보장이 아니다. 또 `cd X && (./scripts/dev.sh run &)`는 `cd`가 백그라운드 서브셸에 안 먹혀 **엉뚱한 워크트리 바이너리**를 띄운다. 워크트리별 검증은 절대경로 바이너리를 직접 exec하고, 의심되면 `lsof -a -p <pid> -d cwd`로 실행 cwd를 확인한다.

## 검증 명령

기본:

- `git diff --check`
- `swift build --disable-sandbox --scratch-path /tmp/minto2-build`
- `swift test --disable-sandbox --scratch-path /tmp/minto2-test`

관련 테스트만 먼저 돌릴 때:

- `swift test --disable-sandbox --scratch-path /tmp/minto2-test --filter <SuiteOrTest>`

UI 변경:

- 앱 실행 후 화면 확인
- 상태: empty, loading, success, error, disabled 확인
- 텍스트 선택/복사, 탭, 버튼 hit area 확인

LLM/검색/내보내기 변경:

- provider 없음/미로그인/토큰 오류/네트워크 오류 테스트
- 로그에 민감정보가 없는지 확인
- export 결과에 요약, 회의 내용 정리, 결정사항, 할 일, 미해결 질문, 전사가 누락되지 않는지 확인

## 코드리뷰

각 구현 단위는 다음을 확인한다.

- 계획 Phase와 연결되어 있는가
- 기존 동작 회귀가 없는가
- 테스트가 변경 범위를 커버하는가
- 민감정보가 로그에 남지 않는가
- UI 상태가 empty/loading/success/error/disabled를 가진가
- 문서와 작업 로그가 업데이트되었는가

리뷰 절차:

- self-review를 먼저 한다.
- 변경 scope에 맞는 reviewer 또는 agent 리뷰를 받는다.
- 리뷰 지적을 반영하거나 반영하지 않는 이유를 작업 로그/ADR에 남긴다.
- 아키텍처 경계를 넘는 변경은 "ADR 필요 조건"에 따라 ADR과 다중 관점 리뷰를 통과해야 한다.
