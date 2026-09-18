#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="漫域音乐"
APP_PATH="$ROOT_DIR/dist/$APP_NAME.app"
APP_VERSION="$(tr -d '\n' < "$ROOT_DIR/VERSION")"
# VERSION 允许带预发布后缀，如 3.13.0-beta1：CFBundleShortVersionString 必须是
# 纯数字三段，用 '-' 之前的部分；完整版本号写入 ManyuMusicReleaseName，
# 设置页据此显示"内部测试版"标识。
APP_MARKETING_VERSION="${APP_VERSION%%-*}"
BUILD_NUMBER="$(git -C "$ROOT_DIR" rev-list --count HEAD 2>/dev/null || echo 1)"

cd "$ROOT_DIR"

echo "正在编译 Release 版本…"
# --disable-sandbox：SwiftPM 自身的 manifest 编译沙箱（sandbox-exec）在受限
# 环境下会报 "sandbox_apply: Operation not permitted"，这里关闭它以保证构建可用。
swift build -c release --disable-sandbox

BIN_DIR="$(swift build -c release --show-bin-path --disable-sandbox)"

if [[ -d "$APP_PATH" ]]; then
    rm -rf "$APP_PATH"
fi

mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

install -m 755 "$BIN_DIR/HarmonyPlayer" "$APP_PATH/Contents/MacOS/HarmonyPlayer"
install -m 644 "$ROOT_DIR/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
install -m 644 "$ROOT_DIR/Resources/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
install -m 644 "$ROOT_DIR/Resources/AppIcon.png" "$APP_PATH/Contents/Resources/AppIcon.png"
install -m 644 "$ROOT_DIR/Resources/AppIconDark.png" "$APP_PATH/Contents/Resources/AppIconDark.png"
install -m 644 "$ROOT_DIR/Resources/AppIconLight.png" "$APP_PATH/Contents/Resources/AppIconLight.png"
install -m 644 "$ROOT_DIR/Resources/AppIconDark.icns" "$APP_PATH/Contents/Resources/AppIconDark.icns"
install -m 644 "$ROOT_DIR/Resources/AppIconLight.icns" "$APP_PATH/Contents/Resources/AppIconLight.icns"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_MARKETING_VERSION" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_PATH/Contents/Info.plist"
# 写入完整版本号（可能含 -betaN 后缀）；键来自 Info.plist 模板，先删后加保证幂等。
/usr/libexec/PlistBuddy -c "Delete :ManyuMusicReleaseName" "$APP_PATH/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :ManyuMusicReleaseName string $APP_VERSION" "$APP_PATH/Contents/Info.plist"

codesign --force --deep --sign - "$APP_PATH" >/dev/null

echo "已生成：$APP_PATH"
echo "双击即可运行，或执行：open \"$APP_PATH\""
