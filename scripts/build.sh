#!/bin/zsh
# Builds Infiniview.app with SwiftPM and assembles its bundles; no Xcode project needed.
#   scripts/build.sh              build into build/Infiniview.app
#   scripts/build.sh --install    also install it (to /Applications if writable, else ~/Applications)
# INSTALL_DIR overrides where it installs.
set -euo pipefail
ROOT=${0:A:h:h}
cd $ROOT
OUT=$ROOT/build
APP=$OUT/Infiniview.app
VERSION=0.1.0
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 1)
SDKV=$(xcrun --show-sdk-version)
SDKB=$(xcrun --show-sdk-build-version)
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister

swift build -c release --arch arm64 --product InfiniviewApp
swift build -c release --arch arm64 --product PreviewExtension
swift build -c release --arch arm64 --product QuickActionExtension
swift build -c release --arch arm64 --product InfiniviewHelper
BIN=$(swift build -c release --arch arm64 --show-bin-path)

# Info.plist keys Xcode normally adds; without them a preview extension crashes at launch.
PLATFORM_KEYS="<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
	<key>DTPlatformName</key><string>macosx</string>
	<key>DTPlatformVersion</key><string>$SDKV</string>
	<key>DTSDKName</key><string>macosx$SDKV</string>
	<key>DTSDKBuild</key><string>$SDKB</string>
	<key>LSMinimumSystemVersion</key><string>15.0</string>"

fill() { # template output [KEY value]...
  local text=$(<$1) out=$2; shift 2
  text=${text//__PLATFORM_KEYS__/$PLATFORM_KEYS}
  text=${text//__VERSION__/$VERSION}
  text=${text//__BUILD__/$BUILD}
  while (( $# )); do text=${text//$1/$2}; shift 2; done
  print -r -- $text > $out
  plutil -lint -s $out
}

types() { for t in "$@"; do print -r -- "				<string>$t</string>"; done }

rm -rf $APP
mkdir -p $APP/Contents/{MacOS,Resources,PlugIns,Library/LaunchAgents}
cp $BIN/InfiniviewApp $APP/Contents/MacOS/Infiniview
cp $BIN/InfiniviewHelper $APP/Contents/MacOS/
cp Bundle/Helper-LaunchAgent.plist $APP/Contents/Library/LaunchAgents/com.mdrum.infiniview.helper.plist
cp Resources/builtin-extensions.txt THIRD-PARTY-NOTICES.md LICENSE $APP/Contents/Resources/
fill Bundle/App-Info.plist $APP/Contents/Info.plist

preview_appex() { # name bundle-id display-name types...
  local ax=$APP/Contents/PlugIns/$1.appex id=$2 display=$3; shift 3
  mkdir -p $ax/Contents/{MacOS,Resources}
  cp $BIN/PreviewExtension $ax/Contents/MacOS/
  ditto Vendor/highlighting $ax/Contents/Resources/highlighting
  fill Bundle/Preview-Info.plist $ax/Contents/Info.plist __BUNDLE_ID__ $id __NAME__ ${ax:t:r} __DISPLAY_NAME__ $display __TYPES__ "$(types "$@")"
}
preview_appex InfiniviewPreview com.mdrum.infiniview.preview "Infiniview" \
  public.data public.unix-executable com.mdrum.infiniview.learned-text
preview_appex InfiniviewTakeover com.mdrum.infiniview.takeover "Infiniview Takeover" \
  ${(f)"$(grep -v '^#' Resources/takeover-types.txt | grep .)"}

QA=$APP/Contents/PlugIns/AlwaysPreviewAsText.appex
mkdir -p $QA/Contents/MacOS
cp $BIN/QuickActionExtension $QA/Contents/MacOS/
fill Bundle/QuickAction-Info.plist $QA/Contents/Info.plist

# Ad-hoc signing: extensions first, sandboxed; then the app.
for ax in InfiniviewPreview InfiniviewTakeover; do
  codesign -f -s - -o runtime --entitlements Bundle/Preview.entitlements $APP/Contents/PlugIns/$ax.appex
done
codesign -f -s - -o runtime --entitlements Bundle/QuickAction.entitlements $QA
codesign -f -s - -o runtime -i com.mdrum.infiniview.helper $APP/Contents/MacOS/InfiniviewHelper
codesign -f -s - $APP
codesign --verify --deep --strict $APP
echo "built $APP"

[[ ${1:-} == --install ]] || exit 0

if [[ -n ${INSTALL_DIR:-} ]]; then DEST_DIR=$INSTALL_DIR
elif [[ -w /Applications ]]; then DEST_DIR=/Applications
else DEST_DIR=$HOME/Applications; mkdir -p $DEST_DIR
fi
DEST=$DEST_DIR/Infiniview.app
# A running helper keeps the old binary; stop it so launchd starts the new one on demand.
launchctl kill TERM gui/$UID/com.mdrum.infiniview.helper 2>/dev/null || true
for ax in InfiniviewPreview InfiniviewTakeover AlwaysPreviewAsText; do
  pluginkit -r $DEST/Contents/PlugIns/$ax.appex 2>/dev/null || true
done
rm -rf $DEST
ditto $APP $DEST
$LSREGISTER -f -R $DEST
# pluginkit sometimes drops freshly replaced extensions for a moment; add until all are listed.
for i in {1..10}; do
  pluginkit -a $DEST/Contents/PlugIns/*.appex
  sleep 1
  (( $(pluginkit -m -p com.apple.quicklook.preview | grep -c com.mdrum.infiniview) == 2 )) && break
done
# Finder lists a new Quick Action only once it is turned on.
pluginkit -e use -i com.mdrum.infiniview.quick-action
# Register the Learned Type with the built-in list, and the Folder Check helper (the app does both on
# every launch too).
$DEST/Contents/MacOS/Infiniview --register
echo "installed $DEST"
