# 2026-06-12 진단 로그 정비 계획

## 목표

- OAuth/API 실패 로그에서 `bodyLen`만 남는 지점을 비-200 서버 에러 본문 prefix로 바꿔 원인 진단 가능성을 높인다.
- 정상 응답 본문, 전사, 프롬프트, 검색어, 토큰 원문은 로그에 남기지 않는다.
- 교정 성공, 검색 답변 성공/실패, 설정 변경 로그를 추가해 모델/provider 적용 여부를 추적한다.
- 지정 범위 밖 코드는 수정하지 않는다.

## 작업 단계

1. OAuth/교정 로그 정비
   - Gemini/Copilot/Codex 비-200 실패 로그에 `body` prefix를 남긴다.
   - Gemini HTTP 200 파싱 실패는 본문 없이 `bodyLen`과 누락 필드 힌트만 남긴다.
   - OAuth 3종 교정 성공 로그에 모델과 출력 글자 수를 남긴다.
   - 검증: 정상 응답 본문을 로그하지 않는지 diff로 확인한다.

2. 보조 기능 로그 정비
   - `GlossaryAliasPrefillService` 실패 로그를 `.error`로 올린다.
   - `MeetingSearchAnswerService`에 SummaryService 패턴의 성공/실패 로그를 추가한다.
   - 검증: 질문/답변 원문이 로그 문자열에 들어가지 않는지 확인한다.

3. Settings 모델/provider 변경 로그
   - `lastLLMProvider`와 지정 모델 키 변경을 `onChange(of:)`로 기록한다.
   - `.public` 값은 key, old, new에 한정한다.
   - 검증: 기존 provider 동기화 부작용은 유지하고 로깅만 추가한다.

4. 문서, 검증, 커밋
   - `docs/work-log/2026-06-12-18-diagnostic-log-cleanup.md`와 인덱스 18행을 추가한다.
   - `git diff --check`
   - `./scripts/dev.sh build`
   - `./scripts/dev.sh test`
   - 한국어 `feat:` 또는 `fix:` 커밋을 만든다.

## 진행 상태

- 계획 작성: 완료
- 구현: 완료
- 검증: 완료
- 커밋: 완료
