// Sandboxed benchmark: each preview request runs the highlighting benchmark on that file,
// appends the result row to bench.tsv in the container, and shows it.
import Foundation
import QuickLookUI

@objc(PreviewProvider)
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let assets = Bundle.main.resourceURL!.appendingPathComponent("assets")
        let place = Bundle.main.object(forInfoDictionaryKey: "BenchVariant") as? String ?? "appex"
        let row: String
        do { row = try Bench.run(request.fileURL, where: place, assets: assets) } catch { row = "\(place)\t\(request.fileURL.lastPathComponent)\terror \(error)" }
        let log = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("bench.tsv")
        if let h = try? FileHandle(forWritingTo: log) { h.seekToEndOfFile(); h.write(Data((row + "\n").utf8)); try? h.close() }
        else { try? Data((row + "\n").utf8).write(to: log) }
        return QLPreviewReply(dataOfContentType: .plainText, contentSize: CGSize(width: 800, height: 200)) { _ in Data(row.utf8) }
    }
}
