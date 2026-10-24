// Generates the sample files in examples/: a scan-like PNG and a two-page PDF (the second page rotated).
// Usage: swift Scripts/make-samples.swift [output dir]   (default: examples)
import AppKit
import CoreText
import Foundation

let outDir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "examples", isDirectory: true)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let notice = """
HARBOUR BOARD — PUBLIC NOTICE

From the first of March the north light
will burn from sunset until half an hour
after sunrise. Vessels entering after dark
should keep the red sector to port and
sound two long blasts off the breakwater.

Pilotage fees remain at four shillings per
foot of draught. Masters are reminded that
the inner basin is closed at low water.

By order of the Board, 12th February 1923.
"""

/// Draws `text` top-down inside `rect` of a y-up context.
func draw(_ text: String, in rect: CGRect, ctx: CGContext, font: String, size: CGFloat, color: CGColor) {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont(name: font, size: size) ?? NSFont.systemFont(ofSize: size),
        .foregroundColor: NSColor(cgColor: color)!,
    ]
    let framesetter = CTFramesetterCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
    let frame = CTFramesetterCreateFrame(framesetter, CFRange(), CGPath(rect: rect, transform: nil), nil)
    CTFrameDraw(frame, ctx)
}

// Scan-like image: off-white paper, faded ink, a slight skew, and specks.
let width = 1400, height = 1100
let ctx = CGContext(
    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
)!
ctx.setFillColor(CGColor(red: 0.93, green: 0.90, blue: 0.82, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
var rng = SystemRandomNumberGenerator()
for _ in 0..<2500 {
    let gray = CGFloat.random(in: 0.35...0.8, using: &rng)
    ctx.setFillColor(CGColor(red: gray, green: gray * 0.95, blue: gray * 0.85, alpha: CGFloat.random(in: 0.2...0.7, using: &rng)))
    let r = CGFloat.random(in: 0.5...2.2, using: &rng)
    ctx.fillEllipse(in: CGRect(x: .random(in: 0...CGFloat(width), using: &rng), y: .random(in: 0...CGFloat(height), using: &rng), width: r, height: r))
}
ctx.saveGState()
ctx.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
ctx.rotate(by: -0.012)
ctx.translateBy(x: -CGFloat(width) / 2, y: -CGFloat(height) / 2)
draw(notice, in: CGRect(x: 110, y: 80, width: 1200, height: 940), ctx: ctx,
     font: "Baskerville", size: 40, color: CGColor(red: 0.22, green: 0.18, blue: 0.14, alpha: 0.88))
ctx.restoreGState()
let png = NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
try png.write(to: outDir.appendingPathComponent("sample.png"))

// Two-page PDF: a text page, then a landscape table stored as a portrait page with /Rotate 90.
let pdfURL = outDir.appendingPathComponent("sample.pdf")
var box = CGRect(x: 0, y: 0, width: 612, height: 792)
let pdf = CGContext(pdfURL as CFURL, mediaBox: &box, nil)!
pdf.beginPDFPage(nil)
draw(notice, in: box.insetBy(dx: 72, dy: 72), ctx: pdf, font: "Times New Roman", size: 18, color: .black)
pdf.endPDFPage()

let table = """
TIDE TABLE — WEEK 9

Mon   High 04:12   Low 10:31   High 16:40
Tue   High 05:01   Low 11:20   High 17:28
Wed   High 05:49   Low 12:07   High 18:15
"""
pdf.beginPDFPage([kCGPDFContextMediaBox: Data(bytes: &box, count: MemoryLayout<CGRect>.size)] as CFDictionary)
// Content is drawn rotated 90° counter-clockwise so that a viewer applying /Rotate 90 shows it upright.
pdf.translateBy(x: box.width, y: 0)
pdf.rotate(by: .pi / 2)
draw(table, in: CGRect(x: 72, y: 72, width: box.height - 144, height: box.width - 144), ctx: pdf,
     font: "Menlo", size: 16, color: .black)
pdf.endPDFPage()
pdf.closePDF()

// CGContext can't set /Rotate, so set it with PDFKit.
import PDFKit
let doc = PDFDocument(url: pdfURL)!
doc.page(at: 1)!.rotation = 90
doc.write(to: pdfURL)
print("wrote \(outDir.path)/sample.png and sample.pdf")
