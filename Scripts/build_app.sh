#!/bin/zsh
# Builds a release Grabbit.app into ./build
set -euo pipefail
cd "$(dirname "$0")/.."

# Prefer full Xcode (needed for SwiftUI macros) even if xcode-select points at the Command Line Tools.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

APP="build/Grabbit.app"
VERSION="$(tr -d '[:space:]' < VERSION)"
ARCHS=(--arch arm64 --arch x86_64)   # universal: Apple Silicon + Intel
mkdir -p build
echo "→ Compiling Grabbit $VERSION (release)…"
swift build -c release "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/Grabbit"

echo "→ Assembling bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Grabbit"

if [[ ! -f build/AppIcon.icns ]]; then
  echo "→ Rendering icon…"
  rm -rf build/AppIcon.iconset
  swift Scripts/make_icon.swift build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Grabbit</string>
  <key>CFBundleDisplayName</key><string>Grabbit</string>
  <key>CFBundleIdentifier</key><string>com.vlad.ytdown</string>
  <key>CFBundleExecutable</key><string>Grabbit</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
echo "✓ Built $APP"
echo "  Install: cp -R $APP /Applications/"
