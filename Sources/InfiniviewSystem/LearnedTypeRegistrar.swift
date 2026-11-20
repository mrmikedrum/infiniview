import CoreServices
import Foundation
import InfiniviewCore
import UniformTypeIdentifiers

/// Writes the Learned Type helper bundle and registers it with Launch Services (ADR-0001).
public enum LearnedTypeRegistrar {
    public static var helperURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Infiniview/\(LearnedTypeHelper.bundleName)")
    }

    /// Rewrites the declaration with these extensions and re-registers it. Takes effect for the
    /// next preview; nothing is rebuilt or re-signed.
    @discardableResult
    public static func apply(_ extensions: [String]) -> Bool {
        let contents = helperURL.appendingPathComponent("Contents")
        do {
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            let version = String(Int(Date().timeIntervalSince1970 * 1000))
            let plist = LearnedTypeHelper.infoPlist(extensions: extensions, version: version)
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: contents.appendingPathComponent("Info.plist"), options: .atomic)
        } catch {
            NSLog("Infiniview: couldn't write the Learned Type helper: \(error)")
            return false
        }
        let status = LSRegisterURL(helperURL as CFURL, true)
        if status != noErr { NSLog("Infiniview: LSRegisterURL failed: \(status)") }
        return status == noErr
    }

    /// What macOS currently calls files with this extension, if it isn't Infiniview or unknown.
    public static func otherOwner(of ext: String) -> String? {
        guard let type = UTType(filenameExtension: ext), !type.isDynamic,
              type.identifier != LearnedTypeHelper.typeIdentifier else { return nil }
        return type.localizedDescription ?? type.identifier
    }
}

/// The built-in Learned Extensions, shipped in the app's resources.
public enum BuiltInList {
    public static let extensions: [String] = {
        guard let url = Bundle.main.url(forResource: "builtin-extensions", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return ExtensionList.parse(text)
    }()
}
