#!/bin/zsh
# Removes everything the milestone 1 spike installed for the current user.
set -u
APP=$HOME/Applications/InfiniviewSpike.app
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister
HELPER="$HOME/Library/Application Support/InfiniviewSpike/InfiniviewSpikeTypes.app"
pluginkit -r $APP/Contents/PlugIns/Main.appex $APP/Contents/PlugIns/Takeover.appex 2>/dev/null
[[ -d $APP ]] && $LSREGISTER -u $APP
[[ -d $HELPER ]] && $LSREGISTER -u "$HELPER"
rm -rf $APP "$HOME/Library/Application Support/InfiniviewSpike"
defaults delete com.mdrum.infiniview.spike 2>/dev/null
echo "spike removed (sandbox containers under ~/Library/Containers/com.mdrum.infiniview.spike.* are left for macOS to manage)"
