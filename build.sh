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

# Info.plist 생성
cat > "$APP_CONTENTS/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>ko_KR</string>
	<key>CFBundleExecutable</key>
	<string>ClipboardManager</string>
	<key>CFBundleIdentifier</key>
	<string>com.example.clipboard-manager</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>Clipboard Manager</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>NSMainStoryboardFile</key>
	<string></string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>NSRequiresIPhoneOS</key>
	<false/>
	<key>UIDeviceFamily</key>
	<array>
		<integer>1</integer>
	</array>
	<key>UIMainStoryboardFile</key>
	<string></string>
	<key>UIRequiredDeviceCapabilities</key>
	<array>
		<string>armv7</string>
	</array>
	<key>UISupportedInterfaceOrientations</key>
	<array>
		<string>UIInterfaceOrientationPortrait</string>
		<string>UIInterfaceOrientationLandscapeLeft</string>
		<string>UIInterfaceOrientationLandscapeRight</string>
	</array>
</dict>
</plist>
EOF

echo "✅ 빌드 완료!"
echo "📍 위치: $APP_BUNDLE"
echo ""
echo "🚀 실행 방법:"
echo "   open '$APP_BUNDLE'"
echo ""
echo "💡 Finder에 복사:"
echo "   cp -r '$APP_BUNDLE' ~/Applications/"
