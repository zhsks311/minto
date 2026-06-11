# Confluence 연결 설정 UX 개선 계획

## 목표

- Confluence 설정 입력은 저장값과 분리하고, 실제 인증 확인 성공 후에만 연동 저장한다.
- 회의 시작 시트의 Confluence 조회는 0건과 인증/네트워크 실패를 구분한다.
- 입력창 클릭 영역을 넓혀 설정 화면에서 사이트 URL, 이메일, API token 입력을 쉽게 한다.

## 범위

- 수정 대상:
  - `Sources/Minto/Services/ConfluenceService.swift`
  - `Sources/Minto/UI/SettingsView.swift`
  - `Sources/Minto/UI/MeetingSetupView.swift`
  - `Tests/MintoTests/RelatedInfoTests.swift`
- 비대상:
  - Notion 설정 영역
  - 회의 시작 시트의 용어집 영역
  - 앱 실행 또는 실제 Confluence 네트워크 호출

## 단계와 검증 기준

1. Confluence 자격 검증 API 추가
   - `validateCredentials(baseURL:email:token:)` 추가
   - `/wiki/rest/api/user/current` Basic 인증 호출
   - 200, 401, 403, invalid URL, network outcome 테스트
   - 검증 호출은 저장 상태와 재연결 상태를 바꾸지 않는다

2. Confluence 문맥 검색 실패 결과 분리
   - `search(_:limit:) -> [RelatedDoc]`는 유지
   - `searchContext`는 문서와 실패 사유를 함께 반환
   - 401/403은 `needsReconnect`로 마킹하고, 네트워크와 0건은 구분

3. SettingsView 연결 흐름 변경
   - URL/email은 로컬 `@State`로 관리
   - 입력 변경 시 검증 상태 무효화
   - 이메일 `@` 가드와 순수 함수 테스트 추가
   - `연결 확인` 성공 후 `연동` 버튼만 활성화
   - 연동 시 URL/email/token을 일괄 저장하고 token 입력란을 비운다

4. MeetingSetupView 문구 분기
   - 0건, 401/403, 네트워크 실패 메시지를 분리
   - 상태 색상은 성공 accent, 인증 거부 orange, 네트워크 red, 0건 secondary

## 완료 게이트

- `git diff --check`
- `./scripts/dev.sh build`
- `./scripts/dev.sh test`
- 작은 단위 커밋, 한국어 메시지, `Co-Authored-By` 없음

## 진행 상태

- [x] 계획 문서 작성
- [x] Confluence 자격 검증 API 추가
- [x] 문맥 검색 실패 결과 분리
- [x] SettingsView 연결 확인 후 연동 흐름 구현
- [x] MeetingSetupView 상태 문구 분기
- [x] 관련 테스트 추가
- [x] 관련 테스트: `./scripts/dev.sh test Confluence`
- [x] 전체 게이트: `git diff --check`
- [x] 전체 게이트: `./scripts/dev.sh build`
- [x] 전체 게이트: `./scripts/dev.sh test` (435 tests)
