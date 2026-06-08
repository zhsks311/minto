# ADR 0001: LLM/Search/Export 확장 아키텍처 거버넌스

상태: Accepted
작성일: 2026-06-09

## Context

Minto2는 기존 실시간 전사 앱에서 전사 교정, 요약, 용어집, 검색, 임베딩, Confluence 내보내기, 파일 입력, 시스템 사운드 입력까지 확장될 예정이다.

이 확장은 provider, 저장소, 입력 소스, UI 설정, 외부 API가 동시에 늘어나므로 구조가 쉽게 복잡해진다. 유지보수가 쉬운 구조를 위해 기능 구현 전에 경계와 리뷰 게이트를 고정한다.

## Decision

다음 dependency direction을 기본 경계로 둔다.

> Domain/Core <- Application/Use-case <- Infrastructure/Adapter <- UI

- Domain/Core는 순수 규칙을 소유하고 IO에 의존하지 않는다.
- Application/Use-case는 workflow, retry, timeout, idempotency를 소유한다.
- Infrastructure/Adapter는 LLM provider, Confluence, Keychain, 파일 변환, embedding backend를 구현한다.
- UI는 상태 표시와 명령 전달에 집중한다.

아키텍처 경계를 넘는 변경은 ADR과 다중 관점 리뷰를 통과해야 한다.

## Alternatives

- 현재 서비스 파일 중심 구조를 그대로 확장
  - 장점: 빠르게 구현 가능
  - 단점: LLM, 검색, export, Keychain, UI 상태가 서로 엉키기 쉽다.
  - 기각 이유: 기능 수가 크게 늘어 장기 유지보수 비용이 커진다.
- Clean Architecture식 대규모 재구성
  - 장점: 경계가 명확하다.
  - 단점: 현재 기능 구현보다 리팩터링 비용이 커지고 회귀 위험이 높다.
  - 기각 이유: 사용자가 요구한 기능 진척보다 구조 작업이 앞설 수 있다.
- 점진적 경계 도입
  - 장점: 필요한 곳부터 경계를 만든다.
  - 단점: 초기에 일관성을 계속 점검해야 한다.
  - 선택 이유: 현재 앱을 흔들지 않고 확장 구조를 만들 수 있다.

## Consequences

### Positive

- Provider와 UI가 직접 결합되는 것을 줄인다.
- 검색, 교정, 요약, export를 각각 테스트 가능한 단위로 나눌 수 있다.
- 아키텍처 변경이 문서와 리뷰를 거쳐 결정된다.

### Negative

- 초기 구현 속도는 일부 느려진다.
- ADR과 리뷰 작성 비용이 생긴다.
- 작은 변경도 경계 판단이 필요할 수 있다.

## Migration

기존 `LLMCorrectionService`, `SummaryService`, `MeetingStore`, `MeetingExporter`, `ConfluenceService`는 바로 삭제하지 않는다.

1. 새 interface와 adapter를 추가한다.
2. 기존 서비스는 점진적으로 adapter 뒤로 이동한다.
3. 기존 저장 JSON은 backward-compatible 하게 유지한다.
4. UI는 기존 흐름을 유지하면서 설정을 단계적으로 분리한다.

## Rollback

- 새 adapter를 끄고 기존 provider 경로를 유지한다.
- 저장 schema 변경은 optional field로만 시작한다.
- Confluence publish, embedding index, file import, system audio는 feature 단위로 되돌릴 수 있게 분리한다.

## Verification

- `git diff --check`
- `swift build --disable-sandbox --scratch-path /tmp/minto2-build`
- `swift test --disable-sandbox --scratch-path /tmp/minto2-test`
- Phase별 관련 테스트
- UI 변경은 앱 실행 QA
- benchmark가 필요한 모델/검색 변경은 `docs/benchmark/`에 기록
