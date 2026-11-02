#!/bin/bash
# release 빌드 후 build/ClipboardManager.app 번들을 만든다. 보통은 make로 실행한다.
#
#   Scripts/bundle.sh              현재 Mac 아키텍처용 .app
#   Scripts/bundle.sh --universal  Apple Silicon + Intel 공용 .app
#   Scripts/bundle.sh --dist       배포 파일 생성: zip(설치 스크립트용), dmg(드래그 설치), SHA256SUMS
#                                  파일 이름에 버전을 넣지 않아 항상 같은 "최신 릴리즈" 주소로 받을 수 있다
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
DIST=false
INSTALL=false
for arg in "$@"; do
    case "$arg" in
        --universal) UNIVERSAL=true ;;
        --dist) DIST=true ;;
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
cp -R Resources/*.lproj "$APP_BUNDLE/Contents/Resources/"

echo "🔏 서명 중 (${SIGN_IDENTITY/#-/ad-hoc})..."
codesign --force --options runtime --identifier "$BUNDLE_ID" --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
codesign --verify --strict "$APP_BUNDLE"

echo "✅ $APP_BUNDLE"

if $DIST; then
    rm -f "$OUTPUT_DIR/$APP_NAME.zip" "$OUTPUT_DIR/$APP_NAME.dmg" "$OUTPUT_DIR/SHA256SUMS"

    # ditto는 서명과 확장 속성을 보존한다 (zip 명령은 서명을 깨뜨릴 수 있음)
    ditto -c -k --keepParent "$APP_BUNDLE" "$OUTPUT_DIR/$APP_NAME.zip"

    # 앱과 응용 프로그램 폴더 바로가기를 나란히 둔 디스크 이미지 (드래그해서 설치)
    DMG_STAGING="$(mktemp -d)"
    cp -R "$APP_BUNDLE" "$DMG_STAGING/"
    ln -s /Applications "$DMG_STAGING/Applications"
    hdiutil create -volname "Clipboard Manager" -srcfolder "$DMG_STAGING" -format UDZO -quiet "$OUTPUT_DIR/$APP_NAME.dmg"
    rm -rf "$DMG_STAGING"

    (cd "$OUTPUT_DIR" && shasum -a 256 "$APP_NAME.zip" "$APP_NAME.dmg" > SHA256SUMS)
    echo "📦 $OUTPUT_DIR/$APP_NAME.zip"
    echo "📦 $OUTPUT_DIR/$APP_NAME.dmg"
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
