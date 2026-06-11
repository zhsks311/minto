# 별칭 자동 수집 리뷰 반영 계획

## 목표

`feat/alias-auto-collect` 직전 4커밋의 코드리뷰 지적을 반영해 별칭 제안의 재삽입, 혼재 alias 추출, LLM 프리필 예산/파싱, UI 프리필 덮어쓰기를 막는다.

## 제약

- 앱 실행 금지.
- 검증은 `./scripts/dev.sh build`와 `./scripts/dev.sh test`만 사용한다.
- 1~2개 커밋으로 정리한다.
- 커밋 메시지에 `Co-Authored-By`를 넣지 않는다.

## 단계별 검증 기준

1. dismissed alias 영속화
   - `GlossarySnapshot.dismissedAliasKeys`를 하위 호환 decode로 추가한다.
   - `dismissAliasSuggestion`은 `entryID|aliasFolded` 키를 저장하고 200개 상한을 유지한다.
   - `mergeCorrectionAliases`는 dismissed key를 가진 기존 entry alias 제안을 다시 넣지 않는다.
   - 검증: dismiss 후 동일 쌍 재유입 차단, reload 후에도 차단, 상한 200 테스트.

2. 추출 가드 강화
   - alias가 한글 alias로 통과하려면 구두점/기호 제거 후 한글과 공백만 남아야 한다.
   - `liqui base` -> `Liquibase` 분절 영문 접합 예외는 유지한다.
   - 검증: `AWS 람다` 같은 한영 혼재 alias 거부 테스트.

3. LLM 프리필 요청/응답 방어
   - `LLMTextRequest`에 request별 `maxOutputTokens` override를 추가한다.
   - API key, 로컬, 계정 provider가 override를 사용하도록 연결한다.
   - alias 프리필 요청은 `maxOutputTokens: 64`를 지정한다.
   - 응답 파싱은 괄호/라틴 혼재 응답에서 한글 토큰만 추출한다.
   - 검증: prefill request와 parser 테스트, provider payload override 테스트.

4. UI 프리필 덮어쓰기 방지와 주석
   - 후보 `suggestedAliases`는 별칭 입력 필드가 비어 있을 때만 채운다.
   - provider resolver가 요약 설정 provider를 쓰는 이유를 주석으로 남긴다.
   - `approveAliasSuggestion` 직후 collapse 순서 의도를 주석으로 남긴다.
   - 검증: build로 SwiftUI 컴파일 확인.

## 완료 검증

- `./scripts/dev.sh build`
- `./scripts/dev.sh test`

## 결과

- 구현 완료.
- `./scripts/dev.sh build` 통과.
- `./scripts/dev.sh test` 통과: 406 tests, 58 suites.
- 앱 실행은 수행하지 않음.
