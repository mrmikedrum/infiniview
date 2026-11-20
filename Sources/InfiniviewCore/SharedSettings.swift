import Foundation

/// Settings the app writes and the preview extensions read. The extensions are sandboxed and
/// app groups don't work with ad-hoc signing, so they read the app's own defaults domain through
/// a `shared-preference.read-only` entitlement (docs/research/milestone-1-spikes-2026-11.md).
public struct SharedSettings {
    public static let domain = "com.mdrum.infiniview"

    public enum ThemeSource: String, Sendable { case bundled, editor }

    enum Key {
        static let themeSource = "themeSource"
        static let editorName = "editorName"
        static let editorThemeLight = "editorThemeLight"
        static let editorThemeDark = "editorThemeDark"
        static let addedExtensions = "addedExtensions"
        static let removedExtensions = "removedExtensions"
        static let dismissedExtensions = "dismissedExtensions"
        static let debugLog = "debugLog"
    }

    private let defaults: UserDefaults

    /// In the app the domain is its own (`.standard`); elsewhere it's read as a suite.
    public init(defaults: UserDefaults? = nil) {
        if let defaults { self.defaults = defaults }
        else if Bundle.main.bundleIdentifier == Self.domain { self.defaults = .standard }
        else { self.defaults = UserDefaults(suiteName: Self.domain) ?? .standard }
    }

    public var themeSource: ThemeSource {
        get { defaults.string(forKey: Key.themeSource).flatMap(ThemeSource.init) ?? .bundled }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.themeSource) }
    }

    /// Display name of the editor whose themes are in use.
    public var editorName: String? {
        get { defaults.string(forKey: Key.editorName) }
        nonmutating set { defaults.set(newValue, forKey: Key.editorName) }
    }

    /// The editor's themes, flattened to the bundled themes' JSON shape.
    public var editorThemeLight: String? {
        get { defaults.string(forKey: Key.editorThemeLight) }
        nonmutating set { defaults.set(newValue, forKey: Key.editorThemeLight) }
    }

    public var editorThemeDark: String? {
        get { defaults.string(forKey: Key.editorThemeDark) }
        nonmutating set { defaults.set(newValue, forKey: Key.editorThemeDark) }
    }

    /// Opt-in diagnostics: each preview appends a line to Library/Logs/Infiniview.log in the
    /// extension's container. Set with `defaults write com.mdrum.infiniview debugLog -bool true`.
    public var debugLog: Bool { defaults.bool(forKey: Key.debugLog) }

    /// The user's changes to the built-in Learned Extensions.
    public func learnedExtensions(builtIn: [String]) -> LearnedExtensions {
        LearnedExtensions(builtIn: builtIn,
                          added: Set(defaults.stringArray(forKey: Key.addedExtensions) ?? []),
                          removed: Set(defaults.stringArray(forKey: Key.removedExtensions) ?? []),
                          dismissed: Set(defaults.stringArray(forKey: Key.dismissedExtensions) ?? []))
    }

    public func save(_ learned: LearnedExtensions) {
        defaults.set(learned.added.sorted(), forKey: Key.addedExtensions)
        defaults.set(learned.removed.sorted(), forKey: Key.removedExtensions)
        defaults.set(learned.dismissed.sorted(), forKey: Key.dismissedExtensions)
    }

    /// Re-reads the domain from disk: another process (the app or the helper) may have changed it.
    public func synchronize() { defaults.synchronize() }
}
