# Confluence 연결 설정 UX 개선

## 요약

- Confluence 설정 입력을 저장값과 분리하고, 실제 인증 확인 성공 후에만 연동 저장되도록 바꿨다.
- 회의 시작 시트의 Confluence 조회 결과를 0건, 인증 거부, 네트워크 실패로 구분한다.
- 사이트 URL, 이메일, API token 입력창에 rounded border와 높이를 적용해 클릭 영역을 넓혔다.

## 변경

- `ConfluenceService`
  - `validateCredentials(baseURL:email:token:)` 추가
  - `/wiki/rest/api/user/current` Basic 인증 검증
  - 401/403/network/invalid URL outcome 분리
  - `searchContext`를 `ContextSearchResult`로 변경해 문서와 실패 사유를 함께 반환
  - 검색 403도 401처럼 `needsReconnect`로 마킹
- `SettingsView`
  - Confluence URL/email을 로컬 입력 상태로 분리
  - `[연결 확인]` 성공 후 `[연동]`만 활성화
  - 입력 변경 시 검증 상태 무효화
  - 이메일 `@` 누락 인라인 경고 추가
  - 저장된 token이 있으면 token 입력 없이도 검증 허용
- `MeetingSetupView`
  - 0건, 인증 거부, 네트워크 실패 메시지 분리
  - 인증 거부는 orange, 네트워크 실패는 red 상태로 표시
- 테스트
  - 자격 검증 200/401/403/invalid URL/URLError
  - `searchContext` 401/403/network/0건 outcome
  - 이메일 `@` 가드

## 검증

- `./scripts/dev.sh test Confluence`
  - 37 tests passed
- `git diff --check`
  - passed
- `./scripts/dev.sh build`
  - passed
- `./scripts/dev.sh test`
  - 435 tests passed

## 제외

- 앱 실행과 실제 Confluence 네트워크 호출은 사용자 요청에 따라 하지 않았다.
- Notion 설정 영역과 회의 시작 시트의 용어집 영역은 수정하지 않았다.
