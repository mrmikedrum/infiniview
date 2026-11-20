// Spike preview extension: replies with plain text naming which extension answered,
// so `qlmanage -p -o` output shows who handled each file.
import Foundation
import QuickLookUI
import UniformTypeIdentifiers
import os

@objc(PreviewProvider)
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let url = request.fileURL
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType?.identifier) ?? "?"
        let role = Bundle.main.object(forInfoDictionaryKey: "SpikeRole") as? String ?? "?"
        let head = (try? FileHandle(forReadingFrom: url).read(upToCount: 64)) ?? Data()
        // Settings route check: host's defaults domain via a shared-preference read-only exception,
        // and a file in ~/Library/Application Support via a home-relative read-only exception.
        let pref = UserDefaults(suiteName: "com.mdrum.infiniview.spike")?.string(forKey: "probe") ?? "nil"
        let realHome = URL(fileURLWithPath: NSHomeDirectoryForUser(NSUserName()) ?? "")
        let fileSetting = (try? String(contentsOf: realHome.appendingPathComponent("Library/Application Support/InfiniviewSpike/settings.txt"), encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "nil"
        let line = "SPIKE pref=\(pref) file=\(fileSetting) role=\(role) type=\(type) file=\(url.lastPathComponent) bytes=\(head.count)"
        Logger(subsystem: "com.mdrum.infiniview.spike", category: role).log("\(line, privacy: .public)")
        // Non-admin users can't read the unified log, so also append to a file in the sandbox container.
        let log = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("spike.log")
        if let h = try? FileHandle(forWritingTo: log) { h.seekToEndOfFile(); h.write(Data((line + "\n").utf8)); try? h.close() }
        else { try? Data((line + "\n").utf8).write(to: log) }
        return QLPreviewReply(dataOfContentType: .plainText, contentSize: CGSize(width: 600, height: 200)) { _ in
            Data(line.utf8)
        }
    }
}
