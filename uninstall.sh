#!/bin/bash
# Clipboard Manager 삭제 스크립트
#
#   curl -fsSL https://raw.githubusercontent.com/ParkJeongKyun/clipboard-manager/main/uninstall.sh | bash
#
# 앱과 함께 클립보드 기록, 설정, 암호화 키, 캐시, 손쉬운 사용 권한 항목까지 지운다.
# 확인 없이 바로 지우려면: ... | bash -s -- -y

set -euo pipefail

APP_NAME="ClipboardManager"
BUNDLE_ID="com.kyun.clipboard-manager"

# 스크립트 전체를 함수로 감싸서, 다운로드가 중간에 끊겨도 일부만 실행되지 않게 한다
main() {
    local assume_yes=false
    [[ "${1:-}" == "-y" ]] && assume_yes=true

    local targets=(
        "/Applications/$APP_NAME.app"
        "$HOME/Applications/$APP_NAME.app"
        "$HOME/Library/Application Support/$APP_NAME"
        "$HOME/Library/Preferences/$BUNDLE_ID.plist"
        "$HOME/Library/Caches/$BUNDLE_ID"
        "$HOME/Library/HTTPStorages/$BUNDLE_ID"
        "$HOME/Library/HTTPStorages/$BUNDLE_ID.binarycookies"
        "$HOME/Library/Saved Application State/$BUNDLE_ID.savedState"
    )

    echo "다음 항목을 삭제합니다:"
    local target
    for target in "${targets[@]}"; do
        [[ -e "$target" ]] && echo "  $target"
    done
    echo "  키체인 항목: ClipboardManager (기록 암호화 키)"
    echo "  손쉬운 사용 권한 항목"
    echo "클립보드 기록은 복구할 수 없습니다."

    if ! $assume_yes; then
        # curl | bash로 실행하면 표준 입력이 스크립트라서 터미널에서 직접 읽는다
        if ! { : < /dev/tty; } 2>/dev/null; then
            echo "확인할 터미널이 없습니다. 확인 없이 지우려면 -y 옵션을 붙이세요." >&2
            exit 1
        fi
        local answer
        read -r -p "계속할까요? [y/N] " answer < /dev/tty
        [[ "$answer" =~ ^[Yy]$ ]] || { echo "취소했습니다."; exit 0; }
    fi

    # 실행 중이면 종료 (최대 5초 대기)
    if pgrep -x "$APP_NAME" >/dev/null; then
        osascript -e "quit app id \"$BUNDLE_ID\"" >/dev/null 2>&1 || true
        for _ in {1..50}; do
            pgrep -x "$APP_NAME" >/dev/null || break
            sleep 0.1
        done
        pkill -x "$APP_NAME" 2>/dev/null || true
    fi

    for target in "${targets[@]}"; do
        rm -rf "$target"
    done
    # 메모리에 캐시된 설정까지 지우기 (파일만 지우면 다시 써질 수 있음)
    defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
    security delete-generic-password -s "ClipboardManager" -a "MasterKey" >/dev/null 2>&1 || true
    tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true

    echo "✅ 삭제 완료"
    echo "   로그인 시 자동 실행을 켰었다면 시스템 설정 → 일반 → 로그인 항목에서도 확인하세요."
}

main "$@"
