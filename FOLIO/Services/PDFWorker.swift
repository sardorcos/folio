import Foundation
import PDFKit
import UIKit
import UniformTypeIdentifiers

/// PDF-операции выполняются на локальных файлах. Сеть не используется.
enum PDFWorker {
    static let importLimit: Int64 = 40 * 1024 * 1024
    static let pageLimit = 100

    static func importFile(url: URL, id: UUID, directory: URL) throws -> FolioDocument {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let originalSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard originalSize <= importLimit else { throw FolioIssue.tooLarge }
        let ext = url.pathExtension.lowercased()
        let relativePath = "\(id.uuidString).pdf"
        let target = directory.appendingPathComponent(relativePath)
        let origin: FileOrigin
        let count: Int

        switch ext {
        case "pdf":
            guard let original = PDFDocument(url: url), !original.isEncrypted || original.isUnlocked else {
                throw FolioIssue.corruptedPDF
            }
            count = original.pageCount
            guard count > 0 else { throw FolioIssue.emptyPDF }
            guard count <= pageLimit else { throw FolioIssue.tooLarge }
            // Copy instead of moving: imported user's original is never modified.
            try FileManager.default.copyItem(at: url, to: target)
            origin = .pdf
        case "jpg", "jpeg", "png", "heic":
            let data = try Data(contentsOf: url)
            guard let image = UIImage(data: data), let page = PDFPage(image: image) else {
                throw FolioIssue.unsupported
            }
            let pdf = PDFDocument()
            pdf.insert(page, at: 0)
            guard pdf.write(to: target) else { throw FolioIssue.failedToSave }
            count = 1
            origin = .photo
        default:
            throw FolioIssue.unsupported
        }

        let finalSize = try byteCount(for: target)
        return FolioDocument(id: id,
                             title: url.deletingPathExtension().lastPathComponent,
                             relativePath: relativePath,
                             kind: .source,
                             origin: origin,
                             pageCount: count,
                             byteCount: finalSize,
                             createdAt: Date())
    }

    static func importScan(jpegs: [Data], id: UUID, directory: URL) throws -> FolioDocument {
        guard !jpegs.isEmpty else { throw FolioIssue.noPages }
        guard jpegs.count <= pageLimit else { throw FolioIssue.tooLarge }
        let pdf = PDFDocument()
        for (i, data) in jpegs.enumerated() {
            guard let image = UIImage(data: data), let page = PDFPage(image: image) else {
                throw FolioIssue.unsupported
            }
            pdf.insert(page, at: i)
        }
        let relativePath = "\(id.uuidString).pdf"
        let target = directory.appendingPathComponent(relativePath)
        guard pdf.write(to: target) else { throw FolioIssue.failedToSave }
        return FolioDocument(id: id, title: "Скан \(Date().formatted(date: .numeric, time: .shortened))",
                             relativePath: relativePath, kind: .source, origin: .scan,
                             pageCount: pdf.pageCount, byteCount: try byteCount(for: target), createdAt: Date())
    }

    /// Quality mode re-renders only photo/scan origins. Textual PDFs remain vector PDFs.
    static func export(pages: [FolioDraftPage],
                       documents: [FolioDocument],
                       directory: URL,
                       destination: URL,
                       quality: PDFQuality) throws -> (byteCount: Int64, usedCompression: Bool) {
        guard !pages.isEmpty, pages.count <= pageLimit else { throw FolioIssue.noPages }
        let sources = Dictionary(uniqueKeysWithValues: documents.map { ($0.id, $0) })

        func buildPDF(rasterizePhotos: Bool, to url: URL) throws {
            let result = PDFDocument()
            for (position, token) in pages.enumerated() {
                if Thread.current.isCancelled { throw CancellationError() }
                guard let source = sources[token.documentID] else { throw FolioIssue.missingFile }
                let sourceURL = directory.appendingPathComponent(source.relativePath)
                guard let document = PDFDocument(url: sourceURL),
                      let page = document.page(at: token.pageIndex),
                      let duplicate = page.copy() as? PDFPage else { throw FolioIssue.corruptedPDF }
                duplicate.rotation = ((duplicate.rotation + token.rotation) % 360 + 360) % 360

                if rasterizePhotos && (source.origin == .photo || source.origin == .scan) {
                    let targetSize = CGSize(width: 1100, height: 1556)
                    let rendered = duplicate.thumbnail(of: targetSize, for: .mediaBox)
                    if let jpeg = rendered.jpegData(compressionQuality: 0.68),
                       let recompressed = UIImage(data: jpeg),
                       let rasterPage = PDFPage(image: recompressed) {
                        result.insert(rasterPage, at: position)
                    } else {
                        result.insert(duplicate, at: position)
                    }
                } else {
                    result.insert(duplicate, at: position)
                }
            }
            guard result.write(to: url) else { throw FolioIssue.exportFailed }
        }

        try buildPDF(rasterizePhotos: false, to: destination)
        let baseBytes = try byteCount(for: destination)
        guard quality == .smallerPhotos,
              pages.contains(where: { token in
                  guard let origin = sources[token.documentID]?.origin else { return false }
                  return origin == .photo || origin == .scan
              }) else {
            return (baseBytes, false)
        }

        let compressedURL = destination.deletingLastPathComponent()
            .appendingPathComponent("\(UUID().uuidString)-compressed.pdf")
        defer { try? FileManager.default.removeItem(at: compressedURL) }
        try buildPDF(rasterizePhotos: true, to: compressedURL)
        let compressedBytes = try byteCount(for: compressedURL)
        guard compressedBytes < baseBytes else { return (baseBytes, false) }
        try FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: compressedURL, to: destination)
        return (compressedBytes, true)
    }

    static func byteCount(for url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }
}
