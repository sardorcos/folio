import PDFKit
import XCTest
@testable import FOLIO

final class OCRTests: XCTestCase {
    private var directory: URL!
    private var library: URL!
    private var temp: URL!

    override func setUpWithError() throws {
        directory = try Fixtures.temporaryDirectory()
        library = directory.appendingPathComponent("Files", isDirectory: true)
        temp = directory.appendingPathComponent("Temp", isDirectory: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testRecognizesPrintedText() throws {
        try Fixtures.requireTextRecognition()
        let image = try XCTUnwrap(UIImage(data: try Fixtures.makeTextImage())?.cgImage)
        let text = try TextRecognizer.recognizeLines(in: image).map(\.text).joined(separator: " ")
        XCTAssertTrue(text.contains("FOLIO"), "Распознано: \(text)")
        XCTAssertTrue(text.contains("2026"), "Распознано: \(text)")
    }

    func testPhotoImportAddsSearchableTextLayer() throws {
        try Fixtures.requireTextRecognition()
        let jpeg = try Fixtures.makeTextImage()
        let document = try PDFWorker.importImages([.data(jpeg)], id: UUID(), title: "Скан", origin: .scan, ocr: true,
                                                  directory: library, tempDirectory: temp)
        let url = library.appendingPathComponent(document.relativePath)
        XCTAssertTrue(PDFWorker.extractText(from: url).contains("2026"))
        XCTAssertEqual(PDFWorker.pagesWithoutText(at: url), 0)
    }

    func testWithoutOCRPhotoHasNoText() throws {
        let jpeg = try Fixtures.makeTextImage()
        let document = try PDFWorker.importImages([.data(jpeg)], id: UUID(), title: "Фото", origin: .photo, ocr: false,
                                                  directory: library, tempDirectory: temp)
        let url = library.appendingPathComponent(document.relativePath)
        XCTAssertEqual(PDFWorker.pagesWithoutText(at: url), 1)
    }

    func testSearchableCopyKeepsTextPagesAndRecognizesScans() throws {
        try Fixtures.requireTextRecognition()
        // Документ из страницы со скан-изображением и обычной текстовой страницы.
        let scan = try PDFWorker.importImages([.data(try Fixtures.makeTextImage())], id: UUID(), title: "Скан",
                                              origin: .scan, ocr: false, directory: library, tempDirectory: temp)
        let textPDF = directory.appendingPathComponent("text.pdf")
        try Fixtures.makePDF(widths: [400], at: textPDF)
        let combined = try XCTUnwrap(PDFDocument(url: library.appendingPathComponent(scan.relativePath)))
        let textPage = try XCTUnwrap(PDFDocument(url: textPDF)?.page(at: 0)?.copy() as? PDFPage)
        combined.insert(textPage, at: 1)
        let mixed = directory.appendingPathComponent("mixed.pdf")
        XCTAssertTrue(combined.write(to: mixed))

        let outcome = try PDFWorker.makeSearchableCopy(of: mixed, id: UUID(), title: "С текстом",
                                                       directory: library, tempDirectory: temp)
        XCTAssertEqual(outcome.recognizedPages, 1)
        XCTAssertEqual(outcome.document.pageCount, 2)
        let text = PDFWorker.extractText(from: library.appendingPathComponent(outcome.document.relativePath))
        XCTAssertTrue(text.contains("2026"))
        XCTAssertTrue(text.contains("Страница 1"), "Текстовая страница скопирована без изменений")
    }

    func testMaximumCompressionWithOCRKeepsText() throws {
        try Fixtures.requireTextRecognition()
        let input = directory.appendingPathComponent("photo.jpg")
        try Fixtures.makeTextImage().write(to: input)
        let source = try PDFWorker.importFile(url: input, id: UUID(), ocr: false, directory: library, tempDirectory: temp)
        let output = library.appendingPathComponent("max.pdf")
        _ = try PDFWorker.export(pages: [FolioDraftPage(id: UUID(), documentID: source.id, pageIndex: 0)],
                                 documents: [source], directory: library, tempDirectory: temp,
                                 destination: output, title: "Макс", quality: .maximum, targetBytes: nil, ocr: true)
        XCTAssertTrue(PDFWorker.extractText(from: output).contains("2026"))
    }
}
