# 별칭 자동 수집 리뷰 반영

## 요약

`feat/alias-auto-collect`의 별칭 자동 수집 리뷰 지적을 반영했다. 핵심은 dismiss한 alias 제안의 재삽입 차단, 한영 혼재 alias 추출 거부, LLM alias 프리필의 작은 출력 예산과 응답 방어, UI 프리필 덮어쓰기 방지다.

## 변경 사항

- `GlossarySnapshot.dismissedAliasKeys`를 추가했다.
  - 기존 schemaVersion 1 snapshot은 `try? decode` 기본값으로 하위 호환 로드한다.
  - key 형식은 `entryID|aliasFolded`다.
  - 200개 상한을 두고 초과 시 오래된 key를 제거한다.
  - `mergeCorrectionAliases`는 dismissed key와 일치하는 기존 entry alias 제안을 다시 넣지 않는다.
- `CorrectionAliasExtractor`의 alias 가드를 강화했다.
  - alias가 한글 alias로 통과하려면 구두점/기호 제거 뒤 한글과 공백만 남아야 한다.
  - `liqui base` -> `Liquibase` 같은 영문 분절 접합 예외는 유지했다.
- alias LLM 프리필 요청/응답을 줄였다.
  - `LLMTextRequest.maxOutputTokens` override를 추가했다.
  - API key, local, account provider 경로가 override를 사용한다.
  - alias 프리필은 `maxOutputTokens: 64`를 지정한다.
  - 괄호와 라틴이 섞인 응답에서는 한글 토큰만 추출한다.
- 설정 UI의 후보 프리필을 보수화했다.
  - `candidate.suggestedAliases`는 별칭 입력 필드가 비어 있을 때만 채운다.
  - 요약 설정 provider 경로를 쓰는 이유와 alias 승인 후 collapse 순서 의도를 주석으로 남겼다.
- 전체 테스트 중 반복 실패하던 기존 VAD reset 테스트는 제품 코드 변경 없이 callback 대기 방식을 `AsyncStream`으로 바꿔 병렬 전체 실행에서 안정화했다.

## 검증

- `./scripts/dev.sh build` 통과
- `./scripts/dev.sh test` 통과: 406 tests, 58 suites

## 주의

- 앱 실행은 요청에 따라 수행하지 않았다.
- 첫 전체 테스트 2회는 기존 `VADProcessorTests.reset 후 ramp-up 재적용`의 fixed sleep 대기 문제로 실패했다. 단독 실행은 통과했고, 테스트 대기 방식을 수정한 뒤 전체 테스트가 통과했다.
