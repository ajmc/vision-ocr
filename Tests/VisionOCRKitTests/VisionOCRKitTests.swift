import AppKit
import CoreText
import XCTest
@testable import VisionOCRKit

final class VisionOCRKitTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("vision-ocr-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: Recognition

    func testRecognizesRenderedText() throws {
        let image = try XCTUnwrap(Self.render(["Clear skies over the harbour", "Wind light from the west"]))
        let lines = try Recognizer.recognize(image)
        XCTAssertEqual(lines.map(\.text), ["Clear skies over the harbour", "Wind light from the west"])
        XCTAssertLessThan(lines[0].box.y, lines[1].box.y, "boxes use a top-left origin")
    }

    func testMinimumConfidenceDropsEverythingAboveOne() throws {
        let image = try XCTUnwrap(Self.render(["Nothing survives this filter"]))
        XCTAssertEqual(try Recognizer.recognize(image, options: .init(minimumConfidence: 1.01)), [])
    }

    func testRecognizesEveryPageOfAPDF() throws {
        let url = tmp.appendingPathComponent("two.pdf")
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let pdf = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, nil))
        for text in ["First page here", "Second page here"] {
            pdf.beginPDFPage(nil)
            Self.draw([text], in: box.insetBy(dx: 72, dy: 72), ctx: pdf, size: 28)
            pdf.endPDFPage()
        }
        pdf.closePDF()

        let file = try XCTUnwrap(InputFile(path: url.path))
        let doc = try file.recognize(dpi: 150)
        XCTAssertEqual(doc.pages.map(\.page), [1, 2])
        XCTAssertEqual(doc.pages.map { $0.lines.map(\.text) }, [["First page here"], ["Second page here"]])
        XCTAssertEqual(doc.pages[0].width, 1275) // 8.5 in at 150 dpi
    }

    // MARK: Reading order

    func testReadingOrderGroupsRowsLeftToRight() {
        let lines = [
            line("C", x: 0.1, y: 0.50),
            line("B", x: 0.6, y: 0.105),
            line("A", x: 0.1, y: 0.10),
        ]
        XCTAssertEqual(Recognizer.rows(lines).map { $0.map(\.text) }, [["A", "B"], ["C"]])
    }

    // MARK: Formats

    func testTextJoinsRowsMarksParagraphsAndSeparatesPages() {
        let doc = DocumentResult(file: "x.pdf", pages: [
            PageResult(page: 1, width: 100, height: 100, lines: [
                line("Name", x: 0.1, y: 0.10), line("Total", x: 0.6, y: 0.10),
                line("next", x: 0.1, y: 0.14),
                line("far below", x: 0.1, y: 0.40),
            ]),
            PageResult(page: 2, width: 100, height: 100, lines: [line("two", x: 0.1, y: 0.1)]),
        ])
        XCTAssertEqual(OutputFormat.text(doc), "Name  Total\nnext\n\nfar below\n\u{0C}two\n")
    }

    func testTSVEscapesSpecialCharacters() {
        let doc = DocumentResult(file: "a\tb.png", pages: [
            PageResult(page: 1, width: 10, height: 10, lines: [line("tab\there\nnewline", x: 0.25, y: 0.5)]),
        ])
        XCTAssertEqual(
            OutputFormat.tsv(doc),
            "a\\tb.png\t1\t0.2500\t0.5000\t0.3000\t0.0300\t1.000\ttab\\there\\nnewline\n"
        )
    }

    func testJSONRoundTrips() throws {
        let doc = DocumentResult(file: "a.png", pages: [PageResult(page: 1, width: 10, height: 20, lines: [line("hi", x: 0, y: 0)])])
        let decoded = try JSONDecoder().decode(DocumentResult.self, from: Data(try OutputFormat.json(doc).utf8))
        XCTAssertEqual(decoded, doc)
    }

    // MARK: Inputs

    func testCollectFindsSupportedFilesInFolders() throws {
        for name in ["b10.png", "b2.JPG", "notes.txt", "doc.pdf", ".hidden.png", "sub/deep.tiff"] {
            let url = tmp.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: url)
        }
        let names = { (files: [InputFile]) in files.map { ($0.path as NSString).lastPathComponent } }
        XCTAssertEqual(names(try InputFile.collect([tmp.path])), ["b2.JPG", "b10.png", "doc.pdf"])
        XCTAssertEqual(names(try InputFile.collect([tmp.path], recursive: true)), ["b2.JPG", "b10.png", "doc.pdf", "deep.tiff"])
        XCTAssertThrowsError(try InputFile.collect([tmp.appendingPathComponent("notes.txt").path]))
        XCTAssertThrowsError(try InputFile.collect([tmp.appendingPathComponent("missing.png").path]))
    }

    // MARK: Helpers

    private func line(_ text: String, x: Double, y: Double) -> TextLine {
        TextLine(text: text, confidence: 1, box: BoundingBox(x: x, y: y, width: 0.3, height: 0.03))
    }

    static func draw(_ lines: [String], in rect: CGRect, ctx: CGContext, size: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont(name: "Helvetica", size: size)!, .foregroundColor: NSColor.black]
        let text = NSAttributedString(string: lines.joined(separator: "\n"), attributes: attrs)
        let frame = CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(text), CFRange(), CGPath(rect: rect, transform: nil), nil)
        CTFrameDraw(frame, ctx)
    }

    static func render(_ lines: [String]) -> CGImage? {
        let width = 1200, height = 400
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        ctx.setFillColor(.white)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        draw(lines, in: CGRect(x: 40, y: 40, width: width - 80, height: height - 80), ctx: ctx, size: 48)
        return ctx.makeImage()
    }
}
