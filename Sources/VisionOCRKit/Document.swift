import Foundation

extension InputFile {
    /// Recognizes every page of the file. Pages are processed in parallel; results keep page order.
    /// `progress` is called (from any thread) as each page finishes, with the number of pages done and the total.
    public func recognize(
        options: RecognitionOptions = .init(),
        dpi: Double = 300,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) throws -> DocumentResult {
        let count = try pageCount()
        var pages = [Result<PageResult, Error>?](repeating: nil, count: count)
        let lock = NSLock()
        var done = 0
        DispatchQueue.concurrentPerform(iterations: count) { index in
            let result = Result { () -> PageResult in
                try autoreleasepool {
                    let (image, orientation) = try page(index, dpi: dpi)
                    let lines = try Recognizer.recognize(image, orientation: orientation, options: options)
                    // Orientations 5...8 rotate the image a quarter turn.
                    let rotated = orientation.rawValue >= 5
                    return PageResult(
                        page: index + 1,
                        width: rotated ? image.height : image.width,
                        height: rotated ? image.width : image.height,
                        lines: lines
                    )
                }
            }
            lock.lock()
            pages[index] = result
            done += 1
            let finished = done
            lock.unlock()
            progress?(finished, count)
        }
        return DocumentResult(file: path, pages: try pages.map { try $0!.get() })
    }
}
