# Phase 1a 첨부 문서 용어 직접 주입 구현 계획

## 목표

- 첨부 문서에서 정적으로 추출한 용어를 교정, 요약, 재요약 프롬프트의 용어집 입력에 직접 병합한다.
- GlossaryStore 큐레이션과 STT 바이어싱은 건드리지 않는다.
- 문서 용어와 본문은 로그나 저장용 summaryGlossary에 새지 않게 한다.

## 변경 범위

1. `DocumentTermExtractor` 신규 추가
   - ASCII/약어/숫자-하이픈 토큰은 정규식으로 추출한다.
   - 한국어 토큰은 `NLTokenizer(.word)`와 `NLTagger(.lexicalClass)`의 noun만 사용한다.
   - stopword, 기존 용어 dedup, 빈도 우선/첫 등장 순 안정 정렬, limit 절단을 적용한다.
2. `MeetingContext` 변경
   - `documentTerms`를 세션 ephemeral 상태로 추가한다.
   - `start()`에서 즉시 초기화 후 `Task.detached`로 문서 용어를 추출하고 MainActor에 반영한다.
   - `glossaryForPrompt`는 사용자 glossary와 이미 추출된 documentTerms를 줄 단위로 병합한다.
3. 프롬프트 주입 지점 변경
   - live 교정 편의 오버로드와 live 증분/최종 요약만 `glossaryForPrompt`를 사용한다.
   - 재요약은 프롬프트 context에만 문서 용어 병합본을 넣고 저장 snapshot은 기존 normalized glossary를 유지한다.
4. 테스트 추가
   - 추출, stopword, ranking, dedup, limit, fail-soft, merge, determinism을 Swift Testing으로 검증한다.

## 검증 기준

- `git diff --check`
- `swift build --disable-sandbox --scratch-path /tmp/minto2-build`
- `swift test --disable-sandbox --scratch-path /tmp/minto2-test --filter DocumentTermExtractor`
- `swift test --disable-sandbox --scratch-path /tmp/minto2-test --filter Correction`
- `swift test --disable-sandbox --scratch-path /tmp/minto2-test --filter Summary`
