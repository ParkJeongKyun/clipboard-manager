#!/bin/bash
# 새 버전을 릴리즈한다. 보통은 `make release VERSION=x.y.z`로 실행한다.
#
#   1. Info.plist 버전 변경
#   2. 테스트
#   3. 커밋 + 태그(vX.Y.Z)
#   4. (확인 후) push → GitHub Actions가 빌드해서 GitHub Release에 올림

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

VERSION="${1:-}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "사용법: make release VERSION=1.2.3" >&2
    exit 1
fi
TAG="v$VERSION"

BRANCH="$(git branch --show-current)"
if [[ "$BRANCH" != "master" ]]; then
    echo "master 브랜치에서만 릴리즈할 수 있습니다 (현재: $BRANCH)" >&2
    exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
    echo "커밋하지 않은 변경 사항이 있습니다. 먼저 커밋하세요." >&2
    exit 1
fi
if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "$TAG 태그가 이미 있습니다." >&2
    exit 1
fi

CURRENT="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)"
echo "🏷  $CURRENT → $VERSION"

echo "🧪 테스트 중..."
swift test

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Resources/Info.plist
git add Resources/Info.plist
git commit -q -m "Release $TAG" || true   # 버전이 이미 같으면 커밋할 게 없음
git tag -a "$TAG" -m "Release $TAG"
echo "✅ 커밋 및 태그 생성: $TAG"

read -r -p "origin에 push해서 GitHub Release를 만들까요? [y/N] " answer
if [[ "$answer" =~ ^[Yy]$ ]]; then
    git push origin master "$TAG"
    echo "🚀 push 완료. 빌드 진행 상황: gh run watch  /  결과: gh release view $TAG --web"
else
    echo "push하지 않았습니다. 나중에: git push origin master $TAG"
    echo "취소하려면: git tag -d $TAG && git reset --hard HEAD~1"
fi
