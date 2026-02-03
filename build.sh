#!/bin/bash

# Clipboard Manager 빌드 및 .app 번들 생성 스크립트

set -e

PROJECT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BUILD_DIR="$PROJECT_DIR/.build/debug"
EXECUTABLE="$BUILD_DIR/clipboard-manager"
APP_NAME="ClipboardManager"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"

echo "🔨 Clipboard Manager 빌드 중..."
swift build

echo "📦 .app 번들 생성 중..."

# 기존 번들 삭제
[ -d "$APP_BUNDLE" ] && rm -rf "$APP_BUNDLE"

# 디렉토리 생성
mkdir -p "$APP_MACOS"
mkdir -p "$APP_RESOURCES"

# 실행 파일 복사
cp "$EXECUTABLE" "$APP_MACOS/$APP_NAME"
chmod +x "$APP_MACOS/$APP_NAME"

# Info.plist 복사
cp "$PROJECT_DIR/Sources/Resources/Info.plist" "$APP_CONTENTS/Info.plist"
echo "✅ Info.plist 복사 완료"

# Assets.xcassets 폴더 복사 (아이콘 포함)
if [ -d "$PROJECT_DIR/Sources/Resources/Assets.xcassets" ]; then
    cp -r "$PROJECT_DIR/Sources/Resources/Assets.xcassets" "$APP_RESOURCES/"
    echo "✅ Assets 복사 완료 (아이콘 포함)"
    
    # PNG 이미지들을 AppIcon.icns로 변환 (iconutil 사용)
    ICONSET_DIR="/tmp/AppIcon.iconset"
    rm -rf "$ICONSET_DIR"
    mkdir -p "$ICONSET_DIR"
    
    # 각 크기별 PNG를 iconset으로 복사
    for size in 16 32 64 128 256 512 1024; do
        icon_file="$APP_RESOURCES/Assets.xcassets/AppIcon.appiconset/${size}.png"
        if [ -f "$icon_file" ]; then
            cp "$icon_file" "$ICONSET_DIR/icon_${size}x${size}.png"
        fi
    done
    
    # iconutil로 .icns 생성
    if command -v iconutil &> /dev/null; then
        iconutil -c icns "$ICONSET_DIR" -o "$APP_RESOURCES/AppIcon.icns" 2>/dev/null
        echo "✅ AppIcon.icns 생성 완료"
    fi
    
    rm -rf "$ICONSET_DIR"
fi

# .app 번들에 대한 메타데이터 업데이트
touch "$APP_BUNDLE"

echo "✅ 빌드 완료!"
echo "📍 위치: $APP_BUNDLE"
echo ""
echo "🚀 실행 방법:"
echo "   open '$APP_BUNDLE'"
echo ""
echo "💡 Finder에 복사:"
echo "   cp -r '$APP_BUNDLE' ~/Applications/"
