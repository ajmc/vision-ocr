import CoreGraphics
import Foundation
import ImageIO
import Vision

public struct RecognitionOptions: Sendable {
    /// BCP 47 language codes in priority order, e.g. `["en-US", "fr-FR"]`. Empty uses Vision's default.
    public var languages: [String] = []
    /// Use Vision's fast recognizer instead of the accurate one.
    public var fast = false
    /// Let Vision correct recognized words against its language model.
    public var languageCorrection = true
    /// Drop lines whose confidence is below this value (0...1).
    public var minimumConfidence: Float = 0

    public init(languages: [String] = [], fast: Bool = false, languageCorrection: Bool = true, minimumConfidence: Float = 0) {
        self.languages = languages
        self.fast = fast
        self.languageCorrection = languageCorrection
        self.minimumConfidence = minimumConfidence
    }
}

public enum Recognizer {
    /// Recognizes the text in `image` and returns its lines in reading order.
    public static func recognize(
        _ image: CGImage,
        orientation: CGImagePropertyOrientation = .up,
        options: RecognitionOptions = .init()
    ) throws -> [TextLine] {
        let request = makeRequest(options)
        try VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:]).perform([request])
        let lines = (request.results ?? []).compactMap { observation -> TextLine? in
            guard let candidate = observation.topCandidates(1).first,
                  candidate.confidence >= options.minimumConfidence else { return nil }
            // Vision's boxes are normalized with the origin at the bottom-left; flip to top-left.
            let b = observation.boundingBox
            let box = BoundingBox(
                x: rounded(b.minX), y: rounded(1 - b.maxY),
                width: rounded(b.width), height: rounded(b.height)
            )
            return TextLine(text: candidate.string, confidence: candidate.confidence, box: box)
        }
        return readingOrder(lines)
    }

    /// The language codes Vision can recognize with the given recognizer.
    public static func supportedLanguages(fast: Bool) throws -> [String] {
        try makeRequest(RecognitionOptions(fast: fast)).supportedRecognitionLanguages()
    }

    /// Groups lines into rows (lines whose vertical centers overlap) and sorts top to bottom, then left to right.
    public static func rows(_ lines: [TextLine]) -> [[TextLine]] {
        var rows: [[TextLine]] = []
        for line in lines.sorted(by: { $0.box.midY < $1.box.midY }) {
            if let first = rows.last?.first,
               abs(line.box.midY - first.box.midY) < min(line.box.height, first.box.height) / 2 {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows.map { $0.sorted { $0.box.x < $1.box.x } }
    }

    public static func readingOrder(_ lines: [TextLine]) -> [TextLine] {
        rows(lines).flatMap { $0 }
    }

    private static func makeRequest(_ options: RecognitionOptions) -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = options.fast ? .fast : .accurate
        request.usesLanguageCorrection = options.languageCorrection
        if !options.languages.isEmpty {
            request.recognitionLanguages = options.languages
        }
        return request
    }

    private static func rounded(_ value: CGFloat) -> Double {
        (Double(value) * 10_000).rounded() / 10_000
    }
}
