import Foundation

enum FolioTab: Int, CaseIterable, Hashable {
    case home, files, templates, settings
}

enum FolioRoute: Hashable {
    case composer
    case export
    case result
    case document(UUID)
}

enum FileKind: String, Codable, Sendable {
    case source, result
}

enum FileOrigin: String, Codable, Sendable {
    case pdf, photo, scan
}

/// Ограничения приложения. Все тексты интерфейса берут значения отсюда, а не из захардкоженных чисел.
enum FolioLimits {
    /// Максимальный размер импортируемого PDF.
    static let pdfImportBytes: Int64 = 200 * 1_000_000
    /// Максимальный размер одного импортируемого изображения.
    static let imageImportBytes: Int64 = 50 * 1_000_000
    /// Максимум страниц в одном PDF-комплекте (и в одном импортируемом PDF).
    static let draftPages = 500
    /// Длинная сторона изображения при импорте фото и сканов: ≈300 dpi для A4.
    static let imageMaxPixel: CGFloat = 2480
    /// Глубина истории отмены.
    static let undoDepth = 30
    /// Максимальная длина названия документа.
    static let titleLength = 120

    static func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

struct FolioDocument: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: UUID
    var title: String
    let relativePath: String
    let kind: FileKind
    let origin: FileOrigin
    let pageCount: Int
    let byteCount: Int64
    let createdAt: Date
    var isFavorite: Bool = false

    var summary: String {
        "\(pageCount) стр. · \(FolioLimits.formatted(byteCount))"
    }
}

struct FolioDraftPage: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: UUID
    let documentID: UUID
    let pageIndex: Int
    var rotation: Int = 0
}

struct FolioSnapshot: Codable, Sendable {
    static let currentVersion = 2

    /// Отсутствует в индексах версии 0.4.0 — тогда считаем версию равной 1.
    var version: Int?
    var documents: [FolioDocument]
    var draftPages: [FolioDraftPage]
}

enum ImportIntent: String, Sendable {
    case documents
    case photographs
    case editing
    case compression
    case scan

    var source: ImportSource {
        switch self {
        case .photographs: .photos
        case .scan: .scanner
        case .documents, .editing, .compression: .files
        }
    }
}

enum ImportSource: Sendable {
    case files, photos, scanner
}

enum PDFQuality: String, CaseIterable, Identifiable, Codable, Sendable {
    case original
    case smallerPhotos
    case maximum

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: String(localized: "Исходное качество")
        case .smallerPhotos: String(localized: "Уменьшить фото и сканы")
        case .maximum: String(localized: "Максимальное сжатие")
        }
    }

    var subtitle: String {
        switch self {
        case .original:
            String(localized: "Страницы копируются без изменений. Текст и графика сохраняются.")
        case .smallerPhotos:
            String(localized: "Сжимаются только страницы из фото и сканов. Обычные PDF не меняются.")
        case .maximum:
            String(localized: "Все страницы станут изображениями. Текст нельзя будет выделить и найти.")
        }
    }
}

/// Настройки экспорта, которые можно применить при запуске задачи или шаблона.
struct ExportPreset: Equatable, Sendable {
    var quality: PDFQuality
    var targetMB: Int?
}

struct FolioSavedWorkflow: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var description: String
    var quality: PDFQuality
    var targetMB: Int?

    var preset: ExportPreset { ExportPreset(quality: quality, targetMB: targetMB) }
    var intent: ImportIntent { quality == .smallerPhotos ? .photographs : .documents }

    static let defaults: [FolioSavedWorkflow] = [
        .init(id: UUID(uuidString: "A0D8877B-2D71-480E-BCCB-5A78B241F111")!,
              name: String(localized: "Комплект для клиента"),
              description: String(localized: "Объединение PDF, предупреждение, если больше 5 МБ"),
              quality: .original, targetMB: 5),
        .init(id: UUID(uuidString: "A0D8877B-2D71-480E-BCCB-5A78B241F112")!,
              name: String(localized: "Фото и сканы в PDF"),
              description: String(localized: "Фото из галереи, сжатие до 10 МБ"),
              quality: .smallerPhotos, targetMB: 10),
        .init(id: UUID(uuidString: "A0D8877B-2D71-480E-BCCB-5A78B241F113")!,
              name: String(localized: "PDF без изменения качества"),
              description: String(localized: "Подготовка копии для отправки"),
              quality: .original, targetMB: nil)
    ]
}

/// Ожидающий ввода пароль для защищённого PDF.
struct FolioPasswordRequest: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    var fileName: String { url.lastPathComponent }
    var wrongAttempt: Bool = false
}

enum FolioIssue: LocalizedError, Equatable {
    case unsupported
    case corruptedPDF
    case tooLarge(limit: Int64)
    case tooManyPages(limit: Int)
    case passwordProtected
    case wrongPassword
    case emptyPDF
    case missingFile
    case exportFailed
    case noPages
    case failedToSave

    var errorDescription: String? {
        switch self {
        case .unsupported:
            String(localized: "Поддерживаются PDF и изображения (JPG, PNG, HEIC и другие).")
        case .corruptedPDF:
            String(localized: "PDF не удалось открыть. Возможно, файл повреждён.")
        case .tooLarge(let limit):
            String(localized: "Файл больше \(FolioLimits.formatted(limit)) — это ограничение импорта.")
        case .tooManyPages(let limit):
            String(localized: "В документе больше \(limit) страниц — это ограничение одного комплекта.")
        case .passwordProtected:
            String(localized: "PDF защищён паролем.")
        case .wrongPassword:
            String(localized: "Неверный пароль.")
        case .emptyPDF:
            String(localized: "В этом файле нет страниц.")
        case .missingFile:
            String(localized: "Документ отсутствует в локальной библиотеке.")
        case .exportFailed:
            String(localized: "Не удалось создать итоговый PDF. Исходные документы не изменены.")
        case .noPages:
            String(localized: "Добавьте хотя бы одну страницу.")
        case .failedToSave:
            String(localized: "Не удалось сохранить документ в локальной библиотеке.")
        }
    }
}

/// Склонения. Формы задаются в Localizable.xcstrings (плюральные варианты one/few/many/other).
enum FolioPlural {
    static func pages(_ count: Int) -> String {
        String(localized: "\(count) страниц", comment: "Количество страниц, плюральная форма")
    }

    static func documents(_ count: Int) -> String {
        String(localized: "\(count) документов", comment: "Количество документов, плюральная форма")
    }

    static func files(_ count: Int) -> String {
        String(localized: "\(count) файлов", comment: "Количество файлов, плюральная форма")
    }
}

extension String {
    /// Название, безопасное для отображения и для имени файла при отправке.
    func folioCleanTitle(fallback: String) -> String {
        var clean = self
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.lowercased().hasSuffix(".pdf") {
            clean = String(clean.dropLast(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if clean.count > FolioLimits.titleLength {
            clean = String(clean.prefix(FolioLimits.titleLength)).trimmingCharacters(in: .whitespaces)
        }
        while clean.hasPrefix(".") { clean.removeFirst() }
        return clean.isEmpty ? fallback : clean
    }
}
