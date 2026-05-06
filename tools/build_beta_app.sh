#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

APP_NAME="Codex Quota Manager"
EXECUTABLE_NAME="CodexQuotaManager"
BUNDLE_ID="com.vifengjie.codexquotamanager"
BUILD_ROOT="$REPO_ROOT/.build/beta-release"
APP_BUNDLE="$BUILD_ROOT/${APP_NAME}.app"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"
PLIST_PATH="$APP_BUNDLE/Contents/Info.plist"
VERSION=$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo "dev")
SWIFTPM_ROOT="$BUILD_ROOT/swiftpm"
CLANG_CACHE_ROOT="$BUILD_ROOT/clang-module-cache"
CONFIG_ROOT="$BUILD_ROOT/swiftpm-config"
SECURITY_ROOT="$BUILD_ROOT/swiftpm-security"

echo "==> Building release binary"
mkdir -p "$SWIFTPM_ROOT" "$CLANG_CACHE_ROOT" "$CONFIG_ROOT" "$SECURITY_ROOT"
env CLANG_MODULE_CACHE_PATH="$CLANG_CACHE_ROOT" \
  swift build \
  -c release \
  --product "$EXECUTABLE_NAME" \
  --package-path "$REPO_ROOT" \
  --disable-sandbox \
  --scratch-path "$SWIFTPM_ROOT" \
  --cache-path "$SWIFTPM_ROOT/cache" \
  --config-path "$CONFIG_ROOT" \
  --security-path "$SECURITY_ROOT" \
  --manifest-cache local

BINARY_PATH="$SWIFTPM_ROOT/release/$EXECUTABLE_NAME"

if [[ ! -x "$BINARY_PATH" ]]; then
  echo "Release binary not found at: $BINARY_PATH" >&2
  exit 1
fi

echo "==> Assembling app bundle"
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BINARY_PATH" "$MACOS_DIR/$EXECUTABLE_NAME"
chmod +x "$MACOS_DIR/$EXECUTABLE_NAME"

cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleExecutable</key>
  <string>${EXECUTABLE_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF

touch "$APP_BUNDLE"

echo "==> Beta app bundle ready"
echo "$APP_BUNDLE"
