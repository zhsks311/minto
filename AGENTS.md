# Minto2 AGENTS.md

## 프로젝트 설명

Minto2는 macOS용 회의 기록 앱이다. 실시간 전사, 전사 교정, 회의 요약, 회의 검색, 관련 문서 조회, 내보내기를 제공한다.

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
- `docs/work`: 구현 계획
- `docs/work-log`: 세션별 작업 기록
- `docs/benchmark`: benchmark 결과
- `docs/adr`: 아키텍처 결정 기록
- `Resources/designs`: Pencil 디자인 산출물
- `Resources/models`: 로컬 모델 파일 placeholder. 대용량 모델은 git에 넣지 않는다.

## 기본 명령

- 빌드: `swift build --disable-sandbox --scratch-path /tmp/minto2-build`
- 전체 테스트: `swift test --disable-sandbox --scratch-path /tmp/minto2-test`
- 특정 테스트: `swift test --disable-sandbox --scratch-path /tmp/minto2-test --filter <SuiteOrTest>`
- 앱 실행: `./scripts/dev.sh run`

SwiftPM이 sandbox 오류를 내면 `--disable-sandbox`와 `/tmp` scratch path를 먼저 사용한다.

## 작업 원칙

- 먼저 현재 코드와 문서를 읽고 작업 범위를 확인한다.
- 기존 회의 기록, 전사, 요약, 검색 흐름을 깨지 않는다.
- 기능 변경과 리팩터링을 한 커밋에 섞지 않는다.
- 새 abstraction은 실제 사용처가 있거나 가까운 Phase에서 반복 사용될 때만 만든다.
- 저장 schema 변경은 backward-compatible 하거나 migration/rollback 계획을 둔다.
- token, prompt, transcript 원문은 로그에 남기지 않는다.
- 외부 provider 호출은 timeout, auth, rate limit, malformed response를 구분한다.

## 아키텍처 경계

기본 dependency direction:

> Domain/Core <- Application/Use-case <- Infrastructure/Adapter <- UI

- Domain/Core는 HTTP, Keychain, UserDefaults, 파일 IO에 직접 의존하지 않는다.
- Application/Use-case는 workflow, retry, timeout, idempotency를 소유한다.
- Infrastructure/Adapter는 LLM provider, Confluence, Keychain, 파일 변환 같은 구체 구현을 담당한다.
- UI는 prompt 생성, provider request 조립, 저장 schema 변환을 직접 하지 않는다.

## ADR 필요 조건

다음 변경은 `docs/adr/`에 ADR을 작성한다.

- 새 외부 dependency 또는 저장소 도입
- provider adapter, pipeline, job runner 같은 공유 core abstraction 추가
- 실행 모델 변경
- 저장 schema, embedding index, export contract의 비호환 변경
- 개인정보가 외부 provider로 나가는 범위 변경
- domain/application/infrastructure/UI 책임 경계 변경

## UI/UX 컨벤션

- 사용자는 심플함과 사용 편의성을 선호한다.
- Toss식 원칙을 Minto에 맞게 적용한다: 좋은 기본값, 단계적 공개, 명확한 상태, 낮은 인지 부하.
- 3단계 이상 flow, 4개 이상 상태, mental model 변화가 있는 UI는 Pencil로 먼저 설계한다.
- Pencil `.pen`과 export 이미지는 `Resources/designs/`에 저장한다.
- 설정 화면은 모든 고급 설정을 한 번에 드러내지 않는다.
- 클라우드 전송 여부와 로컬 처리 여부를 명확히 구분한다.

## 문서/로그 컨벤션

- 복잡한 작업은 구현 전에 `docs/work/`에 계획을 작성한다.
- 작업 완료 또는 의미 있는 중간 결과는 `docs/work-log/`에 남기고 `docs/work-log.md` 인덱스를 업데이트한다.
- benchmark는 `docs/benchmark/`에 기록한다.
- 코드 리뷰/QA 증거는 작업 로그 또는 별도 보고서에 남긴다.
- 기능 정의는 `docs/service-definition.md`를 최신 상태로 유지한다.

## 검증 게이트

기본 완료 전 확인:

- `git diff --check`
- `swift build --disable-sandbox --scratch-path /tmp/minto2-build`
- 관련 테스트 또는 `swift test --disable-sandbox --scratch-path /tmp/minto2-test`

UI 변경:

- 앱 실행 후 화면 확인
- 상태: empty, loading, success, error, disabled 확인
- 텍스트 선택/복사, 탭, 버튼 hit area 확인

LLM/검색/내보내기 변경:

- provider 없음/미로그인/토큰 오류/네트워크 오류 테스트
- 로그에 민감정보가 없는지 확인
- export 결과에 요약, 회의 내용 정리, 결정사항, 할 일, 미해결 질문, 전사가 누락되지 않는지 확인

## 코드리뷰 규칙

- self-review를 먼저 한다.
- 변경 scope에 맞는 reviewer 또는 agent 리뷰를 받는다.
- 리뷰 지적을 반영하거나 반영하지 않는 이유를 작업 로그/ADR에 남긴다.
- 아키텍처 경계를 넘는 변경은 다중 관점 리뷰를 통과해야 한다.
