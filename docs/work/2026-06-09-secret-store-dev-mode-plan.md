# SecretStore dev mode implementation plan

작성일: 2026-06-09
상태: 구현/검증 완료
브랜치: `integration/llm-search-export-2026-06-09`

## 목표

개발 중 반복 Keychain prompt를 줄이기 위해 opt-in secret 저장 경로를 제공한다.

## 범위

- `SecretStore` 프로토콜 추가
- 기본 `KeychainSecretStore` 구현
- 개발 opt-in `LocalDevSecretStore` 구현
- `MINTO_DEV_SECRET_STORE=file`이면 file store 사용
- LLM API key, MCP/OAuth token storage, Confluence API token storage가 공통 store를 사용하도록 연결

## 비범위

- production 기본 저장소 변경
- 기존 Keychain 데이터 자동 migration
- token 원문 로그 출력
- OAuth provider의 네트워크/login 흐름 변경

## 검증 기준

- 기본 모드에서는 Keychain 기반 storage를 사용한다.
- `MINTO_DEV_SECRET_STORE=file` 모드에서는 Keychain backend 호출 없이 save/load/exists/delete가 동작한다.
- 파일 store는 secret 원문을 파일명이나 로그에 남기지 않는다.
- 기존 LLM API key, Confluence, Notion token tests가 통과한다.

## 단계

1. 공통 `SecretStore`와 factory 추가
2. 기존 storage backend가 `SecretStore`를 사용하도록 연결
3. file store unit test 추가
4. 관련 LLM/Confluence/Notion tests와 build 검증

## 결과

- 기본 모드는 `KeychainSecretStore`를 사용한다.
- `MINTO_DEV_SECRET_STORE=file` opt-in 모드는 `LocalDevSecretStore`를 사용한다.
- 개발용 file store는 `~/Library/Application Support/Minto/dev-secrets` 아래에 0700 directory, 0600 file permission으로 secret 파일을 저장한다.
- LLM API key, OAuth token, Confluence API token storage를 공통 `SecretStore` backend로 연결했다.
- Settings 안내 문구는 `Keychain` 고정 표현 대신 기본 저장소가 Keychain인 `비밀 저장소` 표현으로 정리했다.

## 검증 결과

- `swift test --disable-sandbox --scratch-path /tmp/minto2-secret-store-test --filter SecretStore` 통과: 5 tests
- `swift test --disable-sandbox --scratch-path /tmp/minto2-secret-store-related-test --filter 'SecretStore|LLMProviderTests|RelatedInfoTests'` 통과: 70 tests
- `swift build --disable-sandbox --scratch-path /tmp/minto2-secret-store-build` 통과
- `git diff --check` 통과
