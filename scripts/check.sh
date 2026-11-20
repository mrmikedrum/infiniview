#!/bin/zsh
# End-to-end check of the installed Infiniview: previews each fixture through Quick Look
# (QLPreviewView, the machinery Finder uses) and prints what the extension logged for it.
# `qlmanage -p` can't be used: on macOS 27 it crashes hosting any preview extension.
#   scripts/check.sh [file...]      (default: the fixture corpus)
set -euo pipefail
setopt nullglob
ROOT=${0:A:h:h}
OUT=$ROOT/build
PROBE=$OUT/QLProbe.app
mkdir -p $PROBE/Contents/MacOS
swiftc -O $ROOT/tools/qlprobe/main.swift -o $PROBE/Contents/MacOS/QLProbe
plutil -create xml1 $PROBE/Contents/Info.plist
plutil -insert CFBundleIdentifier -string com.mdrum.infiniview.qlprobe $PROBE/Contents/Info.plist
plutil -insert CFBundleExecutable -string QLProbe $PROBE/Contents/Info.plist
codesign -f -s - $PROBE 2>/dev/null

files=("$@")
(( $#files )) || files=($ROOT/Tests/Fixtures/corpus/*(N) $ROOT/Tests/Fixtures/corpus/.*(N))
files=(${files:#*/expected.tsv})

was=$(defaults read com.mdrum.infiniview debugLog 2>/dev/null || echo 0)
defaults write com.mdrum.infiniview debugLog -bool true
LOGS=($HOME/Library/Containers/com.mdrum.infiniview.{preview,takeover}/Data/Library/Logs/Infiniview.log)
typeset -A before
for l in $LOGS; do before[$l]=$( [[ -f $l ]] && wc -l < $l | tr -d ' ' || echo 0 ); done
new() { for l in $LOGS; do [[ -f $l ]] && tail -n +$(( ${before[$l]} + 1 )) $l; done }

FIFO=$(mktemp -u); mkfifo $FIFO
$PROBE/Contents/MacOS/QLProbe < $FIFO > /dev/null 2>&1 &
PP=$!
exec 3>$FIFO
for f in $files; do print -u3 -- ${f:A}; sleep 1.5; done
exec 3>&-; sleep 1; kill $PP 2>/dev/null || true; rm -f $FIFO
[[ $was == 1 ]] || defaults delete com.mdrum.infiniview debugLog

new | cut -f2- | sort -u
seen=$(new | cut -f2 | sort -u | wc -l | tr -d ' ')
echo "-- $seen of $#files files reached Infiniview"
crashes=($HOME/Library/Logs/DiagnosticReports/PreviewExtension*(Nmm-10))
(( $#crashes == 0 )) || { echo "crash reports in the last 10 minutes:"; print -l $crashes; exit 1; }
