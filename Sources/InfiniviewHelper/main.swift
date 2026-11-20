import Foundation
import InfiniviewCore
import InfiniviewSystem
import UniformTypeIdentifiers

// The background helper (ADR-0005). launchd starts it when a preview extension connects to its
// Mach service; it runs Folder Checks one at a time and exits after a while with nothing to do.

/// Runs Folder Checks on one serial queue.
final class FolderChecker: @unchecked Sendable {
    /// A folder isn't checked again within this long unless it has changed.
    static let recheckInterval: TimeInterval = 30
    /// The helper exits after this long without a request; launchd restarts it on the next one.
    static let idleExit: TimeInterval = 300

    private let queue = DispatchQueue(label: "com.mdrum.infiniview.folder-check")
    private var lastChecked = [String: (at: Date, modified: Date?)]()
    private var idleTimer: DispatchSourceTimer?

    func enqueue(_ path: String) {
        queue.async { self.check(URL(fileURLWithPath: path, isDirectory: true)) }
    }

    private func check(_ folder: URL) {
        defer { resetIdleTimer() }
        let modified = try? folder.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        if let last = lastChecked[folder.path], last.modified == modified,
           Date().timeIntervalSince(last.at) < Self.recheckInterval { return }
        lastChecked[folder.path] = (Date(), modified)

        let settings = SharedSettings()
        settings.synchronize()
        var learned = settings.learnedExtensions(builtIn: BuiltInList.extensions)
        let start = Date()
        let found = FolderCheck.textExtensions(in: folder) { ext in
            // Only extensions macOS has no type for, that the user hasn't removed.
            (UTType(filenameExtension: ext)?.isDynamic ?? true) && !learned.isDismissed(ext) && !learned.isLearned(ext)
        }
        let new = found.filter { learned.learnAutomatically($0) }
        if !new.isEmpty {
            settings.save(learned)
            LearnedTypeRegistrar.apply(learned.effective)
        }
        log(settings, "\(folder.path)\tlearned: \(new.joined(separator: " "))\t\(Int(Date().timeIntervalSince(start) * 1000))ms")
    }

    private func resetIdleTimer() {
        idleTimer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + Self.idleExit)
        t.setEventHandler { exit(0) }
        t.resume()
        idleTimer = t
    }

    /// With `debugLog` on, one line per Folder Check in ~/Library/Logs/Infiniview-helper.log.
    private func log(_ settings: SharedSettings, _ line: String) {
        guard settings.debugLog else { return }
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Infiniview-helper.log")
        let stamped = ISO8601DateFormatter().string(from: Date()) + "\t" + line + "\n"
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(Data(stamped.utf8))
            try? h.close()
        } else {
            try? Data(stamped.utf8).write(to: url)
        }
    }

    func start() { queue.async { self.resetIdleTimer() } }
}

final class Service: NSObject, FolderCheckService {
    let checker: FolderChecker
    init(checker: FolderChecker) { self.checker = checker }

    func checkFolder(_ path: String, reply: @escaping @Sendable () -> Void) {
        reply()
        checker.enqueue(path)
    }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    let checker = FolderChecker()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // Only Infiniview's own preview extensions may ask.
        connection.setCodeSigningRequirement(
            #"identifier "com.mdrum.infiniview.preview" or identifier "com.mdrum.infiniview.takeover""#)
        connection.exportedInterface = NSXPCInterface(with: FolderCheckService.self)
        connection.exportedObject = Service(checker: checker)
        connection.resume()
        return true
    }
}

let delegate = ListenerDelegate()
let listener = NSXPCListener(machServiceName: FolderCheckClient.machServiceName)
listener.delegate = delegate
listener.resume()
delegate.checker.start()
dispatchMain()
