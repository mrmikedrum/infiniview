import Foundation

/// A language Infiniview can highlight: VS Code's language id and its TextMate grammar's scope.
public struct Language: Sendable, Equatable, Codable {
    public var id: String
    public var scopeName: String
    public var extensions: [String] = []
    public var filenames: [String] = []
    public var filenamePatterns: [String] = []
    public var firstLine: String?

    public init(id: String, scopeName: String, extensions: [String] = [], filenames: [String] = [],
                filenamePatterns: [String] = [], firstLine: String? = nil) {
        self.id = id; self.scopeName = scopeName; self.extensions = extensions
        self.filenames = filenames; self.filenamePatterns = filenamePatterns; self.firstLine = firstLine
    }
}

/// The bundled language definitions (`languages.json`) and the rules for picking one for a file.
///
/// Order, as in VS Code: exact file name, file-name pattern, longest matching extension, then the
/// contents: the language's own first-line pattern, a shebang, an `<?xml` prolog, valid JSON.
public struct LanguageIndex: Sendable {
    public let languages: [Language]
    public let injections: [String: [String]]

    private let byFileName: [String: Language]
    private let suffixes: [(suffix: String, language: Language)] // longest first

    public init(languages: [Language], injections: [String: [String]] = [:]) {
        self.languages = languages
        self.injections = injections
        var names = [String: Language]()
        var suffixes = [(String, Language)]()
        for l in languages {
            for n in l.filenames where names[n.lowercased()] == nil { names[n.lowercased()] = l }
            for e in l.extensions where !e.contains("*") && !e.contains("?") { suffixes.append(("." + e.lowercased(), l)) }
        }
        byFileName = names
        self.suffixes = suffixes.sorted { $0.0.count > $1.0.count }
    }

    public init(json: Data) throws {
        struct File: Decodable { var languages: [Language]; var injections: [String: [String]]? }
        let f = try JSONDecoder().decode(File.self, from: json)
        self.init(languages: f.languages, injections: f.injections ?? [:])
    }

    public func language(id: String) -> Language? { languages.first { $0.id == id } }

    /// - Parameter text: the start of the file (a few KB is enough), or the whole of a small file.
    public func detect(fileName: String, text: String) -> Language? {
        let name = fileName.lowercased()
        if let l = byFileName[name] { return l }
        for l in languages where l.filenamePatterns.contains(where: { Self.glob($0.lowercased(), matches: name) }) { return l }
        // A dotfile's own name counts as its extension (".bashrc" matches "bashrc").
        if let hit = suffixes.first(where: { name.hasSuffix($0.suffix) }) { return hit.language }
        return detect(contents: text)
    }

    func detect(contents text: String) -> Language? {
        let firstLine = String(text.prefix(while: { $0 != "\n" && $0 != "\r" }).prefix(1000))
        if firstLine.hasPrefix("#!"), let l = shebang(firstLine) { return l }
        for l in languages {
            if let p = l.firstLine, let re = try? NSRegularExpression(pattern: p),
               re.firstMatch(in: firstLine, range: NSRange(firstLine.startIndex..., in: firstLine)) != nil { return l }
        }
        let trimmed = text.drop(while: { $0.isWhitespace })
        if trimmed.hasPrefix("<?xml") { return language(id: "xml") }
        if trimmed.first == "{" || trimmed.first == "[",
           (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8), options: [.fragmentsAllowed])) != nil {
            return language(id: "json")
        }
        return nil
    }

    /// Interpreter names to languages, for shebangs no language's own pattern caught.
    static let interpreters: [String: String] = [
        "sh": "shellscript", "bash": "shellscript", "zsh": "shellscript", "ksh": "shellscript", "dash": "shellscript",
        "ash": "shellscript", "csh": "shellscript", "tcsh": "shellscript",
        "python": "python", "ruby": "ruby", "perl": "perl", "php": "php", "lua": "lua",
        "node": "javascript", "deno": "typescript", "bun": "javascript", "ts-node": "typescript",
        "rscript": "r", "pwsh": "powershell", "swift": "swift", "groovy": "groovy", "julia": "julia",
        "make": "makefile",
    ]

    private func shebang(_ line: String) -> Language? {
        var words = line.dropFirst(2).split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard !words.isEmpty else { return nil }
        if words[0].hasSuffix("/env") {
            words.removeFirst()
            words.removeAll { $0.hasPrefix("-") } // env -S, -i, ...
        }
        guard var program = words.first?.split(separator: "/").last.map({ String($0).lowercased() }) else { return nil }
        // python3.12, ruby2 -> python, ruby
        if Self.interpreters[program] == nil { program = String(program.prefix(while: { !$0.isNumber && $0 != "." })) }
        return Self.interpreters[program].flatMap { language(id: $0) }
    }

    /// `*` matches any run of characters, `?` one character. Patterns here are file names only.
    static func glob(_ pattern: String, matches name: String) -> Bool {
        var re = "^"
        for c in pattern {
            switch c {
            case "*": re += ".*"
            case "?": re += "."
            default: re += NSRegularExpression.escapedPattern(for: String(c))
            }
        }
        return name.range(of: re + "$", options: .regularExpression) != nil
    }
}
