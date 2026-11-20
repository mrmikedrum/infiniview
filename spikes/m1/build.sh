#!/bin/zsh
# Milestone 1 spike: builds a host app with two Quick Look preview extensions using only
# the Command Line Tools (swiftc + codesign), installs it to ~/Applications and registers it.
#   Main.appex      claims public.data, public.unix-executable and the Learned Type
#   Takeover.appex  claims system text types
# Throwaway code: see docs/research/milestone-1-spikes.md for results.
set -euo pipefail
HERE=${0:A:h}
OUT=$HERE/build
APP=$OUT/InfiniviewSpike.app
DEST=$HOME/Applications/InfiniviewSpike.app
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister
SDK=$(xcrun --show-sdk-path)
TARGET=arm64-apple-macos15.0
SDKV=$(xcrun --show-sdk-version)
SDKB=$(xcrun --show-sdk-build-version)

rm -rf $OUT && mkdir -p $APP/Contents/{MacOS,PlugIns}

swiftc -target $TARGET -sdk $SDK -O $HERE/src/Host.swift -o $APP/Contents/MacOS/InfiniviewSpike
cat > $APP/Contents/Info.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.mdrum.infiniview.spike</string>
  <key>CFBundleName</key><string>InfiniviewSpike</string>
  <key>CFBundleExecutable</key><string>InfiniviewSpike</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
  <key>DTPlatformName</key><string>macosx</string>
  <key>DTPlatformVersion</key><string>$SDKV</string>
  <key>DTSDKName</key><string>macosx$SDKV</string>
  <key>DTSDKBuild</key><string>$SDKB</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
EOF

build_appex() { # name role types-plist-array
  local name=$1 role=$2 types=$3
  local ax=$APP/Contents/PlugIns/$name.appex
  mkdir -p $ax/Contents/MacOS
  swiftc -target $TARGET -sdk $SDK -O -parse-as-library -application-extension \
    -module-name $name $HERE/src/PreviewProvider.swift \
    -Xlinker -e -Xlinker _NSExtensionMain -o $ax/Contents/MacOS/$name
  cat > $ax/Contents/Info.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.mdrum.infiniview.spike.$role</string>
  <key>CFBundleName</key><string>$name</string>
  <key>CFBundleDisplayName</key><string>Infiniview Spike $role</string>
  <key>CFBundleExecutable</key><string>$name</string>
  <key>CFBundlePackageType</key><string>XPC!</string>
  <key>CFBundleShortVersionString</key><string>0.0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
  <key>DTPlatformName</key><string>macosx</string>
  <key>DTPlatformVersion</key><string>$SDKV</string>
  <key>DTSDKName</key><string>macosx$SDKV</string>
  <key>DTSDKBuild</key><string>$SDKB</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>SpikeRole</key><string>$role</string>
  <key>NSExtension</key><dict>
    <key>NSExtensionPointIdentifier</key><string>com.apple.quicklook.preview</string>
    <key>NSExtensionPrincipalClass</key><string>PreviewProvider</string>
    <key>NSExtensionAttributes</key><dict>
      <key>QLIsDataBasedPreview</key><true/>
      <key>QLSupportsSearchableItems</key><false/>
      <key>QLSupportedContentTypes</key><array>$types</array>
    </dict>
  </dict>
</dict></plist>
EOF
  codesign -f -s - --entitlements $HERE/sandbox.entitlements -o runtime $ax
}

s() { for t in "$@"; do print -n "<string>$t</string>"; done; }
build_appex Main main "$(s public.data public.unix-executable com.mdrum.infiniview.spike.learned)"
build_appex Takeover takeover "$(s public.plain-text public.source-code public.script public.shell-script \
  public.json public.yaml public.xml public.python-script public.swift-source net.daringfireball.markdown)"

codesign -f -s - $APP
codesign --verify --deep --strict $APP

pluginkit -r $DEST/Contents/PlugIns/Main.appex 2>/dev/null || true
pluginkit -r $DEST/Contents/PlugIns/Takeover.appex 2>/dev/null || true
rm -rf $DEST && ditto $APP $DEST
$LSREGISTER -f -R $DEST
# pluginkit sometimes drops freshly replaced extensions; re-add until both are listed.
for i in {1..10}; do
  pluginkit -a $DEST/Contents/PlugIns/Main.appex $DEST/Contents/PlugIns/Takeover.appex
  sleep 1
  pluginkit -m -i com.mdrum.infiniview.spike.main | grep -q main && pluginkit -m -i com.mdrum.infiniview.spike.takeover | grep -q takeover && break
done
echo "installed $DEST"

# Probe app (a bundled host is needed: qlmanage on macOS 27 crashes hosting any data-based extension).
PROBE=$OUT/QLProbe.app
mkdir -p $PROBE/Contents/MacOS
swiftc -target $TARGET -sdk $SDK -O $HERE/src/Probe.swift -o $PROBE/Contents/MacOS/QLProbe
plutil -create xml1 $PROBE/Contents/Info.plist
plutil -insert CFBundleIdentifier -string com.mdrum.infiniview.spike.probe $PROBE/Contents/Info.plist
plutil -insert CFBundleExecutable -string QLProbe $PROBE/Contents/Info.plist
plutil -insert CFBundlePackageType -string APPL $PROBE/Contents/Info.plist
codesign -f -s - $PROBE
swiftc -target $TARGET -sdk $SDK -O $HERE/src/Learn.swift -o $OUT/learn
