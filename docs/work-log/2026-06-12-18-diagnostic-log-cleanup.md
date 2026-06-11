# 진단 로그 정비

## 요약

OAuth 계정 교정, 검색 답변, 설정 변경 경로의 진단 로그를 정비했다. 비-200 서버 에러 본문은 prefix만 남기고, 정상 응답 본문과 질문/답변/전사/프롬프트 원문은 로그하지 않는다.

## 변경 사항

- Codex/Gemini/Copilot 계정 교정 성공 로그에 실제 사용 모델과 출력 글자 수를 추가했다.
- Codex/Gemini/Copilot의 HTTP 실패 로그에서 `bodyLen`만 남기던 지점을 서버 에러 body prefix로 바꿨다.
- Gemini HTTP 200 파싱 실패는 정상 응답 본문 유출을 막기 위해 `bodyLen`과 누락 필드 reason만 기록한다.
- Copilot 교정 HTTP 실패 경로에 누락돼 있던 에러 로그를 추가했다.
- 별칭 프리필 실패 로그를 `.debug`에서 `.error`로 올렸다.
- 검색 답변 생성 성공/실패 로그를 `Log.search`에 추가했다.
- Settings의 provider/model AppStorage 변경을 `Log.app.info`로 기록한다.
- 코드 리뷰 후 검색 답변 guard 실패 로그, `lastLLMProvider` 동기화 주석, OAuth body prefix 정리, Copilot 200 파싱 실패 reason 로그를 보완했다.

## 민감정보 기준

- 비-200 서버 에러 body prefix만 로그한다.
- 정상 응답 본문, 전사, 프롬프트, 검색어, 질문, 답변, 토큰, API 키는 로그하지 않는다.
- 모델 ID, provider ID, HTTP status, 출력 글자 수, 에러 설명만 `.public`으로 기록한다.

## 검증

- `git diff --check` 통과
- `./scripts/dev.sh build` 통과
- `./scripts/dev.sh test` 통과: 451 tests, 64 suites

## 주의

- 빌드/테스트 중 기존 warning이 표시됐지만 이번 로그 정비 범위 밖이라 수정하지 않았다.
