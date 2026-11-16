#!/bin/bash
# 在模拟器里把 App 从新手引导开始点一遍，每一屏截图（UITests/WalkthroughTests.swift）。
#
#   scripts/ui_walkthrough.sh                 # 英文 + 简体中文
#   scripts/ui_walkthrough.sh ja zh-Hant      # 指定语言（en / zh-Hans / zh-Hant / ja）
#   SIMULATOR="iPhone 17" scripts/ui_walkthrough.sh
#
# 截图导出到 build/walkthrough/<语言>/，文件名按点击顺序编号。
set -euo pipefail
cd "$(dirname "$0")/.."

SIMULATOR="${SIMULATOR:-iPhone 17}"
BUNDLE_ID="com.purrday.app"
LANGS=("$@")
[ ${#LANGS[@]} -eq 0 ] && LANGS=(en zh-Hans)
OUT="build/walkthrough"

UDID=$(xcrun simctl list devices available | grep -E "^\s+${SIMULATOR} \(" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
[ -z "$UDID" ] && { echo "找不到模拟器：$SIMULATOR"; exit 1; }
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b > /dev/null

# "窗外跟着你那里"要一个位置：给模拟器定一个（默认纽约；换成和这台 Mac 时区对得上的地方，截图里的天色才对）
xcrun simctl location "$UDID" set "${WALKTHROUGH_LOCATION:-40.71,-74.01}" 2>/dev/null || true

xcodegen generate > /dev/null
mkdir -p "$OUT"

status=0
for lang in "${LANGS[@]}"; do
  echo "== $lang"
  # 卸载 App：清掉 UserDefaults 和 App Group 里的猫，保证从新手引导开始
  xcrun simctl uninstall "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  result="$OUT/$lang.xcresult"
  rm -rf "$result" "$OUT/$lang"
  if ! TEST_RUNNER_WALKTHROUGH_LANG="$lang" xcodebuild test \
      -project Purrday.xcodeproj -scheme PurrdayWalkthrough \
      -destination "id=$UDID" -derivedDataPath build/DerivedData \
      -resultBundlePath "$result" > "$OUT/$lang.log" 2>&1; then
    echo "   测试没通过（日志：$OUT/$lang.log）"
    status=1
  fi
  # 按截图名重命名导出的附件
  raw="$OUT/$lang.raw"
  rm -rf "$raw"
  xcrun xcresulttool export attachments --path "$result" --output-path "$raw" > /dev/null
  python3 - "$raw" "$OUT/$lang" <<'PY'
import json, pathlib, re, shutil, sys
raw, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
out.mkdir(parents=True, exist_ok=True)
for test in json.loads((raw / "manifest.json").read_text()):
    for a in test.get("attachments", []):
        name = a.get("suggestedHumanReadableName") or a["exportedFileName"]
        name = re.sub(r"_\d+_[0-9A-F-]{36}(?=\.)", "", name)  # 去掉 xcresulttool 加的序号和 UUID
        if not re.match(r"\d{2}-", name):
            continue  # 只要我们自己拍的截图和备注（Xcode 自动附的录屏、界面快照不要）
        shutil.copy(raw / a["exportedFileName"], out / name)
PY
  rm -rf "$raw"
  grep -hE "⚠️|error:|Test Case .* (passed|failed)" "$OUT/$lang.log" | sed 's/^/   /' || true
  echo "   截图：$OUT/$lang/"
done
exit $status
