import Foundation

/// Takeover is a separate preview extension that claims the system text types. Switching it is
/// the per-user extension setting (the same one System Settings shows), via `pluginkit`.
public enum Takeover {
    public static let extensionIdentifier = "com.mdrum.infiniview.takeover"

    /// Reads `pluginkit -m -i <id>` output. A leading "-" means switched off; "+" or nothing
    /// means on (new extensions start on). Nil if the extension isn't registered.
    public static func isOn(pluginkitOutput: String) -> Bool? {
        guard let line = pluginkitOutput.split(separator: "\n").first(where: { $0.contains(extensionIdentifier) }) else { return nil }
        return line.trimmingCharacters(in: .whitespaces).first != "-"
    }

    public static func arguments(on: Bool) -> [String] { ["-e", on ? "use" : "ignore", "-i", extensionIdentifier] }
}
