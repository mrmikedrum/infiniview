#!/bin/zsh
# Runs the unit tests. With only the Command Line Tools installed, SwiftPM's default build system
# can fail to load the Swift Testing macros, so this uses the native build system and points it at
# the Command Line Tools' Testing framework and macro plugin. With Xcode, plain `swift test` is used.
set -euo pipefail
cd ${0:A:h}/..
DEV=$(xcode-select -p)
if [[ $DEV == */CommandLineTools ]]; then
  exec swift test --build-system native \
    -Xswiftc -F -Xswiftc $DEV/Library/Developer/Frameworks \
    -Xswiftc -plugin-path -Xswiftc $DEV/usr/lib/swift/host/plugins/testing \
    -Xlinker -rpath -Xlinker $DEV/Library/Developer/Frameworks \
    -Xlinker -rpath -Xlinker $DEV/Library/Developer/usr/lib "$@"
fi
exec swift test "$@"
