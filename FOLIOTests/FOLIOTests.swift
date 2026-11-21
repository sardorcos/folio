import XCTest
import PDFKit
import UIKit
@testable import FOLIO

final class FOLIOTests: XCTestCase {
    func testFileSizeDescriptionIsNonEmpty() {
        let file = FolioDocument(id: UUID(), title: "Test", relativePath: "test.pdf",
                                 kind: .source, origin: .pdf, pageCount: 4,
                                 byteCount: 2048, createdAt: Date())
        XCTAssertTrue(file.summary.contains("4 стр."))
    }

    func testQualityTextExplainsLimitations() {
        XCTAssertTrue(PDFQuality.smallerPhotos.subtitle.contains("качество"))
        XCTAssertTrue(PDFQuality.original.title.contains("Исходное"))
    }

    func testDraftPreservesOrderAndRotationWhenCodable() throws {
        let pages = [
            FolioDraftPage(id: UUID(), documentID: UUID(), pageIndex: 2, rotation: 90),
            FolioDraftPage(id: UUID(), documentID: UUID(), pageIndex: 0, rotation: 0)
        ]
        let encoded = try JSONEncoder().encode(pages)
        let decoded = try JSONDecoder().decode([FolioDraftPage].self, from: encoded)
        XCTAssertEqual(decoded, pages)
    }

    func testWorkflowsContainRealFileActions() {
        XCTAssertEqual(FolioSavedWorkflow.defaults.count, 3)
        XCTAssertEqual(FolioSavedWorkflow.defaults[0].targetMB, 5)
    }

    func testLocalPDFExportsAllPages() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = PDFDocument()
        guard let page = PDFPage(image: UIImage(systemName: "doc.fill")!) else {
            XCTFail("Cannot create PDF page")
            return
        }
        source.insert(page, at: 0)
        let input = directory.appendingPathComponent("sample.pdf")
        XCTAssertTrue(source.write(to: input))
        let id = UUID()
        let file = FolioDocument(id: id, title: "Sample", relativePath: "sample.pdf",
                                 kind: .source, origin: .pdf, pageCount: 1,
                                 byteCount: try PDFWorker.byteCount(for: input), createdAt: Date())
        let output = directory.appendingPathComponent("output.pdf")
        _ = try PDFWorker.export(pages: [FolioDraftPage(id: UUID(), documentID: id, pageIndex: 0)],
                                 documents: [file], directory: directory, destination: output,
                                 quality: .original)
        XCTAssertEqual(PDFDocument(url: output)?.pageCount, 1)
    }
}
