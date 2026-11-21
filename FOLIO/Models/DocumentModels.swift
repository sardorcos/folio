import Foundation

enum FolioTab: Int, CaseIterable {
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

struct FolioDocument: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var title: String
    let relativePath: String
    let kind: FileKind
    let origin: FileOrigin
    let pageCount: Int
    let byteCount: Int64
    let createdAt: Date
    var isFavorite: Bool = false

    var summary: String { "\(pageCount) стр. · \(ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file))" }
}

struct FolioDraftPage: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let documentID: UUID
    let pageIndex: Int
    var rotation: Int = 0
}

struct FolioSnapshot: Codable, Sendable {
    var documents: [FolioDocument]
    var draftPages: [FolioDraftPage]
}

enum ImportIntent: String, Sendable {
    case documents
    case photographs
    case editing
    case compression
}

enum PDFQuality: String, CaseIterable, Identifiable, Codable, Sendable {
    case original
    case smallerPhotos

    var id: String { rawValue }
    var title: String {
        switch self {
        case .original: "Исходное качество"
        case .smallerPhotos: "Уменьшить фото и сканы"
        }
    }
    var subtitle: String {
        switch self {
        case .original: "Текст и векторные элементы сохраняются"
        case .smallerPhotos: "Для фотографий и сканов; качество может снизиться"
        }
    }
}

enum FolioIssue: LocalizedError {
    case unsupported
    case corruptedPDF
    case tooLarge
    case emptyPDF
    case missingFile
    case exportFailed
    case noPages
    case failedToSave

    var errorDescription: String? {
        switch self {
        case .unsupported: "Поддерживаются PDF, JPG, PNG и HEIC."
        case .corruptedPDF: "PDF не удалось открыть. Возможно, он повреждён или защищён паролем."
        case .tooLarge: "Файл превышает ограничение импорта 40 МБ."
        case .emptyPDF: "В этом файле нет страниц."
        case .missingFile: "Документ отсутствует в локальной библиотеке."
        case .exportFailed: "Не удалось создать итоговый PDF. Исходные документы не изменены."
        case .noPages: "Добавьте хотя бы одну страницу."
        case .failedToSave: "Не удалось сохранить документ в локальной библиотеке."
        }
    }
}
