import Foundation

public enum OutputFormat: String, CaseIterable, Sendable {
    case text, tsv, json

    public var fileExtension: String {
        switch self {
        case .text: return "txt"
        case .tsv: return "tsv"
        case .json: return "json"
        }
    }

    public static let tsvHeader = "file\tpage\tx\ty\twidth\theight\tconfidence\ttext"

    /// Plain text: one row of text per line, lines on the same row joined by two spaces, a blank line where the
    /// vertical gap suggests a paragraph break, and pages separated by a form feed (as `pdftotext` does).
    public static func text(_ doc: DocumentResult) -> String {
        doc.pages.map { page in
            var out: [String] = []
            var previous: [TextLine]?
            for row in Recognizer.rows(page.lines) {
                if let prev = previous {
                    let prevBottom = prev.map { $0.box.y + $0.box.height }.max()!
                    let top = row.map(\.box.y).min()!
                    let lineHeight = prev.map(\.box.height).max()!
                    if top - prevBottom > lineHeight { out.append("") }
                }
                out.append(row.map(\.text).joined(separator: "  "))
                previous = row
            }
            return out.joined(separator: "\n") + "\n"
        }.joined(separator: "\u{0C}")
    }

    /// TSV rows (without the header), one per line of text. Coordinates are normalized with a top-left origin.
    public static func tsv(_ doc: DocumentResult) -> String {
        doc.pages.flatMap { page in
            page.lines.map { line in
                [
                    escape(doc.file), String(page.page),
                    format(line.box.x), format(line.box.y), format(line.box.width), format(line.box.height),
                    String(format: "%.3f", line.confidence), escape(line.text),
                ].joined(separator: "\t") + "\n"
            }
        }.joined()
    }

    public static func json<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self) + "\n"
    }

    private static func format(_ value: Double) -> String { String(format: "%.4f", value) }

    private static func escape(_ field: String) -> String {
        field
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\t", with: "\\t")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}
