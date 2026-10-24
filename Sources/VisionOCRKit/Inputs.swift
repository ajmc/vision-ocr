import CoreGraphics
import Foundation
import ImageIO
import PDFKit

public enum InputError: LocalizedError, Equatable {
    case notFound(String)
    case unsupported(String)
    case unreadable(String)

    public var errorDescription: String? {
        switch self {
        case .notFound(let path): return "\(path): no such file or directory"
        case .unsupported(let path): return "\(path): not a supported image or PDF"
        case .unreadable(let path): return "\(path): could not be read"
        }
    }
}

/// An image or PDF to recognize. Multi-page TIFFs and PDFs have more than one page.
public struct InputFile: Equatable, Sendable {
    public enum Kind: Sendable { case image, pdf }

    public static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "tif", "tiff", "heic", "heif", "gif", "bmp", "webp", "jp2",
    ]

    public let url: URL
    public let kind: Kind
    /// The path as the user gave it (or as found under a folder they gave), for display in results.
    public let path: String

    public init?(path: String) {
        let ext = (path as NSString).pathExtension.lowercased()
        if ext == "pdf" {
            kind = .pdf
        } else if Self.imageExtensions.contains(ext) {
            kind = .image
        } else {
            return nil
        }
        self.path = path
        url = URL(fileURLWithPath: path)
    }

    /// Expands `paths` into supported files. Folders contribute their images and PDFs in natural sort order;
    /// a file named explicitly must be a supported type.
    public static func collect(_ paths: [String], recursive: Bool = false) throws -> [InputFile] {
        let fm = FileManager.default
        var files: [InputFile] = []
        for path in paths {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir) else { throw InputError.notFound(path) }
            if !isDir.boolValue {
                guard let file = InputFile(path: path) else { throw InputError.unsupported(path) }
                files.append(file)
                continue
            }
            var found: [String] = []
            let walker = fm.enumerator(atPath: path)
            while let sub = walker?.nextObject() as? String {
                let name = (sub as NSString).lastPathComponent
                let isFolder = (walker?.fileAttributes?[.type] as? FileAttributeType) == .typeDirectory
                if name.hasPrefix(".") || (isFolder && !recursive) {
                    if isFolder { walker?.skipDescendants() }
                    continue
                }
                if !isFolder { found.append(sub) }
            }
            files += found
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                .compactMap { InputFile(path: (path as NSString).appendingPathComponent($0)) }
        }
        return files
    }

    public func pageCount() throws -> Int {
        switch kind {
        case .pdf:
            guard let doc = PDFDocument(url: url) else { throw InputError.unreadable(url.path) }
            return doc.pageCount
        case .image:
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw InputError.unreadable(url.path) }
            return CGImageSourceGetCount(source)
        }
    }

    /// Loads page `index` (0-based). PDF pages are rendered at `dpi`.
    public func page(_ index: Int, dpi: Double = 300) throws -> (image: CGImage, orientation: CGImagePropertyOrientation) {
        switch kind {
        case .pdf:
            // The page must not outlive its document while drawing, so keep `doc` in scope.
            guard let doc = PDFDocument(url: url), let page = doc.page(at: index),
                  let image = withExtendedLifetime(doc, { PDFRenderer.render(page, dpi: dpi) })
            else { throw InputError.unreadable(url.path) }
            return (image, .up)
        case .image:
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { throw InputError.unreadable(url.path) }
            let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let raw = (props?[kCGImagePropertyOrientation] as? UInt32) ?? 1
            return (image, CGImagePropertyOrientation(rawValue: raw) ?? .up)
        }
    }
}

public enum PDFRenderer {
    /// The longest side, in pixels, a rendered page may have; larger pages are rendered at a lower DPI.
    public static let maxDimension = 10_000.0

    /// Renders `page` on a white background at `dpi`, honoring the page's rotation.
    public static func render(_ page: PDFPage, dpi: Double) -> CGImage? {
        var size = page.bounds(for: .mediaBox).size
        if page.rotation % 180 != 0 {
            size = CGSize(width: size.height, height: size.width)
        }
        var scale = dpi / 72
        scale = min(scale, maxDimension / max(size.width, size.height, 1))
        let width = Int((size.width * scale).rounded()), height = Int((size.height * scale).rounded())
        guard width > 0, height > 0,
              let ctx = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: ctx)
        return ctx.makeImage()
    }
}
