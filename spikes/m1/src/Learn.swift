// Spike "learn" tool: rewrites the Learned Type helper bundle's type declaration with the given
// extensions and re-registers it with Launch Services (LSRegisterURL), the way the host app would.
// usage: learn <helper.app path> ext...
import Foundation
import CoreServices
import UniformTypeIdentifiers

let args = Array(CommandLine.arguments.dropFirst())
let helper = URL(fileURLWithPath: args[0])
let exts = Array(args.dropFirst())
let contents = helper.appendingPathComponent("Contents")
try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)

let plist: [String: Any] = [
    "CFBundleIdentifier": "com.mdrum.infiniview.spike.types",
    "CFBundleName": "InfiniviewSpikeTypes",
    "CFBundlePackageType": "APPL",
    "CFBundleInfoDictionaryVersion": "6.0",
    "CFBundleShortVersionString": "1.0",
    // Launch Services skips re-reading a bundle whose version hasn't changed, so bump it each time.
    "CFBundleVersion": String(Int(Date().timeIntervalSince1970)),
    "LSUIElement": true,
    "UTExportedTypeDeclarations": [[
        "UTTypeIdentifier": "com.mdrum.infiniview.spike.learned",
        "UTTypeDescription": "Text (Infiniview)",
        "UTTypeConformsTo": ["public.plain-text"],
        "UTTypeTagSpecification": ["public.filename-extension": exts],
    ]],
]
let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
try data.write(to: contents.appendingPathComponent("Info.plist"))
let status = LSRegisterURL(helper as CFURL, true)
print("LSRegisterURL -> \(status)")
for e in exts { print("\(e) -> \(UTType(filenameExtension: e)?.identifier ?? "nil")") }
