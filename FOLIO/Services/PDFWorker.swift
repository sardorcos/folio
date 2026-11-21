import Foundation
import ImageIO
import PDFKit
import UIKit
import UniformTypeIdentifiers

struct SearchableCopyOutcome: Sendable {
    let document: FolioDocument
    /// Сколько страниц получили распознанный текст.
    let recognizedPages: Int
}

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

    /// Прогресс длительной операции: сколько шагов выполнено из скольких.
    typealias FolioProgress = @Sendable (_ done: Int, _ total: Int) -> Void

    // MARK: - Импорт файлов

    /// Импортирует PDF или изображение как новый документ библиотеки. Оригинал пользователя не изменяется.
    /// - Parameter ocr: распознать текст на изображении (для PDF не используется — см. `makeSearchableCopy`).
    static func importFile(url: URL, id: UUID, password: String? = nil, ocr: Bool = false,
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
                                      id: id, password: password, ocr: ocr,
                                      directory: directory, tempDirectory: tempDirectory)
            }
        }
        if let coordinationError { throw coordinationError }
        return try outcome.get()
    }

    private static func importCoordinated(readURL: URL, title: String, id: UUID, password: String?, ocr: Bool,
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
            try writeImagePDF([jpeg], to: staging, ocr: ocr)
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
                             ocr: Bool = false, progress: FolioProgress? = nil,
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
        try writeImagePDF(pages, to: staging, ocr: ocr, progress: progress)
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
    /// При `ocr` поверх изображения добавляется невидимый распознанный текст.
    static func writeImagePDF(_ pages: [PreparedJPEG], to url: URL, ocr: Bool = false,
                              progress: FolioProgress? = nil) throws {
        let images: [(image: CGImage, size: CGSize)] = try pages.map { page in
            (try jpegImage(page.data), pageSize(forPixelSize: page.pixelSize))
        }
        var recognized = Array(repeating: [RecognizedLine](), count: images.count)
        if ocr {
            for (index, item) in images.enumerated() {
                try Task.checkCancellation()
                // Ошибка OCR не мешает созданию PDF: страница просто останется без текстового слоя.
                recognized[index] = autoreleasepool { (try? TextRecognizer.recognizeLines(in: item.image)) ?? [] }
                progress?(index + 1, images.count)
            }
        }
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextCreator as String: "FOLIO"]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: PaperSize.current), format: format)
        try renderer.writePDF(to: url) { context in
            for (index, item) in images.enumerated() {
                let bounds = CGRect(origin: .zero, size: item.size)
                context.beginPage(withBounds: bounds, pageInfo: [:])
                UIImage(cgImage: item.image).draw(in: bounds)
                TextRecognizer.drawInvisibleText(recognized[index], in: bounds, context: context.cgContext)
            }
        }
    }

    /// CGImage поверх JPEG-данных: при отрисовке в PDF JPEG встраивается как есть.
    static func jpegImage(_ data: Data) throws -> CGImage {
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(jpegDataProviderSource: provider, decode: nil,
                                  shouldInterpolate: true, intent: .defaultIntent) else {
            throw FolioIssue.unsupported
        }
        return image
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

        /// Качество для «Распознать текст» у PDF-сканов: близко к исходному.
        static let ocrCopy = CompressionLevel(maxPixel: 2200, quality: 0.75)
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
                       targetBytes: Int64?,
                       ocr: Bool = false,
                       progress: FolioProgress? = nil) throws -> ExportOutcome {
        guard !pages.isEmpty else { throw FolioIssue.noPages }
        guard pages.count <= FolioLimits.draftPages else { throw FolioIssue.tooManyPages(limit: FolioLimits.draftPages) }
        let sources = Dictionary(documents.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var opened: [UUID: PDFDocument] = [:]
        var created: [URL] = []
        // OCR страницы выполняется один раз и переиспользуется на всех уровнях сжатия.
        var ocrCache: [Int: [RecognizedLine]] = [:]
        let levels = targetBytes == nil ? [CompressionLevel.ladder[0]] : CompressionLevel.ladder
        var pass = 0
        let totalSteps = pages.count * (1 + levels.count)
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
                        let recognize: ((CGImage) -> [RecognizedLine])? = ocr ? { image in
                            if let cached = ocrCache[position] { return cached }
                            let lines = (try? TextRecognizer.recognizeLines(in: image)) ?? []
                            ocrCache[position] = lines
                            return lines
                        } : nil
                        let (rasterPage, holder) = try rasterizedPage(copy, level: level, recognize: recognize)
                        keepAlive.append(holder)
                        result.insert(rasterPage, at: position)
                    } else {
                        result.insert(copy, at: position)
                    }
                }
                progress?(pass * pages.count + position + 1, totalSteps)
            }
            pass += 1
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
        progress?(totalSteps, totalSteps)
        try FileManager.default.moveItem(at: bestURL, to: destination)
        return ExportOutcome(byteCount: bestBytes, uncompressedByteCount: baseBytes,
                             usedCompression: bestURL != baseURL)
    }

    /// Превращает страницу в JPEG-страницу того же физического размера. Поворот «впекается» в изображение.
    /// Если передан `recognize`, поверх изображения добавляется невидимый распознанный текст.
    static func rasterizedPage(_ page: PDFPage, level: CompressionLevel,
                               recognize: ((CGImage) -> [RecognizedLine])? = nil) throws -> (PDFPage, PDFDocument) {
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
        let cgImage = try jpegImage(prepared.data)
        let lines = recognize?(cgImage) ?? []
        let pageRect = CGRect(origin: .zero, size: pointSize)
        let data = UIGraphicsPDFRenderer(bounds: pageRect).pdfData { context in
            context.beginPage()
            UIImage(cgImage: cgImage).draw(in: pageRect)
            TextRecognizer.drawInvisibleText(lines, in: pageRect, context: context.cgContext)
        }
        // Вставляем копию: страница не должна одновременно принадлежать двум документам.
        guard let holder = PDFDocument(data: data),
              let rasterPage = holder.page(at: 0)?.copy() as? PDFPage else {
            throw FolioIssue.exportFailed
        }
        return (rasterPage, holder)
    }

    // MARK: - Распознавание текста в готовых PDF

    /// Создаёт копию PDF, в которой страницы без текста (сканы) получают распознанный текстовый слой.
    /// Страницы, где текст уже есть, копируются без изменений. Оригинал не трогается.
    static func makeSearchableCopy(of source: URL, id: UUID, title: String,
                                   directory: URL, tempDirectory: URL,
                                   progress: FolioProgress? = nil) throws -> SearchableCopyOutcome {
        guard let pdf = PDFDocument(url: source), !pdf.isLocked, pdf.pageCount > 0 else { throw FolioIssue.corruptedPDF }
        let result = PDFDocument()
        var keepAlive: [PDFDocument] = []
        var recognizedPages = 0
        for index in 0..<pdf.pageCount {
            try Task.checkCancellation()
            try autoreleasepool {
                guard let page = pdf.page(at: index), let copy = page.copy() as? PDFPage else {
                    throw FolioIssue.corruptedPDF
                }
                if hasText(page) {
                    result.insert(copy, at: index)
                } else {
                    var found = 0
                    let (rasterPage, holder) = try rasterizedPage(copy, level: .ocrCopy) { image in
                        let lines = (try? TextRecognizer.recognizeLines(in: image)) ?? []
                        found = lines.count
                        return lines
                    }
                    if found > 0 { recognizedPages += 1 }
                    keepAlive.append(holder)
                    result.insert(rasterPage, at: index)
                }
            }
            progress?(index + 1, pdf.pageCount)
        }
        result.documentAttributes = [
            PDFDocumentAttribute.titleAttribute: title,
            PDFDocumentAttribute.creatorAttribute: "FOLIO"
        ]
        let relativePath = "\(id.uuidString).pdf"
        let target = directory.appendingPathComponent(relativePath)
        let staging = tempDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: staging) }
        guard result.write(to: staging) else { throw FolioIssue.failedToSave }
        withExtendedLifetime(keepAlive) {}
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: staging, to: target)
        let document = FolioDocument(id: id, title: title, relativePath: relativePath, kind: .source, origin: .scan,
                                     pageCount: result.pageCount, byteCount: try byteCount(for: target),
                                     createdAt: Date())
        return SearchableCopyOutcome(document: document, recognizedPages: recognizedPages)
    }

    static func hasText(_ page: PDFPage) -> Bool {
        !(page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Сколько страниц документа не содержат текста (кандидаты на OCR).
    static func pagesWithoutText(at url: URL) -> Int {
        guard let pdf = PDFDocument(url: url), !pdf.isLocked else { return 0 }
        return (0..<pdf.pageCount).reduce(0) { count, index in
            guard let page = pdf.page(at: index) else { return count }
            return hasText(page) ? count : count + 1
        }
    }

    /// Текст документа для поиска и экрана «Текст документа».
    static func extractText(from url: URL, limit: Int = 200_000) -> String {
        guard let pdf = PDFDocument(url: url), !pdf.isLocked else { return "" }
        let text = pdf.string ?? ""
        return text.count > limit ? String(text.prefix(limit)) : text
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
