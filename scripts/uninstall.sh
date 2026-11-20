#!/bin/zsh
# Removes Infiniview for the current user: the app, its extensions and the Learned Type helper.
# Settings (defaults domain com.mdrum.infiniview) are kept; pass --settings to delete them too.
set -u
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister
HELPER="$HOME/Library/Application Support/Infiniview"
for app in /Applications/Infiniview.app $HOME/Applications/Infiniview.app; do
  [[ -d $app ]] || continue
  [[ -f $app/Contents/Library/LaunchAgents/com.mdrum.infiniview.helper.plist ]] && $app/Contents/MacOS/Infiniview --unregister
  pluginkit -r $app/Contents/PlugIns/*.appex 2>/dev/null
  $LSREGISTER -u $app
  rm -rf $app && echo "removed $app"
done
if [[ -d $HELPER ]]; then
  $LSREGISTER -u "$HELPER/Infiniview Learned Types.app"
  rm -rf $HELPER && echo "removed the Learned Type helper"
fi
[[ ${1:-} == --settings ]] && defaults delete com.mdrum.infiniview 2>/dev/null && echo "removed settings"
exit 0
