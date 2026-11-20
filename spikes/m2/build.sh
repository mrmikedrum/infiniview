#!/bin/zsh
# Milestone 2 spike: highlighting benchmark, from the command line and in a sandboxed preview extension.
#   ./build.sh <vscode checkout> [jit|nojit]
set -euo pipefail
HERE=${0:A:h}
VSCODE=$1
VARIANT=${2:-jit}   # jit | nojit | view (view-based, with JIT)
OUT=$HERE/build
SDK=$(xcrun --show-sdk-path); SDKV=$(xcrun --show-sdk-version); SDKB=$(xcrun --show-sdk-build-version)
TARGET=arm64-apple-macos15.0
APP=$OUT/InfiniviewBench.app
DEST=$HOME/Applications/InfiniviewBench.app
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister
ID=com.mdrum.infiniview.bench

mkdir -p $OUT
(cd $HERE/js && npm install --silent && npm run -s build)
node $HERE/js/prepare-assets.mjs $VSCODE $OUT/assets 2026-light.json 2026-dark.json
cp $HERE/js/node_modules/vscode-oniguruma/release/onig.wasm $OUT/highlighter.js $OUT/assets/

swiftc -target $TARGET -sdk $SDK -O $HERE/src/Highlighter.swift $HERE/src/Bench.swift $HERE/src/main.swift -o $OUT/bench
codesign -f -s - --entitlements $HERE/jit.entitlements $OUT/bench

plist() { # id name exe type extra
  cat <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$1</string>
  <key>CFBundleName</key><string>$2</string>
  <key>CFBundleExecutable</key><string>$3</string>
  <key>CFBundlePackageType</key><string>$4</string>
  <key>CFBundleShortVersionString</key><string>0.0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
  <key>DTPlatformName</key><string>macosx</string>
  <key>DTPlatformVersion</key><string>$SDKV</string>
  <key>DTSDKName</key><string>macosx$SDKV</string>
  <key>DTSDKBuild</key><string>$SDKB</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
$5
</dict></plist>
P
}

rm -rf $APP && mkdir -p $APP/Contents/{MacOS,PlugIns}
print 'import Foundation' > $OUT/host.swift
swiftc -target $TARGET -sdk $SDK -O $OUT/host.swift -o $APP/Contents/MacOS/InfiniviewBench
plist $ID InfiniviewBench InfiniviewBench APPL '<key>LSUIElement</key><true/>' > $APP/Contents/Info.plist

AX=$APP/Contents/PlugIns/Bench.appex
if [[ $VARIANT == view ]]; then PRINCIPAL=PreviewViewController; DATABASED=false; ENT=jit
else PRINCIPAL=PreviewProvider; DATABASED=true; ENT=$VARIANT; fi
mkdir -p $AX/Contents/{MacOS,Resources}
swiftc -target $TARGET -sdk $SDK -O -parse-as-library -application-extension -module-name Bench \
  $HERE/src/Highlighter.swift $HERE/src/Bench.swift $HERE/src/BenchProvider.swift $HERE/src/ViewBench.swift \
  -Xlinker -e -Xlinker _NSExtensionMain -o $AX/Contents/MacOS/Bench
plist $ID.preview Bench Bench 'XPC!' "  <key>BenchVariant</key><string>appex-$VARIANT</string>
  <key>NSExtension</key><dict>
    <key>NSExtensionPointIdentifier</key><string>com.apple.quicklook.preview</string>
    <key>NSExtensionPrincipalClass</key><string>$PRINCIPAL</string>
    <key>NSExtensionAttributes</key><dict>
      <key>QLIsDataBasedPreview</key><$DATABASED/>
      <key>QLSupportsSearchableItems</key><false/>
      <key>QLSupportedContentTypes</key><array><string>public.data</string></array>
    </dict>
  </dict>" > $AX/Contents/Info.plist
cp -R $OUT/assets $AX/Contents/Resources/
codesign -f -s - -o runtime --entitlements $HERE/appex-$ENT.entitlements $AX
codesign -f -s - $APP

pluginkit -r $DEST/Contents/PlugIns/Bench.appex 2>/dev/null || true
rm -rf $DEST && ditto $APP $DEST
$LSREGISTER -f -R $DEST
for i in {1..10}; do
  pluginkit -a $DEST/Contents/PlugIns/Bench.appex; sleep 1
  pluginkit -m -i $ID.preview | grep -q bench && break
done
echo "installed $DEST ($VARIANT)"
