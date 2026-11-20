---
status: proposed
---

# Build with SwiftPM and a script, without an Xcode project

The development Mac had only the Command Line Tools, not Xcode. Infiniview builds anyway: SwiftPM compiles the app, the two preview extensions and the Quick Action (the extensions link with `-e _NSExtensionMain`), and `scripts/build.sh` assembles the bundles from Info.plist templates in `Bundle/`, ad-hoc signs them and installs them. Anyone can build with `xcode-select --install` alone; Xcode can still open `Package.swift` for editing and debugging.

## Considered Options

- **Xcode project.** The usual way, and it fills in Info.plist keys and signing for you. It needs Xcode to build, which wasn't available, and a project file is hard to review in diffs.
- **XcodeGen/Tuist.** These generate an Xcode project and still need Xcode to build.

## Consequences

- `scripts/build.sh` must add the Info.plist keys Xcode normally writes (`CFBundleSupportedPlatforms`, `DTPlatformName`, `DTSDKName`, …). Without them a preview extension crashes at launch.
- With only the Command Line Tools, `swift test` can fail to load the Swift Testing macros, so `scripts/test.sh` points the native build system at them. The SwiftUI macro plugin isn't shipped at all, so the app avoids `@State` and keeps view state in its model.
- Both preview extensions carry their own copy of the 6 MB highlighting assets. A shared framework would save that; not worth the build complexity yet.
