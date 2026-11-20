import AppKit
import InfiniviewCore

/// What a Preview shows for one file, decided from its bytes.
public enum PreviewContent {
    case text(TextDocument)
    case rtf(NSAttributedString)
    case card(FallbackCard)

    public struct TextDocument {
        public var text: String
        public var language: Language?
        public var shownBytes: Int
        public var totalBytes: Int
        public var isTruncated: Bool { shownBytes < totalBytes }
        public var isMarkdown: Bool { language?.id == "markdown" }
    }

    public static func load(_ url: URL, languages: LanguageIndex, maxShownBytes: Int = PreviewLimits.maxShownBytes) throws -> PreviewContent {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey])
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let total = values.fileSize ?? 0
        let sample = try handle.read(upToCount: Classifier.sampleSize) ?? Data()
        switch Classifier.classify(sample: sample, isTruncated: total > sample.count) {
        case .binary:
            return .card(FallbackCard(head: sample.prefix(FallbackCard.hexDumpBytes), size: total,
                                      created: values.creationDate, modified: values.contentModificationDate))
        case .rtf:
            let data = sample + (try handle.readToEnd() ?? Data())
            if let rtf = NSAttributedString(rtf: data, documentAttributes: nil) { return .rtf(rtf) }
            return .text(TextDocument(text: String(decoding: data, as: UTF8.self), language: nil,
                                      shownBytes: data.count, totalBytes: total))
        case .text(let encoding):
            var data = sample
            if total > sample.count, maxShownBytes > sample.count {
                data += try handle.read(upToCount: maxShownBytes - sample.count) ?? Data()
            }
            data = data.prefix(maxShownBytes)
            var text = Classifier.decode(data, as: encoding)
            // A cut can split the last character; drop the replacement character it leaves.
            if data.count < total, text.last == "\u{FFFD}" { text.removeLast() }
            let language = languages.detect(fileName: url.lastPathComponent, text: String(text.prefix(4096)))
            return .text(TextDocument(text: text, language: language, shownBytes: data.count, totalBytes: total))
        }
    }
}
