#!/bin/bash
# release 빌드 후 build/ClipboardManager.app 번들을 만든다. 보통은 make로 실행한다.
#
#   Scripts/bundle.sh              현재 Mac 아키텍처용 .app
#   Scripts/bundle.sh --universal  Apple Silicon + Intel 공용 .app
#   Scripts/bundle.sh --zip        배포용 zip과 sha256도 생성 (--universal과 함께 사용)
#   Scripts/bundle.sh --install    ~/Applications에 설치하고 실행
#
# 서명: SIGN_IDENTITY 환경 변수로 인증서 이름을 지정한다 (기본값: ad-hoc).

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="ClipboardManager"
BUNDLE_ID="com.kyun.clipboard-manager"
OUTPUT_DIR="$PROJECT_DIR/build"
APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"
INSTALL_DIR="$HOME/Applications"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

UNIVERSAL=false
ZIP=false
INSTALL=false
for arg in "$@"; do
    case "$arg" in
        --universal) UNIVERSAL=true ;;
        --zip) ZIP=true ;;
        --install) INSTALL=true ;;
        *) echo "알 수 없는 옵션: $arg" >&2; exit 1 ;;
    esac
done

cd "$PROJECT_DIR"

# 버전은 Resources/Info.plist 한 곳에서만 관리
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)"
# 빌드 번호는 커밋 수로 자동 증가
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

BUILD_ARGS=(-c release)
if $UNIVERSAL; then
    BUILD_ARGS+=(--arch arm64 --arch x86_64)
fi

echo "🔨 빌드 중: v$VERSION ($BUILD_NUMBER)$($UNIVERSAL && echo ', universal')"
swift build "${BUILD_ARGS[@]}"
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"

echo "📦 .app 번들 생성 중..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_BUNDLE/Contents/Info.plist"
iconutil -c icns Resources/AppIcon.iconset -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

echo "🔏 서명 중 (${SIGN_IDENTITY/#-/ad-hoc})..."
codesign --force --options runtime --identifier "$BUNDLE_ID" --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
codesign --verify --strict "$APP_BUNDLE"

echo "✅ $APP_BUNDLE"

if $ZIP; then
    ZIP_PATH="$OUTPUT_DIR/$APP_NAME-$VERSION.zip"
    rm -f "$ZIP_PATH"
    # ditto는 서명과 확장 속성을 보존한다 (zip 명령은 서명을 깨뜨릴 수 있음)
    ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"
    (cd "$OUTPUT_DIR" && shasum -a 256 "$(basename "$ZIP_PATH")" > "$(basename "$ZIP_PATH").sha256")
    echo "📦 $ZIP_PATH"
fi

if $INSTALL; then
    mkdir -p "$INSTALL_DIR"
    osascript -e "quit app id \"$BUNDLE_ID\"" 2>/dev/null || true
    pkill -x "$APP_NAME" 2>/dev/null || true
    rm -rf "$INSTALL_DIR/$APP_NAME.app"
    cp -R "$APP_BUNDLE" "$INSTALL_DIR/"
    open "$INSTALL_DIR/$APP_NAME.app"
    echo "🚀 설치 및 실행: $INSTALL_DIR/$APP_NAME.app"
fi
