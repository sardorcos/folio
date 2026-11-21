import Foundation
import ImageIO
import PDFKit
import UIKit
import UniformTypeIdentifiers

struct ExportOutcome: Sendable {
    /// Размер итогового файла.
    let byteCount: Int64
    /// Размер PDF без сжатия — для сравнения в интерфейсе.
    let uncompressedByteCount: Int64
    let usedCompression: Bool
}

/// PDF-операции выполняются на локальных файлах. Сеть не используется.
/// Все функции синхронные и рассчитаны на вызов вне главного потока; отмена — через `Task.checkCancellation()`.
enum PDFWorker {

    // MARK: - Импорт файлов

    /// Импортирует PDF или изображение как новый документ библиотеки. Оригинал пользователя не изменяется.
    static func importFile(url: URL, id: UUID, password: String? = nil,
                           directory: URL, tempDirectory: URL) throws -> FolioDocument {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }

        // Координированное чтение скачивает файлы iCloud Drive, которых ещё нет на устройстве.
        var coordinationError: NSError?
        var outcome: Result<FolioDocument, Error> = .failure(FolioIssue.unsupported)
        NSFileCoordinator().coordinate(readingItemAt: url, options: [.withoutChanges],
                                       error: &coordinationError) { readURL in
            outcome = Result {
                try importCoordinated(readURL: readURL, title: url.deletingPathExtension().lastPathComponent,
                                      id: id, password: password,
                                      directory: directory, tempDirectory: tempDirectory)
            }
        }
        if let coordinationError { throw coordinationError }
        return try outcome.get()
    }

    private static func importCoordinated(readURL: URL, title: String, id: UUID, password: String?,
                                          directory: URL, tempDirectory: URL) throws -> FolioDocument {
        try Task.checkCancellation()
        let values = try readURL.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
        let size = Int64(values.fileSize ?? 0)
        let type = values.contentType ?? UTType(filenameExtension: readURL.pathExtension.lowercased())
        let relativePath = "\(id.uuidString).pdf"
        let target = directory.appendingPathComponent(relativePath)
        let staging = tempDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: staging) }

        let origin: FileOrigin
        let pageCount: Int

        if let type, type.conforms(to: .pdf) {
            guard size <= FolioLimits.pdfImportBytes else { throw FolioIssue.tooLarge(limit: FolioLimits.pdfImportBytes) }
            guard let pdf = PDFDocument(url: readURL) else { throw FolioIssue.corruptedPDF }
            if pdf.isLocked {
                guard let password else { throw FolioIssue.passwordProtected }
                guard pdf.unlock(withPassword: password) else { throw FolioIssue.wrongPassword }
            }
            pageCount = pdf.pageCount
            guard pageCount > 0 else { throw FolioIssue.emptyPDF }
            guard pageCount <= FolioLimits.draftPages else { throw FolioIssue.tooManyPages(limit: FolioLimits.draftPages) }
            if password != nil {
                // Разблокированный документ сохраняем без пароля, иначе его нельзя будет открыть при сборке.
                guard pdf.write(to: staging) else { throw FolioIssue.failedToSave }
            } else {
                try FileManager.default.copyItem(at: readURL, to: staging)
            }
            origin = .pdf
        } else if let type, type.conforms(to: .image) {
            guard size <= FolioLimits.imageImportBytes else { throw FolioIssue.tooLarge(limit: FolioLimits.imageImportBytes) }
            let data = try Data(contentsOf: readURL)
            let jpeg = try preparedJPEG(fromImageData: data)
            try writeImagePDF([jpeg], to: staging)
            pageCount = 1
            origin = .photo
        } else {
            throw FolioIssue.unsupported
        }

        try Task.checkCancellation()
        // В библиотеку попадает только полностью записанный файл.
        try FileManager.default.moveItem(at: staging, to: target)
        return FolioDocument(id: id,
                             title: title.folioCleanTitle(fallback: String(localized: "Документ")),
                             relativePath: relativePath,
                             kind: .source,
                             origin: origin,
                             pageCount: pageCount,
                             byteCount: try byteCount(for: target),
                             createdAt: Date())
    }

    // MARK: - Фото и сканы

    enum ImageInput {
        case data(Data)
        case image(UIImage)
    }

    /// Создаёт один многостраничный документ из фотографий или страниц скана.
    static func importImages(_ inputs: [ImageInput], id: UUID, title: String, origin: FileOrigin,
                             directory: URL, tempDirectory: URL) throws -> FolioDocument {
        guard !inputs.isEmpty else { throw FolioIssue.noPages }
        guard inputs.count <= FolioLimits.draftPages else { throw FolioIssue.tooManyPages(limit: FolioLimits.draftPages) }
        var pages: [PreparedJPEG] = []
        for input in inputs {
            try Task.checkCancellation()
            let prepared: PreparedJPEG = try autoreleasepool {
                switch input {
                case .data(let data): return try preparedJPEG(fromImageData: data)
                case .image(let image): return try preparedJPEG(from: image)
                }
            }
            pages.append(prepared)
        }
        let relativePath = "\(id.uuidString).pdf"
        let target = directory.appendingPathComponent(relativePath)
        let staging = tempDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: staging) }
        try writeImagePDF(pages, to: staging)
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: staging, to: target)
        return FolioDocument(id: id, title: title, relativePath: relativePath, kind: .source, origin: origin,
                             pageCount: pages.count, byteCount: try byteCount(for: target), createdAt: Date())
    }

    struct PreparedJPEG {
        let data: Data
        let pixelSize: CGSize
    }

    /// Уменьшает изображение до `FolioLimits.imageMaxPixel`, применяет EXIF-ориентацию и кодирует в JPEG.
    static func preparedJPEG(fromImageData data: Data, maxPixel: CGFloat = FolioLimits.imageMaxPixel,
                             quality: CGFloat = 0.82) throws -> PreparedJPEG {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw FolioIssue.unsupported }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixel)
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw FolioIssue.unsupported
        }
        return try preparedJPEG(from: UIImage(cgImage: cgImage), maxPixel: maxPixel, quality: quality)
    }

    static func preparedJPEG(from image: UIImage, maxPixel: CGFloat = FolioLimits.imageMaxPixel,
                             quality: CGFloat = 0.82) throws -> PreparedJPEG {
        let flat = flattened(image, maxPixel: maxPixel)
        guard let data = flat.jpegData(compressionQuality: quality) else { throw FolioIssue.unsupported }
        return PreparedJPEG(data: data, pixelSize: CGSize(width: flat.size.width * flat.scale,
                                                          height: flat.size.height * flat.scale))
    }

    /// Непрозрачная копия изображения с ориентацией `.up`, белым фоном и масштабом 1.
    static func flattened(_ image: UIImage, maxPixel: CGFloat) -> UIImage {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        guard pixelWidth > 0, pixelHeight > 0 else { return image }
        let factor = min(1, maxPixel / max(pixelWidth, pixelHeight))
        let size = CGSize(width: max(1, (pixelWidth * factor).rounded()),
                          height: max(1, (pixelHeight * factor).rounded()))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Пишет PDF, в котором каждая страница — JPEG, вписанный в формат бумаги (A4 или Letter по региону).
    /// JPEG встраивается без перекодирования, поэтому размер файла близок к сумме JPEG.
    static func writeImagePDF(_ pages: [PreparedJPEG], to url: URL) throws {
        let images: [(UIImage, CGSize)] = try pages.map { page in
            guard let provider = CGDataProvider(data: page.data as CFData),
                  let cgImage = CGImage(jpegDataProviderSource: provider, decode: nil,
                                        shouldInterpolate: true, intent: .defaultIntent) else {
                throw FolioIssue.unsupported
            }
            return (UIImage(cgImage: cgImage), pageSize(forPixelSize: page.pixelSize))
        }
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextCreator as String: "FOLIO"]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: PaperSize.current), format: format)
        try renderer.writePDF(to: url) { context in
            for (image, size) in images {
                let bounds = CGRect(origin: .zero, size: size)
                context.beginPage(withBounds: bounds, pageInfo: [:])
                image.draw(in: bounds)
            }
        }
    }

    /// Размер страницы в пунктах: изображение вписывается в A4/Letter с учётом своей ориентации.
    static func pageSize(forPixelSize pixel: CGSize) -> CGSize {
        let paper = PaperSize.current
        let long = max(paper.width, paper.height)
        let short = min(paper.width, paper.height)
        let box = pixel.width > pixel.height ? CGSize(width: long, height: short) : CGSize(width: short, height: long)
        guard pixel.width > 0, pixel.height > 0 else { return box }
        let scale = min(box.width / pixel.width, box.height / pixel.height)
        return CGSize(width: (pixel.width * scale).rounded(), height: (pixel.height * scale).rounded())
    }

    enum PaperSize {
        static let a4 = CGSize(width: 595.28, height: 841.89)
        static let letter = CGSize(width: 612, height: 792)
        private static let letterRegions: Set<String> = ["US", "CA", "MX", "CL", "CO", "CR", "GT", "PA", "PH", "PR", "SV", "VE", "DO"]

        static var current: CGSize {
            letterRegions.contains(Locale.current.region?.identifier ?? "") ? letter : a4
        }
    }

    // MARK: - Экспорт

    struct CompressionLevel: Sendable {
        let maxPixel: CGFloat
        let quality: CGFloat

        /// От мягкого к сильному. Без цели по размеру используется только первый уровень.
        static let ladder: [CompressionLevel] = [
            .init(maxPixel: 1800, quality: 0.70),
            .init(maxPixel: 1500, quality: 0.58),
            .init(maxPixel: 1200, quality: 0.48),
            .init(maxPixel: 1000, quality: 0.38)
        ]
    }

    /// Собирает итоговый PDF. При сжатии подбирает уровень, чтобы уложиться в `targetBytes`,
    /// и никогда не возвращает файл больше несжатого варианта.
    static func export(pages: [FolioDraftPage],
                       documents: [FolioDocument],
                       directory: URL,
                       tempDirectory: URL,
                       destination: URL,
                       title: String,
                       quality: PDFQuality,
                       targetBytes: Int64?) throws -> ExportOutcome {
        guard !pages.isEmpty else { throw FolioIssue.noPages }
        guard pages.count <= FolioLimits.draftPages else { throw FolioIssue.tooManyPages(limit: FolioLimits.draftPages) }
        let sources = Dictionary(documents.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var opened: [UUID: PDFDocument] = [:]
        var created: [URL] = []
        defer { for url in created { try? FileManager.default.removeItem(at: url) } }

        func sourcePage(for token: FolioDraftPage) throws -> PDFPage {
            guard let source = sources[token.documentID] else { throw FolioIssue.missingFile }
            let document: PDFDocument
            if let cached = opened[token.documentID] {
                document = cached
            } else {
                guard let loaded = PDFDocument(url: directory.appendingPathComponent(source.relativePath)) else {
                    throw FolioIssue.corruptedPDF
                }
                opened[token.documentID] = loaded
                document = loaded
            }
            guard let page = document.page(at: token.pageIndex) else { throw FolioIssue.corruptedPDF }
            return page
        }

        func shouldRasterize(_ token: FolioDraftPage) -> Bool {
            switch quality {
            case .original: return false
            case .maximum: return true
            case .smallerPhotos:
                guard let origin = sources[token.documentID]?.origin else { return false }
                return origin == .photo || origin == .scan
            }
        }

        func build(level: CompressionLevel?) throws -> URL {
            let url = tempDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
            created.append(url)
            let result = PDFDocument()
            var keepAlive: [PDFDocument] = []
            for (position, token) in pages.enumerated() {
                try Task.checkCancellation()
                try autoreleasepool {
                    let original = try sourcePage(for: token)
                    guard let copy = original.copy() as? PDFPage else { throw FolioIssue.corruptedPDF }
                    copy.rotation = normalizedRotation(copy.rotation + token.rotation)
                    if let level, shouldRasterize(token) {
                        let (rasterPage, holder) = try rasterizedPage(copy, level: level)
                        keepAlive.append(holder)
                        result.insert(rasterPage, at: position)
                    } else {
                        result.insert(copy, at: position)
                    }
                }
            }
            result.documentAttributes = [
                PDFDocumentAttribute.titleAttribute: title,
                PDFDocumentAttribute.creatorAttribute: "FOLIO"
            ]
            guard result.write(to: url) else { throw FolioIssue.exportFailed }
            withExtendedLifetime(keepAlive) {}
            return url
        }

        let baseURL = try build(level: nil)
        let baseBytes = try byteCount(for: baseURL)
        var bestURL = baseURL
        var bestBytes = baseBytes

        if pages.contains(where: shouldRasterize) {
            let levels = targetBytes == nil ? [CompressionLevel.ladder[0]] : CompressionLevel.ladder
            for level in levels {
                try Task.checkCancellation()
                let candidate = try build(level: level)
                let bytes = try byteCount(for: candidate)
                if bytes < bestBytes {
                    bestURL = candidate
                    bestBytes = bytes
                }
                if let targetBytes, bestBytes <= targetBytes { break }
            }
        }

        try Task.checkCancellation()
        try FileManager.default.moveItem(at: bestURL, to: destination)
        return ExportOutcome(byteCount: bestBytes, uncompressedByteCount: baseBytes,
                             usedCompression: bestURL != baseURL)
    }

    /// Превращает страницу в JPEG-страницу того же физического размера. Поворот «впекается» в изображение.
    static func rasterizedPage(_ page: PDFPage, level: CompressionLevel) throws -> (PDFPage, PDFDocument) {
        let bounds = page.bounds(for: .cropBox)
        let quarterTurn = normalizedRotation(page.rotation) % 180 != 0
        let pointSize = quarterTurn ? CGSize(width: bounds.height, height: bounds.width) : bounds.size
        guard pointSize.width > 0, pointSize.height > 0 else { throw FolioIssue.corruptedPDF }
        let scale = level.maxPixel / max(pointSize.width, pointSize.height)
        let pixelSize = CGSize(width: max(1, (pointSize.width * scale).rounded()),
                               height: max(1, (pointSize.height * scale).rounded()))
        // thumbnail учитывает поворот страницы и сохраняет пропорции.
        let rendered = page.thumbnail(of: pixelSize, for: .cropBox)
        let prepared = try preparedJPEG(from: rendered, maxPixel: level.maxPixel, quality: level.quality)
        guard let provider = CGDataProvider(data: prepared.data as CFData),
              let cgImage = CGImage(jpegDataProviderSource: provider, decode: nil,
                                    shouldInterpolate: true, intent: .defaultIntent) else {
            throw FolioIssue.exportFailed
        }
        let pageRect = CGRect(origin: .zero, size: pointSize)
        let data = UIGraphicsPDFRenderer(bounds: pageRect).pdfData { context in
            context.beginPage()
            UIImage(cgImage: cgImage).draw(in: pageRect)
        }
        // Вставляем копию: страница не должна одновременно принадлежать двум документам.
        guard let holder = PDFDocument(data: data),
              let rasterPage = holder.page(at: 0)?.copy() as? PDFPage else {
            throw FolioIssue.exportFailed
        }
        return (rasterPage, holder)
    }

    // MARK: - Утилиты

    static func normalizedRotation(_ degrees: Int) -> Int {
        ((degrees % 360) + 360) % 360
    }

    static func byteCount(for url: URL) throws -> Int64 {
        Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
    }

    static func pageCount(of url: URL) -> Int? {
        guard let document = PDFDocument(url: url), !document.isLocked, document.pageCount > 0 else { return nil }
        return document.pageCount
    }
}
