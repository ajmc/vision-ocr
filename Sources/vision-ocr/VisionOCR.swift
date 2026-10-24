import ArgumentParser
import Foundation
import VisionOCRKit

extension OutputFormat: ExpressibleByArgument {}

@main
struct VisionOCR: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "vision-ocr",
        abstract: "Recognize text in images and PDFs with Apple's Vision framework.",
        discussion: """
        Inputs can be image files (PNG, JPEG, TIFF, HEIC, ...), PDFs, or folders of them. \
        Results go to stdout unless --output-dir is given, in which case each input gets its own file.
        """,
        version: "0.1.0"
    )

    @Argument(help: "Image files, PDFs, or folders.", completion: .file())
    var inputs: [String] = []

    @Option(name: .shortAndLong, help: "Output format: text, tsv (with bounding boxes and confidence), or json.")
    var format: OutputFormat = .text

    @Option(
        name: [.short, .customLong("language")],
        help: ArgumentHelp("Recognition language, in priority order. Repeat or comma-separate.", valueName: "code")
    )
    var languages: [String] = []

    @Flag(help: "Use the fast recognizer instead of the accurate one.")
    var fast = false

    @Flag(inversion: .prefixedNo, help: "Correct recognized words with Vision's language model.")
    var languageCorrection = true

    @Option(name: .customLong("min-confidence"), help: "Drop lines with confidence below this value (0-1).")
    var minConfidence: Float = 0

    @Option(help: "Resolution at which PDF pages are rendered.")
    var dpi: Double = 300

    @Option(name: [.short, .customLong("output-dir")], help: "Write one output file per input into this folder.", completion: .directory)
    var outputDir: String?

    @Flag(name: .shortAndLong, help: "Include images and PDFs in subfolders.")
    var recursive = false

    @Flag(help: "List the recognition languages Vision supports and exit.")
    var listLanguages = false

    @Flag(name: .shortAndLong, help: "Report progress on stderr.")
    var verbose = false

    func validate() throws {
        if inputs.isEmpty && !listLanguages { throw ValidationError("Give at least one image, PDF, or folder.") }
        if !(36...1200).contains(dpi) { throw ValidationError("--dpi must be between 36 and 1200.") }
        if !(0...1).contains(minConfidence) { throw ValidationError("--min-confidence must be between 0 and 1.") }
    }

    func run() throws {
        if listLanguages {
            print(try Recognizer.supportedLanguages(fast: fast).joined(separator: "\n"))
            return
        }
        let files = try InputFile.collect(inputs, recursive: recursive)
        guard !files.isEmpty else { throw ValidationError("No images or PDFs found in \(inputs.joined(separator: ", ")).") }

        let options = RecognitionOptions(
            languages: languages.flatMap { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } },
            fast: fast,
            languageCorrection: languageCorrection,
            minimumConfidence: minConfidence
        )
        let outDir = outputDir.map { URL(fileURLWithPath: $0, isDirectory: true) }
        if let outDir {
            try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        } else if format == .tsv {
            print(OutputFormat.tsvHeader)
        }

        var documents: [DocumentResult] = []
        var usedNames: Set<String> = []
        var failures = 0
        for (i, file) in files.enumerated() {
            let verbose = self.verbose
            let doc: DocumentResult
            do {
                doc = try file.recognize(options: options, dpi: dpi) { done, total in
                    if verbose { log("\(file.path): page \(done)/\(total)") }
                }
            } catch {
                log("vision-ocr: \(error.localizedDescription)")
                failures += 1
                continue
            }

            if let outDir {
                let name = uniqueName(for: file.url, used: &usedNames)
                let dest = outDir.appendingPathComponent(name).appendingPathExtension(format.fileExtension)
                let body: String
                switch format {
                case .text: body = OutputFormat.text(doc)
                case .tsv: body = OutputFormat.tsvHeader + "\n" + OutputFormat.tsv(doc)
                case .json: body = try OutputFormat.json(doc)
                }
                try body.write(to: dest, atomically: true, encoding: .utf8)
                if verbose { log("wrote \(dest.path)") }
                continue
            }

            switch format {
            case .text:
                if files.count > 1 { print("\(i == 0 ? "" : "\n")==> \(file.path) <==") }
                print(OutputFormat.text(doc), terminator: "")
            case .tsv:
                print(OutputFormat.tsv(doc), terminator: "")
            case .json:
                documents.append(doc)
            }
        }
        if outDir == nil && format == .json {
            print(try OutputFormat.json(documents), terminator: "")
        }
        if failures > 0 { throw ExitCode.failure }
    }

    /// The input's file name, with a numeric suffix if an earlier input (in another folder) already used it.
    private func uniqueName(for url: URL, used: inout Set<String>) -> String {
        let base = url.lastPathComponent
        var name = base
        var n = 2
        while used.contains(name) {
            name = "\(base)-\(n)"
            n += 1
        }
        used.insert(name)
        return name
    }
}

private func log(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}
