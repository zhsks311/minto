#!/usr/bin/env bash
#
# 로컬 개발용 빌드 + 안정 서명 스크립트.
#
# 목적: adhoc 서명은 재빌드마다 cdhash가 바뀌어 Keychain ACL이 깨지고,
#       OAuth 토큰 접근 시 매번 권한창이 뜬다. 고정된 자가서명 인증서로
#       재서명하면 designated requirement가 인증서에 고정되어 재빌드해도
#       "항상 허용"이 유지된다.
#
# 사전 준비(1회): Keychain Access > 인증서 지원 > 인증서 생성
#                이름 "Minto2 Dev", Self Signed Root, Code Signing
#                (자가서명이라 trust는 NOT_TRUSTED로 떠도 서명에는 문제 없음)
#
# 사용법:
#   ./scripts/dev.sh build           앱 빌드 + 서명
#   ./scripts/dev.sh run             앱 빌드 + 서명 + 실행 (swift run 대신 사용)
#   ./scripts/dev.sh test [filter]   테스트 빌드 + 서명 + 실행
#   ./scripts/dev.sh sign            현재 빌드 산출물만 재서명
#
# 주의: `swift run`은 SPM이 실행 직전 다시 adhoc 서명을 덮어쓰므로 쓰지 말 것.
#       반드시 `./scripts/dev.sh run`(또는 build 후 .build/debug/minto2 직접 실행).
#
set -euo pipefail

IDENTITY="${MINTO_SIGN_IDENTITY:-Minto2 Dev}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_BIN=".build/debug/minto2"
TEST_BUNDLE=".build/debug/minto2PackageTests.xctest"
TEST_BIN="$TEST_BUNDLE/Contents/MacOS/minto2PackageTests"

# get-task-allow(디버거 attach)를 보존하기 위해 Minto.entitlements에 합쳐
# 임시 dev 권한 파일을 만든다.
make_dev_entitlements() {
  local out="$1"
  cp "$ROOT/Minto.entitlements" "$out"
  /usr/libexec/PlistBuddy -c "Add :com.apple.security.get-task-allow bool true" "$out" >/dev/null 2>&1 \
    || /usr/libexec/PlistBuddy -c "Set :com.apple.security.get-task-allow true" "$out" >/dev/null
}

assert_identity() {
  # -v(valid only)는 trust를 요구하므로 쓰지 않는다. 자가서명 인증서는
  # NOT_TRUSTED여도 codesign이 서명에 사용할 수 있다.
  if ! security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    echo "❌ 코드서명 인증서 '$IDENTITY' 를 찾을 수 없습니다." >&2
    echo "   Keychain Access > 인증서 지원 > 인증서 생성으로" >&2
    echo "   이름 '$IDENTITY', Self Signed Root, Code Signing 인증서를 먼저 만드세요." >&2
    exit 1
  fi
}

sign_one() {
  local target="$1" entitlements="$2"
  [ -e "$target" ] || return 0
  codesign --force --sign "$IDENTITY" --entitlements "$entitlements" "$target"
  echo "  ✔ signed: $target"
}

do_sign() {
  assert_identity
  local dev_ent
  dev_ent="$(mktemp -t minto-dev-ent).plist"
  # shellcheck disable=SC2064
  trap "rm -f '$dev_ent'" RETURN
  make_dev_entitlements "$dev_ent"

  echo "→ 서명 (identity: $IDENTITY)"
  sign_one "$APP_BIN" "$dev_ent"
  if [ -d "$TEST_BUNDLE" ]; then
    # 번들 내부 실행파일을 먼저, 그다음 번들 자체를 서명한다.
    sign_one "$TEST_BIN" "$dev_ent"
    sign_one "$TEST_BUNDLE" "$dev_ent"
  fi

  # 서명 검증: adhoc가 아니라 인증서 기반인지 확인
  echo "→ 검증"
  codesign -dv "$APP_BIN" 2>&1 | grep -E "Signature|Authority|TeamIdentifier" | sed 's/^/  /' || true
}

cmd="${1:-build}"
case "$cmd" in
  build)
    echo "→ swift build"
    swift build
    do_sign
    ;;
  run)
    echo "→ swift build"
    swift build
    do_sign
    echo "→ 실행: $APP_BIN"
    exec "$APP_BIN"
    ;;
  test)
    shift || true
    echo "→ swift build --build-tests"
    swift build --build-tests
    do_sign
    echo "→ swift test ${*:+(filter: $*)}"
    # 소스 변경이 없으면 swift test는 relink/재서명하지 않아 위 서명이 유지된다.
    if [ "$#" -gt 0 ]; then
      swift test --skip-build --filter "$1"
    else
      swift test --skip-build
    fi
    ;;
  sign)
    do_sign
    ;;
  *)
    echo "사용법: $0 {build|run|test [filter]|sign}" >&2
    exit 1
    ;;
esac
