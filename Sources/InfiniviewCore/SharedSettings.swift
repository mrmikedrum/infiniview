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
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults? = UserDefaults(suiteName: SharedSettings.domain)) {
        self.defaults = defaults ?? .standard
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

    /// The user's changes to the built-in Learned Extensions.
    public func learnedExtensions(builtIn: [String]) -> LearnedExtensions {
        LearnedExtensions(builtIn: builtIn,
                          added: Set(defaults.stringArray(forKey: Key.addedExtensions) ?? []),
                          removed: Set(defaults.stringArray(forKey: Key.removedExtensions) ?? []))
    }

    public func save(_ learned: LearnedExtensions) {
        defaults.set(learned.added.sorted(), forKey: Key.addedExtensions)
        defaults.set(learned.removed.sorted(), forKey: Key.removedExtensions)
    }
}
