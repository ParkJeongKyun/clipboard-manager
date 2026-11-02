#!/bin/bash
# 코드의 모든 번역 대상 문자열이 각 언어 파일에 있는지 확인한다. (make check-l10n, CI에서 실행)
# Swift 컴파일러가 추출한 문자열(Xcode 문자열 카탈로그와 같은 방식)과 Localizable.strings를 비교.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

cd "$PROJECT_DIR"
swift build --build-path "$WORK_DIR/build" \
    -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$WORK_DIR/strings" >"$WORK_DIR/build.log" 2>&1 \
    || { cat "$WORK_DIR/build.log"; exit 1; }

python3 -I - "$WORK_DIR/strings" Resources/*.lproj/Localizable.strings <<'PY'
import glob, json, re, sys

keys = set()
for path in glob.glob(sys.argv[1] + "/*.stringsdata"):
    for entries in json.load(open(path)).get("tables", {}).values():
        keys.update(entry["key"] for entry in entries)

failed = False
for strings_path in sys.argv[2:]:
    # 영어는 키가 곧 표시 문자열이라 검사하지 않음
    if "/en.lproj/" in strings_path:
        continue
    defined = set(re.findall(r'^"((?:[^"\\]|\\.)*)"\s*=', open(strings_path).read(), re.M))
    for key in sorted(keys - defined):
        print(f"❌ {strings_path}: 번역 없음: {key}")
        failed = True
    for key in sorted(defined - keys):
        print(f"⚠️  {strings_path}: 코드에서 쓰지 않는 번역: {key}")

if failed:
    sys.exit(1)
print(f"✅ 번역 문자열 {len(keys)}개 모두 확인")
PY
