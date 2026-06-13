#!/usr/bin/env bash
#
# 배포용 .app 번들 생성 스크립트 (옵션 1: 무료·소수 배포).
#
# 목적: SPM은 맨 실행파일만 만든다. 다른 Mac에 건네줄 수 있는 Minto2.app
#       번들 구조(Contents/{MacOS,Resources,Info.plist})로 패키징하고,
#       dev.sh와 동일한 자가서명 인증서로 서명한다.
#
# ⚠️ 이 번들은 공증(notarization)되지 않는다. 받는 사람은 첫 실행 시
#    "우클릭 > 열기" 또는 quarantine 제거가 필요하다 (README의 배포 안내 참고).
#    외부 일반 배포에는 유료 Apple Developer 계정 + 공증이 필요하다.
#
# 사용법:
#   ./scripts/bundle.sh            release 빌드 + .app 생성 + 서명
#   ./scripts/bundle.sh --zip      위 + 배포용 zip 생성
#
set -euo pipefail

IDENTITY="${MINTO_SIGN_IDENTITY:-Minto2 Dev}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="Minto2"
EXECUTABLE="minto2"                 # SPM product 이름
SCRATCH="/tmp/minto2-release-build"
RELEASE_DIR="$SCRATCH/release"
DIST_DIR="$ROOT/dist"
APP="$DIST_DIR/$APP_NAME.app"
INFO_PLIST_SRC="$ROOT/Sources/MintoApp/Info.plist"

MAKE_ZIP=0
[ "${1:-}" = "--zip" ] && MAKE_ZIP=1

assert_identity() {
  if ! security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    echo "❌ 코드서명 인증서 '$IDENTITY' 를 찾을 수 없습니다." >&2
    echo "   README의 '1회 설정: 코드서명 인증서'를 참고해 먼저 만드세요." >&2
    exit 1
  fi
}

echo "→ swift build -c release"
swift build -c release --disable-sandbox --scratch-path "$SCRATCH"

[ -x "$RELEASE_DIR/$EXECUTABLE" ] || { echo "❌ 실행파일 없음: $RELEASE_DIR/$EXECUTABLE" >&2; exit 1; }

echo "→ .app 구조 생성: $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# 1) 실행파일
cp "$RELEASE_DIR/$EXECUTABLE" "$APP/Contents/MacOS/$EXECUTABLE"

# 2) SPM 리소스 번들(있으면) → Contents/Resources/
#    Bundle.module은 후보 경로로 Bundle.main.resourceURL(=Contents/Resources)을
#    확인하므로 여기 두면 런타임에 발견된다. MacOS/에 두면 codesign이 코드로
#    오인해 "bundle format unrecognized"로 실패한다.
shopt -s nullglob
bundles=("$RELEASE_DIR"/*.bundle)
if [ ${#bundles[@]} -gt 0 ]; then
  echo "  ↳ 리소스 번들 ${#bundles[@]}개 동봉 (Contents/Resources/)"
  for b in "${bundles[@]}"; do
    cp -R "$b" "$APP/Contents/Resources/"
    echo "    • $(basename "$b")"
  done
else
  echo "  ↳ 리소스 번들 없음"
fi
shopt -u nullglob

# 3) Info.plist + 번들 필수 키 보강
cp "$INFO_PLIST_SRC" "$APP/Contents/Info.plist"
PB=/usr/libexec/PlistBuddy
# CFBundleExecutable: 번들에서 실행 바이너리를 찾는 키 (원본 plist엔 없음)
$PB -c "Add :CFBundleExecutable string $EXECUTABLE" "$APP/Contents/Info.plist" 2>/dev/null \
  || $PB -c "Set :CFBundleExecutable $EXECUTABLE" "$APP/Contents/Info.plist"
$PB -c "Add :CFBundlePackageType string APPL" "$APP/Contents/Info.plist" 2>/dev/null || true

# 4) 아이콘(있으면)
ICON_SRC="$ROOT/Resources/AppIcon.icns"
if [ -f "$ICON_SRC" ]; then
  cp "$ICON_SRC" "$APP/Contents/Resources/AppIcon.icns"
  $PB -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" 2>/dev/null \
    || $PB -c "Set :CFBundleIconFile AppIcon" "$APP/Contents/Info.plist"
  echo "  ↳ 아이콘 포함: AppIcon.icns"
else
  echo "  ↳ 아이콘 없음 (Resources/AppIcon.icns 추가 시 자동 포함)"
fi

# 5) 서명 — SPM 리소스 번들(swift-crypto_Crypto.bundle 등)은 코드가 없는
#    평면 리소스 번들이라 개별 서명 대상이 아니다. .app 전체 서명 시 리소스로
#    봉인된다. entitlements + Hardened Runtime을 .app에 적용한다.
assert_identity
echo "→ 서명 (identity: $IDENTITY)"
codesign --force --deep --sign "$IDENTITY" \
  --entitlements "$ROOT/Minto.entitlements" \
  --options runtime \
  "$APP"

echo "→ 서명 검증"
codesign -dv "$APP" 2>&1 | grep -E "Authority|Identifier|Signature" | sed 's/^/  /' || true
codesign --verify --deep --strict "$APP" && echo "  ✔ 서명 유효"

if [ "$MAKE_ZIP" -eq 1 ]; then
  ZIP="$DIST_DIR/$APP_NAME.zip"
  echo "→ zip 생성: $ZIP"
  rm -f "$ZIP"
  # ditto: 메타데이터·서명 보존 압축
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo "  ✔ $ZIP"
fi

echo ""
echo "✅ 완료: $APP"
echo "   받는 사람은 첫 실행 시 우클릭 > 열기 (또는: xattr -dr com.apple.quarantine '$APP_NAME.app')"
