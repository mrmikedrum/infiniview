import Foundation

/// The plain-text extension list format (`Resources/builtin-extensions.txt`).
public enum ExtensionList {
    /// One extension per line, optionally followed by a description; `#` starts a comment line.
    /// Invalid entries and duplicates are dropped; order is kept.
    public static func parse(_ text: String) -> [String] {
        var seen = Set<String>(), result = [String]()
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), let first = trimmed.split(whereSeparator: \.isWhitespace).first,
                  let ext = normalize(String(first)), seen.insert(ext).inserted else { continue }
            result.append(ext)
        }
        return result
    }

    /// Lower case, no leading dot. Only what can be a file name's last extension: no dots,
    /// slashes or spaces, at most 64 characters.
    public static func normalize(_ input: String) -> String? {
        var s = input.trimmingCharacters(in: .whitespaces).lowercased()
        if s.hasPrefix(".") { s.removeFirst() }
        guard !s.isEmpty, s.count <= 64,
              s.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || "-_+~".unicodeScalars.contains($0) })
        else { return nil }
        return s
    }
}

/// The Learned Extensions: the built-in list, plus what the user added, minus what they removed.
public struct LearnedExtensions: Sendable, Equatable {
    public let builtIn: [String]
    public private(set) var added: Set<String>
    public private(set) var removed: Set<String>
    /// Added extensions the user removed again. Folder Checks never re-learn these, or the
    /// built-in ones in `removed`; learning one by hand clears it.
    public private(set) var dismissed: Set<String>

    public init(builtIn: [String], added: Set<String> = [], removed: Set<String> = [], dismissed: Set<String> = []) {
        self.builtIn = builtIn
        self.added = added.subtracting(builtIn)
        self.removed = removed.intersection(builtIn)
        self.dismissed = dismissed.subtracting(builtIn).subtracting(added)
    }

    public var effective: [String] { Set(builtIn).subtracting(removed).union(added).sorted() }

    public func isLearned(_ ext: String) -> Bool {
        ExtensionList.normalize(ext).map { effective.contains($0) } ?? false
    }

    /// The user removed this extension, so only the user may learn it again.
    public func isDismissed(_ ext: String) -> Bool {
        ExtensionList.normalize(ext).map { removed.contains($0) || dismissed.contains($0) } ?? false
    }

    /// Learning asked for by the user (Quick Action, settings): always applies.
    public mutating func learn(_ ext: String) {
        guard let e = ExtensionList.normalize(ext) else { return }
        dismissed.remove(e)
        if builtIn.contains(e) { removed.remove(e) } else { added.insert(e) }
    }

    /// Learning by a Folder Check: skipped for extensions the user removed.
    /// - Returns: whether the extension is newly learned.
    @discardableResult
    public mutating func learnAutomatically(_ ext: String) -> Bool {
        guard let e = ExtensionList.normalize(ext), !isDismissed(e), !isLearned(e) else { return false }
        learn(e)
        return true
    }

    public mutating func forget(_ ext: String) {
        guard let e = ExtensionList.normalize(ext) else { return }
        if builtIn.contains(e) { removed.insert(e) } else if added.remove(e) != nil { dismissed.insert(e) }
    }
}

/// The helper bundle whose type declaration turns Learned Extensions into the Learned Type
/// (ADR-0001). The app rewrites its Info.plist and re-registers it with Launch Services.
public enum LearnedTypeHelper {
    public static let bundleIdentifier = "com.mdrum.infiniview.learned-types"
    public static let typeIdentifier = "com.mdrum.infiniview.learned-text"
    public static let bundleName = "Infiniview Learned Types.app"

    /// - Parameter version: must change on every rewrite; Launch Services skips re-reading a
    ///   bundle whose version is unchanged.
    public static func infoPlist(extensions: [String], version: String) -> [String: Any] {
        [
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleName": "Infiniview Learned Types",
            "CFBundlePackageType": "APPL",
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": version,
            "LSUIElement": true,
            "UTExportedTypeDeclarations": [[
                "UTTypeIdentifier": typeIdentifier,
                "UTTypeDescription": "Text (Infiniview)",
                "UTTypeConformsTo": ["public.plain-text"],
                "UTTypeTagSpecification": ["public.filename-extension": extensions],
            ] as [String: Any]],
        ]
    }
}
