import PDFKit
import XCTest
@testable import FOLIO

final class PDFWorkerTests: XCTestCase {
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

    func testImportPDFCopiesOriginal() throws {
        let input = directory.appendingPathComponent("Договор.pdf")
        try Fixtures.makePDF(widths: [300, 400], at: input)
        let before = try Data(contentsOf: input)
        let document = try PDFWorker.importFile(url: input, id: UUID(), directory: library, tempDirectory: temp)
        XCTAssertEqual(document.title, "Договор")
        XCTAssertEqual(document.pageCount, 2)
        XCTAssertEqual(try Data(contentsOf: input), before, "Оригинал не должен меняться")
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.appendingPathComponent(document.relativePath).path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: temp.path).isEmpty, "Временные файлы удалены")
    }

    func testUnsupportedFileIsRejected() throws {
        let input = directory.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: input)
        XCTAssertThrowsError(try PDFWorker.importFile(url: input, id: UUID(), directory: library, tempDirectory: temp)) {
            XCTAssertEqual($0 as? FolioIssue, .unsupported)
        }
    }

    func testTooManyPagesHasCorrectError() throws {
        let input = directory.appendingPathComponent("big.pdf")
        try Fixtures.makePDF(widths: Array(repeating: 100, count: FolioLimits.draftPages + 1), at: input)
        XCTAssertThrowsError(try PDFWorker.importFile(url: input, id: UUID(), directory: library, tempDirectory: temp)) {
            XCTAssertEqual($0 as? FolioIssue, .tooManyPages(limit: FolioLimits.draftPages))
        }
    }

    func testPasswordProtectedPDF() throws {
        let input = directory.appendingPathComponent("secret.pdf")
        try Fixtures.makeEncryptedPDF(at: input, password: "1234")

        XCTAssertThrowsError(try PDFWorker.importFile(url: input, id: UUID(), directory: library, tempDirectory: temp)) {
            XCTAssertEqual($0 as? FolioIssue, .passwordProtected)
        }
        XCTAssertThrowsError(try PDFWorker.importFile(url: input, id: UUID(), password: "0000",
                                                      directory: library, tempDirectory: temp)) {
            XCTAssertEqual($0 as? FolioIssue, .wrongPassword)
        }
        let document = try PDFWorker.importFile(url: input, id: UUID(), password: "1234",
                                                directory: library, tempDirectory: temp)
        let stored = try XCTUnwrap(PDFDocument(url: library.appendingPathComponent(document.relativePath)))
        XCTAssertFalse(stored.isLocked, "В библиотеке хранится копия без пароля")
        XCTAssertEqual(stored.pageCount, 2)
    }

    func testImageImportUsesPaperSizeAndExifOrientation() throws {
        // 400×200 с EXIF-ориентацией 6 отображается как портрет 200×400.
        let input = directory.appendingPathComponent("photo.jpg")
        try Fixtures.makeJPEG(width: 400, height: 200, orientation: 6).write(to: input)
        let document = try PDFWorker.importFile(url: input, id: UUID(), directory: library, tempDirectory: temp)
        let pdf = try XCTUnwrap(PDFDocument(url: library.appendingPathComponent(document.relativePath)))
        let bounds = try XCTUnwrap(pdf.page(at: 0)).bounds(for: .mediaBox)
        XCTAssertGreaterThan(bounds.height, bounds.width, "Ориентация EXIF применена")
        XCTAssertLessThanOrEqual(max(bounds.width, bounds.height), 842.5, "Страница не больше A4/Letter")
        XCTAssertEqual(document.origin, .photo)
    }

    func testLargePhotoBecomesPaperSizedPage() throws {
        let jpeg = try Fixtures.makeJPEG(width: 4000, height: 3000)
        let document = try PDFWorker.importImages([.data(jpeg)], id: UUID(), title: "Фото", origin: .photo,
                                                  directory: library, tempDirectory: temp)
        let pdf = try XCTUnwrap(PDFDocument(url: library.appendingPathComponent(document.relativePath)))
        let bounds = try XCTUnwrap(pdf.page(at: 0)).bounds(for: .mediaBox)
        XCTAssertGreaterThan(bounds.width, bounds.height)
        XCTAssertLessThanOrEqual(bounds.width, 842.5)
    }

    func testExportKeepsAllPagesInOrder() throws {
        let input = directory.appendingPathComponent("sample.pdf")
        try Fixtures.makePDF(widths: [300, 400, 500], at: input)
        let source = try PDFWorker.importFile(url: input, id: UUID(), directory: library, tempDirectory: temp)
        let pages = [2, 0, 1].map { FolioDraftPage(id: UUID(), documentID: source.id, pageIndex: $0) }
        let output = library.appendingPathComponent("out.pdf")
        let outcome = try PDFWorker.export(pages: pages, documents: [source], directory: library, tempDirectory: temp,
                                           destination: output, title: "Итог", quality: .original, targetBytes: nil)
        XCTAssertEqual(try Fixtures.pageWidths(of: output), [500, 300, 400])
        XCTAssertFalse(outcome.usedCompression)
        XCTAssertEqual(PDFDocument(url: output)?.documentAttributes?[PDFDocumentAttribute.titleAttribute.rawValue] as? String, "Итог")
    }

    func testMaximumCompressionNeverGrowsFile() throws {
        let jpeg = try Fixtures.makeJPEG(width: 2400, height: 3200, noisy: true)
        let source = try PDFWorker.importImages([.data(jpeg), .data(jpeg)], id: UUID(), title: "Скан", origin: .scan,
                                                directory: library, tempDirectory: temp)
        let pages = (0..<2).map { FolioDraftPage(id: UUID(), documentID: source.id, pageIndex: $0) }
        let output = library.appendingPathComponent("small.pdf")
        let outcome = try PDFWorker.export(pages: pages, documents: [source], directory: library, tempDirectory: temp,
                                           destination: output, title: "Сжатый", quality: .smallerPhotos,
                                           targetBytes: 300_000)
        XCTAssertLessThanOrEqual(outcome.byteCount, outcome.uncompressedByteCount)
        XCTAssertTrue(outcome.usedCompression, "Шумное фото в 2400×3200 должно сжиматься")
        XCTAssertEqual(PDFDocument(url: output)?.pageCount, 2)
    }
}
