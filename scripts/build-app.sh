#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="漫域音乐"
APP_PATH="$ROOT_DIR/dist/$APP_NAME.app"
APP_VERSION="$(tr -d '\n' < "$ROOT_DIR/VERSION")"
BUILD_NUMBER="$(git -C "$ROOT_DIR" rev-list --count HEAD 2>/dev/null || echo 1)"

cd "$ROOT_DIR"

echo "正在编译 Release 版本…"
swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"

if [[ -d "$APP_PATH" ]]; then
    rm -rf "$APP_PATH"
fi

mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

install -m 755 "$BIN_DIR/HarmonyPlayer" "$APP_PATH/Contents/MacOS/HarmonyPlayer"
install -m 644 "$ROOT_DIR/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
install -m 644 "$ROOT_DIR/Resources/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
install -m 644 "$ROOT_DIR/Resources/AppIcon.png" "$APP_PATH/Contents/Resources/AppIcon.png"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_PATH/Contents/Info.plist"

codesign --force --deep --sign - "$APP_PATH" >/dev/null

echo "已生成：$APP_PATH"
echo "双击即可运行，或执行：open \"$APP_PATH\""
