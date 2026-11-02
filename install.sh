#!/bin/bash
# Clipboard Manager 설치 스크립트
#
#   curl -fsSL https://raw.githubusercontent.com/ParkJeongKyun/clipboard-manager/master/install.sh | bash
#
# 최신 릴리즈를 받아 체크섬을 확인한 뒤 응용 프로그램 폴더에 설치하고 실행한다.
# 이미 설치되어 있으면 같은 위치에 덮어써서 업데이트한다.
# curl로 받은 파일에는 격리 속성이 붙지 않아 "확인되지 않은 개발자" 경고 없이 실행된다.

set -euo pipefail

REPO="ParkJeongKyun/clipboard-manager"
APP_NAME="ClipboardManager"
BUNDLE_ID="com.kyun.clipboard-manager"
DOWNLOAD_URL="https://github.com/$REPO/releases/latest/download"

# 스크립트 전체를 함수로 감싸서, 다운로드가 중간에 끊겨도 일부만 실행되지 않게 한다
main() {
    if [[ "$(uname)" != "Darwin" ]]; then
        echo "macOS에서만 설치할 수 있습니다." >&2
        exit 1
    fi
    local macos_major
    macos_major="$(sw_vers -productVersion | cut -d. -f1)"
    if (( macos_major < 15 )); then
        echo "macOS 15 이상이 필요합니다. (현재: $(sw_vers -productVersion))" >&2
        exit 1
    fi

    # 이미 설치된 위치가 있으면 그대로 업데이트, 없으면 /Applications (쓸 수 없으면 ~/Applications)
    local install_dir
    if [[ -d "$HOME/Applications/$APP_NAME.app" ]]; then
        install_dir="$HOME/Applications"
    elif [[ -d "/Applications/$APP_NAME.app" || -w "/Applications" ]]; then
        install_dir="/Applications"
    else
        install_dir="$HOME/Applications"
    fi

    # trap은 main이 끝난 뒤 실행되므로 local이 아닌 전역 변수여야 한다
    work_dir="$(mktemp -d)"
    trap 'rm -rf "$work_dir"' EXIT

    echo "⬇️  최신 버전 다운로드 중..."
    curl -fsSL "$DOWNLOAD_URL/$APP_NAME.zip" -o "$work_dir/$APP_NAME.zip"
    curl -fsSL "$DOWNLOAD_URL/SHA256SUMS" -o "$work_dir/SHA256SUMS"

    echo "🔐 체크섬 확인 중..."
    (cd "$work_dir" && grep " $APP_NAME.zip\$" SHA256SUMS | shasum -a 256 -c - >/dev/null) || {
        echo "체크섬이 일치하지 않습니다. 다운로드가 손상되었을 수 있으니 다시 시도해 주세요." >&2
        exit 1
    }
    ditto -x -k "$work_dir/$APP_NAME.zip" "$work_dir"

    # 실행 중이면 종료 (최대 5초 대기)
    if pgrep -x "$APP_NAME" >/dev/null; then
        echo "⏹  실행 중인 앱 종료 중..."
        osascript -e "quit app id \"$BUNDLE_ID\"" >/dev/null 2>&1 || true
        for _ in {1..50}; do
            pgrep -x "$APP_NAME" >/dev/null || break
            sleep 0.1
        done
    fi

    echo "📦 $install_dir 에 설치 중..."
    mkdir -p "$install_dir"
    rm -rf "$install_dir/$APP_NAME.app"
    ditto "$work_dir/$APP_NAME.app" "$install_dir/$APP_NAME.app"
    xattr -dr com.apple.quarantine "$install_dir/$APP_NAME.app" 2>/dev/null || true

    open "$install_dir/$APP_NAME.app"
    echo "✅ 설치 완료: $install_dir/$APP_NAME.app"
    echo "   메뉴바의 클립보드 아이콘을 확인하세요. 단축키: ⌃⌘V"
}

main "$@"
