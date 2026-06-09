# 2026-06-09 Reconnect Delete QA

## Scope

- Branch: `feature/reconnect-delete-rendered-qa`
- Base: `release/llm-search-export-2026-06-09-rc1` at `afee79f`
- Target:
  - Settings Confluence `연동 해제`가 stored token과 persisted URL/email metadata를 함께 지우는지 확인
  - `MINTO_DEV_SECRET_STORE=file` 격리 환경에서 실제 사용자 Keychain을 건드리지 않고 삭제 결과를 확인

## Runtime Evidence

- Runtime:
  - `HOME=/tmp/minto2-reconnect-delete-rendered-qa/home`
  - `CFFIXED_USER_HOME=/tmp/minto2-reconnect-delete-rendered-qa/home`
  - `MINTO_DEV_SECRET_STORE=file`
  - `MINTO_DEV_SECRET_STORE_ROOT=/tmp/minto2-reconnect-delete-rendered-qa/dev-secrets`
- User pressed the Settings Confluence `연동 해제` button during the QA run.
- File-store result immediately after the click:
  - `/tmp/minto2-reconnect-delete-rendered-qa/dev-secrets` was empty.
  - The previous file `/tmp/minto2-reconnect-delete-rendered-qa/dev-secrets/com.minto.app.oauth__confluence.json` was removed.
- Remaining issue observed in the same run:
  - `/tmp/minto2-reconnect-delete-rendered-qa/home/Library/Preferences/com.minto.app.plist` still contained `confluenceBaseURL=https://qa.atlassian.net` and `confluenceEmail=qa@example.com`.
  - This meant the previous Settings button path removed the token, but URL/email cleanup depended on `@AppStorage` writes outside `ConfluenceService`.

## Fix

- Added `ConfluenceService.disconnect()`.
- `disconnect()` now deletes the Confluence token and removes `confluenceBaseURL`/`confluenceEmail` from the same service-owned defaults store.
- Updated Settings `연동 해제` to call `confluence.disconnect()` and clear the transient token input.

## Verification

- `git diff --check`: passed.
- `swift test --disable-sandbox --scratch-path /tmp/minto2-reconnect-delete-rendered-qa-build --filter IntegrationReconnectStateTests`: passed, 9 Swift Testing tests.
- Added regression:
  - `Confluence 연동 해제는 token과 URL/email을 함께 지운다`
  - Proves token storage no longer exists after disconnect.
  - Proves `confluenceBaseURL` and `confluenceEmail` are removed from persisted defaults.

## Notes

- Direct SwiftPM executable UI runs still rendered Confluence as `미연동` even when the file-store token and `com.minto.app.plist` seed were present. The process environment had the expected `MINTO_DEV_SECRET_STORE=file`, `MINTO_DEV_SECRET_STORE_ROOT`, `HOME`, `CFFIXED_USER_HOME`, and `__CFBundleIdentifier=com.minto.app`.
- Because of that raw-executable rendered limitation, this slice treats the manual click file deletion as runtime evidence and the new service-level regression as the authoritative cleanup guarantee.
