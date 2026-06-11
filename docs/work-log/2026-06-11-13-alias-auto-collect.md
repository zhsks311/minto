# 용어집 별칭 자동 수집

## 요약

전사 교정 결과의 원문/교정문 차이를 이용해 용어집 별칭 후보를 자동 수집하되, 자동 등록은 하지 않고 설정 화면에서 사용자가 직접 승인하도록 구현했다.

## 변경 사항

- `CorrectionAliasExtractor` 추가
  - 공백 토큰화와 LCS 기반 diff로 치환 구간만 추출한다.
  - 원문 쪽은 alias, 교정문 쪽은 canonical로 해석한다.
  - 1~3토큰 치환만 허용하고, 어순 변경/삽입/삭제/대규모 재작성은 버린다.
  - 기본은 한글↔영문/숫자 교차만 허용한다.
  - `liqui base` → `Liquibase`처럼 영숫자 다토큰 분절이 접합 동일한 경우만 예외 허용한다.
- `LLMCorrectionService.correct` 성공 후 alias 추출을 실행하고 `GlossaryStore`에 전달한다.
  - 로그에는 추출 쌍 개수만 남긴다.
- `GlossaryStore`에 `pendingAliases`와 `GlossaryAliasSuggestion`을 추가했다.
  - 기존 entry에 매칭되면 alias 제안으로 축적한다.
  - 기존 entry가 없으면 `GlossaryCandidate.suggestedAliases`에 함께 축적한다.
  - snapshot은 새 필드를 `try? decode` + 기본값으로 하위 호환 로드한다.
  - `approveAliasSuggestion` / `dismissAliasSuggestion`은 사용자 클릭 경로에서만 동작한다.
- 설정 UI에 alias 제안을 노출했다.
  - 제안된 용어 행에 `오인식: ...`를 표시한다.
  - 후보 `[추가]`는 등록 폼 alias 필드를 제안 alias로 프리필한다.
  - 기존 용어 행은 `별칭 제안 N` 배지로 제안 목록을 펼치고, 각 제안에 `[추가]` / `[무시]`를 제공한다.
- 후보 alias가 비어 있을 때만 백그라운드 LLM 프리필을 1회 실행한다.
  - provider는 요약 설정의 text generation provider를 재사용한다.
  - 프롬프트에는 후보 용어만 넣고 회의 내용/전사/문맥은 넣지 않는다.
  - 실패/지연/사용자 입력 시작 시 빈 필드 또는 사용자 입력을 유지한다.

## 커밋 단위

- 커밋 1: `feat: extract correction alias candidates`
- 커밋 2: `feat: collect correction alias suggestions`
- 커밋 3: `feat: show glossary alias suggestions`
- 커밋 4: `feat: prefill glossary aliases with llm`

## 검증

- 커밋 1 전:
  - `./scripts/dev.sh test CorrectionAliasExtractorTests` 통과: 5 tests
  - `git diff --check` 통과
  - `./scripts/dev.sh build` 통과
  - `./scripts/dev.sh test` 재실행 통과: 389 tests
- 커밋 2 전:
  - `./scripts/dev.sh test GlossaryStoreTests` 통과: 33 tests
  - `git diff --check` 통과
  - `./scripts/dev.sh build` 통과
  - `./scripts/dev.sh test` 통과: 397 tests
- 커밋 3 전:
  - `./scripts/dev.sh build` 통과
  - `git diff --check` 통과
  - `./scripts/dev.sh build` 통과
  - `./scripts/dev.sh test` 통과: 397 tests
- 커밋 4 전:
  - `./scripts/dev.sh test GlossaryAliasPrefillServiceTests` 통과: 4 tests
  - `git diff --check` 통과
  - `./scripts/dev.sh build` 통과
  - `./scripts/dev.sh test` 통과: 401 tests

## 주의

- 앱 실행은 요청에 따라 수행하지 않았다.
- 모든 LLM/교정 로그는 용어/전사 원문을 남기지 않고 개수, 길이, provider id, 에러 설명만 기록한다.
