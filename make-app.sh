#!/bin/bash
# Builds Windchime.app — a real bundle with an Info.plist, so macOS will grant
# microphone access (a bare command-line binary can't get the TCC prompt).
# Ad-hoc code-signs it so the granted permission persists across launches.
set -e
cd "$(dirname "$0")"

# Universal build (Intel + Apple Silicon) for App Store parity.
swift build -c release --arch arm64 --arch x86_64
BIN_DIR=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)

APP="Windchime.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Windchime" "$APP/Contents/MacOS/Windchime"
cp build/icon.icns "$APP/Contents/Resources/icon.icns"
cp PrivacyInfo.xcprivacy "$APP/Contents/Resources/PrivacyInfo.xcprivacy"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Windchime</string>
  <key>CFBundleDisplayName</key><string>Windchime</string>
  <key>CFBundleExecutable</key><string>Windchime</string>
  <key>CFBundleIconFile</key><string>icon</string>
  <key>CFBundleIdentifier</key><string>com.shivami.windchime</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>2.0.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Windchime listens for the sound of your breath to make the chimes ring. Audio never leaves your device.</string>
</dict>
</plist>
PLIST

# Ad-hoc sign the LOCAL build WITHOUT the sandbox. An ad-hoc-signed sandboxed
# app can't persist the microphone TCC grant, so it re-prompts on a loop. The
# App Store build is different: Xcode applies Windchime.entitlements (sandbox +
# mic) and signs with your real Apple certificate, where the mic works fine.
codesign --force --deep --sign - "$APP" 2>/dev/null || true
echo "built $APP ($(lipo -archs "$APP/Contents/MacOS/Windchime" 2>/dev/null))"
