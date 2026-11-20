import Foundation

/// A Folder Check (ADR-0005): finds the extensions in a folder whose files are text, so they can
/// be learned before the user previews them.
public enum FolderCheck {
    /// Most folder entries looked at; larger folders are checked only this far.
    public static let entryLimit = 1000
    /// Files tried per extension when earlier ones are empty or unreadable.
    public static let samplesPerExtension = 3

    /// Extensions of the files directly in `folder` (not subfolders) whose contents are text,
    /// among the extensions `isCandidate` accepts. Each extension is decided by the first of
    /// its files that is non-empty and readable, from the first `Classifier.sampleSize` bytes.
    public static func textExtensions(in folder: URL, isCandidate: (String) -> Bool) -> [String] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        // An enumerator stops after `entryLimit`; listing the whole folder first takes seconds and
        // hundreds of MB in a folder of hundreds of thousands of files.
        guard let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsSubdirectoryDescendants]) else { return [] }
        var order = [String](), samples = [String: [URL]](), rejected = Set<String>()
        var seen = 0
        while seen < entryLimit, let url = enumerator.nextObject() as? URL {
            seen += 1
            guard let ext = ExtensionList.normalize(url.pathExtension), !rejected.contains(ext),
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true, (values.fileSize ?? 0) > 0 else { continue }
            if samples[ext] == nil {
                guard isCandidate(ext) else { rejected.insert(ext); continue }
                samples[ext] = []
                order.append(ext)
            }
            if samples[ext]!.count < samplesPerExtension { samples[ext]!.append(url) }
        }
        return order.filter { ext in
            for url in samples[ext] ?? [] {
                guard let kind = try? Classifier.classify(fileAt: url) else { continue }
                return kind != .binary
            }
            return false
        }
    }
}

/// How a preview extension asks the background helper to run a Folder Check.
@objc public protocol FolderCheckService {
    /// Replies as soon as the request is queued, not when the check is done.
    func checkFolder(_ path: String, reply: @escaping @Sendable () -> Void)
}

public enum FolderCheckClient {
    /// The helper's launchd Mach service; preview extensions may look it up through a
    /// `mach-lookup` temporary-exception entitlement.
    public static let machServiceName = "com.mdrum.infiniview.helper"

    /// Fire and forget: failures (helper not registered, not allowed to run) are ignored, since a
    /// Folder Check only ever saves the user a later right-click.
    public static func request(folder: URL) {
        nonisolated(unsafe) let connection = NSXPCConnection(machServiceName: machServiceName, options: [])
        connection.remoteObjectInterface = NSXPCInterface(with: FolderCheckService.self)
        connection.resume()
        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in connection.invalidate() }
        (proxy as? FolderCheckService)?.checkFolder(folder.path) { connection.invalidate() }
    }
}
