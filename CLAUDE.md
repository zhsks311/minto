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
- UI에서 provider request, prompt, 저장 schema 변환을 직접 하지 않는다.
- token, prompt, transcript 원문을 로그로 남기지 않는다.
- 실패는 fail-soft를 우선한다. 요약/교정 실패가 저장/전사를 망치면 안 된다.

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
- 복잡한 화면은 Pencil로 설계하고 `Resources/designs/`에 저장한다.
- `.buttonStyle(.borderedProminent)` 금지: 비활성(non-key) 윈도우에서 강조 배경이 사라져 흰 라벨만 남는다(macOS 기본 동작이지만 이 앱은 다른 창과 나란히 쓰는 대시보드형이라 부적합). 강조 버튼은 MeetingLibraryView의 `ProminentActionButtonStyle`처럼 배경을 직접 그리는 스타일을 쓴다.

## 문서 산출물

- 구현 계획: `docs/work/`
- 세션 로그: `docs/work-log/`
- benchmark 결과: `docs/benchmark/`
- ADR: `docs/adr/`
- 기능 정의: `docs/service-definition.md`
- Pencil 결과물: `Resources/designs/`

## 검증 명령

기본:

- `git diff --check`
- `swift build --disable-sandbox --scratch-path /tmp/minto2-build`
- `swift test --disable-sandbox --scratch-path /tmp/minto2-test`

관련 테스트만 먼저 돌릴 때:

- `swift test --disable-sandbox --scratch-path /tmp/minto2-test --filter <SuiteOrTest>`

## 코드리뷰

각 구현 단위는 다음을 확인한다.

- 계획 Phase와 연결되어 있는가
- 기존 동작 회귀가 없는가
- 테스트가 변경 범위를 커버하는가
- 민감정보가 로그에 남지 않는가
- UI 상태가 empty/loading/success/error/disabled를 가진가
- 문서와 작업 로그가 업데이트되었는가

아키텍처 경계를 넘는 변경은 ADR과 다중 관점 리뷰가 필요하다.
