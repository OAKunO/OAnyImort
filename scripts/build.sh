#!/bin/zsh
set -eu
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
export CLANG_MODULE_CACHE_PATH="$PROJECT_ROOT/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_ROOT/.build/ModuleCache"
BUILD_FLAGS=(-c release -debug-info-format none --disable-sandbox --scratch-path .build --cache-path .build/cache --config-path .build/config --security-path .build/security)
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    BUILD_FLAGS+=(--arch arm64 --arch x86_64)
fi
swift build "${BUILD_FLAGS[@]}"
BIN_PATH="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)"
APP_PATH="$PROJECT_ROOT/dist/OAnyImort.app"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BIN_PATH/OAnyImort" "$APP_PATH/Contents/MacOS/OAnyImort"
cp Resources/Info.plist "$APP_PATH/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then
    cp Resources/AppIcon.icns "$APP_PATH/Contents/Resources/"
fi
if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$CODE_SIGN_IDENTITY" "$APP_PATH"
else
    codesign --force --sign - "$APP_PATH"
fi
codesign --verify --strict --verbose=2 "$APP_PATH"
echo "App ready: $APP_PATH"
