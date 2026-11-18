#!/bin/bash
# PulseAwake 构建与发布脚本（原生支持 arm64 + x86_64 通用二进制）
# 用法：
#   ./build.sh                  编译并部署安装至本机 /Applications/PulseAwake.app
#   ./build.sh --dist [vX.Y.Z]  构建通用分发包 dist/PulseAwake-vX.Y.Z-macos-universal.zip 与 SHA256SUMS.txt
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-install}"
APP_NAME="PulseAwake"
RAW_VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
VERSION="${2:-v${RAW_VER#v}}"
BUILD_DIR=$(mktemp -d /tmp/pulseawake-build.XXXXXX)
BUILD_APP="$BUILD_DIR/$APP_NAME.app"
INSTALL_APP="/Applications/$APP_NAME.app"
CACHE_DIR="${TMPDIR:-/tmp}/pulseawake-swiftcache"

cleanup() {
  rm -rf "$BUILD_DIR"
}
trap cleanup EXIT

echo "1/4 生成矢量图标与编译双架构源码 (arm64 + x86_64)..."
mkdir -p "$CACHE_DIR" "$BUILD_APP/Contents/MacOS" "$BUILD_APP/Contents/Resources"
swift -module-cache-path "$CACHE_DIR" make_icon.swift "$BUILD_DIR" >/dev/null
cp Info.plist "$BUILD_APP/Contents/Info.plist"
cp "$BUILD_DIR/AppIcon.icns" "$BUILD_APP/Contents/Resources/AppIcon.icns"

swiftc -O -target arm64-apple-macos13.0 -module-cache-path "$CACHE_DIR" main.swift -o "$BUILD_DIR/${APP_NAME}_arm64"
swiftc -O -target x86_64-apple-macos13.0 -module-cache-path "$CACHE_DIR" main.swift -o "$BUILD_DIR/${APP_NAME}_x86_64"
lipo -create -output "$BUILD_APP/Contents/MacOS/$APP_NAME" \
  "$BUILD_DIR/${APP_NAME}_arm64" \
  "$BUILD_DIR/${APP_NAME}_x86_64"

if [ "$MODE" = "--dist" ]; then
  echo "2/4 执行通用分发签名 (ad-hoc)..."
  codesign --force --deep --sign - "$BUILD_APP"

  echo "3/4 组装 Release 制品目录..."
  STAGE_DIR="$BUILD_DIR/$APP_NAME"
  DIST_DIR="$(pwd)/dist"
  ZIP_NAME="${APP_NAME}-${VERSION}-macos-universal.zip"
  DIST_ZIP="$DIST_DIR/$ZIP_NAME"

  mkdir -p "$STAGE_DIR" "$DIST_DIR"
  ditto "$BUILD_APP" "$STAGE_DIR/$APP_NAME.app"
  [ -f README.md ] && cp README.md "$STAGE_DIR/README.md"
  [ -f README_EN.md ] && cp README_EN.md "$STAGE_DIR/README_EN.md"
  [ -f LICENSE ] && cp LICENSE "$STAGE_DIR/LICENSE"

  echo "4/4 打包压缩并生成 SHA256SUMS.txt..."
  rm -f "$DIST_ZIP" "$DIST_DIR/SHA256SUMS.txt"
  ditto -c -k --sequesterRsrc --keepParent "$STAGE_DIR" "$DIST_ZIP"
  (cd "$DIST_DIR" && shasum -a 256 "$ZIP_NAME" > SHA256SUMS.txt)
  echo "制品已生成："
  echo "  - $DIST_ZIP ($(du -h "$DIST_ZIP" | awk '{print $1}'))"
  echo "  - $DIST_DIR/SHA256SUMS.txt: $(cat "$DIST_DIR/SHA256SUMS.txt")"
  exit 0
fi

echo "2/4 本机代码签名..."
SIGN_ID=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/{print $2; exit}' || true)
if [ -n "$SIGN_ID" ]; then
  echo "    使用开发者证书: $SIGN_ID"
  codesign --force --deep --sign "$SIGN_ID" "$BUILD_APP"
else
  echo "    未找到开发者证书，使用临时签名 (ad-hoc)"
  codesign --force --deep --sign - "$BUILD_APP"
fi

echo "3/4 部署安装至 $INSTALL_APP..."
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 0.5
rm -rf "$INSTALL_APP"
ditto "$BUILD_APP" "$INSTALL_APP"
touch "$INSTALL_APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALL_APP" 2>/dev/null || true

echo "4/4 启动 $APP_NAME..."
open "$INSTALL_APP"
sleep 1

PID=$(pgrep -x "$APP_NAME" || true)
if [ -n "$PID" ]; then
  echo "部署完成：$INSTALL_APP 正在运行 (PID=$PID)"
else
  echo "错误：$APP_NAME 启动失败" >&2
  exit 1
fi
