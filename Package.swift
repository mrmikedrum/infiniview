// swift-tools-version: 6.0
// Infiniview builds with SwiftPM and scripts/build.sh, which assembles the app and extension
// bundles. No Xcode project; see docs/adr/0002-build-without-xcode.md.
import PackageDescription

let appExtension: [SwiftSetting] = [.unsafeFlags(["-application-extension"])]
let extensionEntry: [LinkerSetting] = [.unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain", "-Xlinker", "-application_extension"])]

let package = Package(
    name: "Infiniview",
    platforms: [.macOS(.v15)],
    targets: [
        // Pure logic: classification, language detection, Styled Source, lists, Fallback Card.
        .target(name: "InfiniviewCore"),
        // The Preview itself (AppKit + JavaScriptCore), shared by both preview extensions.
        .target(name: "InfiniviewPreview", dependencies: ["InfiniviewCore"], swiftSettings: appExtension),
        .executableTarget(name: "PreviewExtension", dependencies: ["InfiniviewPreview"],
                          swiftSettings: appExtension, linkerSettings: extensionEntry),
        .executableTarget(name: "QuickActionExtension", dependencies: ["InfiniviewCore"],
                          swiftSettings: appExtension, linkerSettings: extensionEntry),
        .executableTarget(name: "InfiniviewApp", dependencies: ["InfiniviewCore"]),
        .testTarget(name: "InfiniviewCoreTests", dependencies: ["InfiniviewCore"]),
        .testTarget(name: "InfiniviewPreviewTests", dependencies: ["InfiniviewPreview"]),
    ]
)
