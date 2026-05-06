#!/usr/bin/env bash
set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR" || exit 1

build_cache="/tmp/codex-switchboard-swiftpm-cache"
config_cache="/tmp/codex-switchboard-swiftpm-config"
security_cache="/tmp/codex-switchboard-swiftpm-security"
scratch_path="/tmp/codex-switchboard-m1-readiness-build"
clang_cache="/tmp/codex-switchboard-clang-module-cache"

swiftpm_args=(
  --disable-sandbox
  --cache-path "$build_cache"
  --config-path "$config_cache"
  --security-path "$security_cache"
  --scratch-path "$scratch_path"
  --manifest-cache local
)

fail() {
  echo "NOT READY: $1"
  exit 1
}

pass() {
  echo "OK: $1"
}

echo "Codex Quota Manager M1 readiness check"
echo "Workspace: $ROOT_DIR"
echo

command -v swift >/dev/null 2>&1 || fail "swift is not installed."
pass "swift found: $(command -v swift)"
swift --version
echo

developer_dir="$(xcode-select -p 2>/dev/null || true)"
if [[ -z "$developer_dir" ]]; then
  fail "xcode-select has no active developer directory. Install Xcode and run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
fi

echo "Developer directory: $developer_dir"
if [[ "$developer_dir" == "/Library/Developer/CommandLineTools" ]]; then
  fail "active developer directory is Command Line Tools, not full Xcode. Run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
fi
pass "full Xcode developer directory selected"
echo

if ! xcodebuild -version; then
  fail "xcodebuild is unavailable. Install full Xcode and accept the license if prompted."
fi
pass "xcodebuild available"
echo

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$clang_cache}"

echo "Running swift build..."
if ! swift build "${swiftpm_args[@]}"; then
  fail "swift build failed."
fi
pass "swift build passed"
echo

echo "Running swift test..."
if ! swift test "${swiftpm_args[@]}"; then
  fail "swift test failed."
fi
pass "swift test passed"
echo

echo "READY FOR M1: Xcode, SwiftPM build, and Swift tests are all ready."
