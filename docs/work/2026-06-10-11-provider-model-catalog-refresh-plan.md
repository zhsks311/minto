# Provider model catalog refresh plan

## 목표

- API key provider의 기본 추천 모델 목록을 현재 공식 provider 모델 ID 기준으로 갱신한다.
- 설정 화면의 직접 입력 예시가 실제 provider별 모델 ID와 일치하게 만든다.
- API 키가 없거나 모델 목록 조회가 실패해도 사용자가 낡은 예시를 보지 않게 한다.

## 범위

1. `LLMAPIKeyTextProvider` bundled fallback 모델 목록 갱신
2. `SettingsView` 직접 입력 도움말 예시 갱신
3. 관련 단위 테스트 기대값 갱신
4. 작업 로그 추가

## 검증

- 완료: `git diff --check`
- 완료: `swift build --disable-sandbox`
- 제한: `swift build --disable-sandbox --scratch-path /tmp/minto2-provider-model-catalog-build`
  - `/tmp` checkout 중 `No space left on device`
- 제한: `swift test --disable-sandbox --filter LLMProviderTests`
  - 테스트 컴파일 후 dSYM/link 단계에서 `No space left on device`
- 제한: `./scripts/dev.sh run`
  - 빌드는 통과했으나 codesign 단계가 `internal error in Code Signing subsystem`로 실패
  - `.build/debug/minto2` 직접 실행은 PID 확인까지 완료, 접근성 도구에서는 executable app을 직접 지정할 수 없어 화면 스크린샷 확인은 보류
