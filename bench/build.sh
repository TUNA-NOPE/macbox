#!/bin/bash
# Builds the benchmark tools on the Mac (run there, from ~/src/bench):
#   simfps         the frame counter (macOS command line)
#   GlassBench.app the iOS Simulator load (x86_64 simulator app, ad-hoc signed)
set -euo pipefail
cd "$(dirname "$0")"
xcrun swiftc -O simfps.swift -o simfps
APP=GlassBench.app
rm -rf "$APP"; mkdir -p "$APP"
xcrun -sdk iphonesimulator swiftc -O -target x86_64-apple-ios26.0-simulator -parse-as-library \
  GlassBench/main.swift -o "$APP/GlassBench"
cat > "$APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.macbox.glassbench</string>
  <key>CFBundleExecutable</key><string>GlassBench</string>
  <key>CFBundleName</key><string>GlassBench</string>
  <key>CFBundleDisplayName</key><string>GlassBench</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleSupportedPlatforms</key><array><string>iPhoneSimulator</string></array>
  <key>DTPlatformName</key><string>iphonesimulator</string>
  <key>MinimumOSVersion</key><string>26.0</string>
  <key>UIDeviceFamily</key><array><integer>1</integer></array>
  <key>UILaunchScreen</key><dict/>
  <key>UIApplicationSceneManifest</key><dict>
    <key>UIApplicationSupportsMultipleScenes</key><false/>
  </dict>
</dict></plist>
PLIST
codesign -s - -f "$APP" >/dev/null 2>&1
echo "built: $(pwd)/simfps $(pwd)/$APP"
# GenieBench.app: the desktop load (macOS app)
G=GenieBench.app
rm -rf "$G"; mkdir -p "$G/Contents/MacOS"
xcrun swiftc -O GenieBench/main.swift -o "$G/Contents/MacOS/GenieBench"
cat > "$G/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.macbox.geniebench</string>
  <key>CFBundleExecutable</key><string>GenieBench</string>
  <key>CFBundleName</key><string>GenieBench</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign -s - -f "$G" >/dev/null 2>&1
echo "built: $(pwd)/$G"
