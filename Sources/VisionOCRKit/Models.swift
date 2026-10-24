import Foundation

/// A rectangle in normalized page coordinates: 0...1 on both axes, origin at the top-left corner.
public struct BoundingBox: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var midY: Double { y + height / 2 }
}

/// One line of recognized text.
public struct TextLine: Codable, Equatable, Sendable {
    public var text: String
    public var confidence: Float
    public var box: BoundingBox

    public init(text: String, confidence: Float, box: BoundingBox) {
        self.text = text
        self.confidence = confidence
        self.box = box
    }
}

/// The text recognized on one page (or one image), in reading order.
public struct PageResult: Codable, Equatable, Sendable {
    /// 1-based page number; always 1 for single-page images.
    public var page: Int
    /// Size in pixels of the image that was recognized.
    public var width: Int
    public var height: Int
    public var lines: [TextLine]

    public init(page: Int, width: Int, height: Int, lines: [TextLine]) {
        self.page = page
        self.width = width
        self.height = height
        self.lines = lines
    }
}

/// Every page recognized in one input file.
public struct DocumentResult: Codable, Equatable, Sendable {
    public var file: String
    public var pages: [PageResult]

    public init(file: String, pages: [PageResult]) {
        self.file = file
        self.pages = pages
    }
}
