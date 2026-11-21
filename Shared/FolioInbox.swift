import Foundation

/// Общая папка приложения и расширения «Поделиться» (App Group).
///
/// Расширение пишет файлы в скрытую папку `.incoming-…` и переименовывает её, только когда всё скопировано.
/// Приложение забирает лишь завершённые пакеты, поэтому никогда не читает файл, который ещё пишется.
///
/// Структура: `Inbox/<время>-<uuid>/<0000>/<исходное имя файла>` — порядок пакетов и файлов сохраняется.
enum FolioInbox {
    /// `group.<bundle id приложения>`. Bundle ID расширения — `<bundle id приложения>.share`.
    static var appGroupIdentifier: String? {
        guard var identifier = Bundle.main.bundleIdentifier else { return nil }
        let suffix = ".share"
        if identifier.hasSuffix(suffix) { identifier.removeLast(suffix.count) }
        return "group." + identifier
    }

    /// `nil`, если App Group не настроена в подписи (Signing & Capabilities).
    static var directory: URL? {
        guard let group = appGroupIdentifier,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            return nil
        }
        return container.appendingPathComponent("Inbox", isDirectory: true)
    }

    // MARK: - Расширение

    static func makeIncomingBatch(in root: URL) throws -> URL {
        let batch = root.appendingPathComponent(".incoming-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: batch, withIntermediateDirectories: true)
        return batch
    }

    static func slot(_ index: Int, in batch: URL) -> URL {
        batch.appendingPathComponent(String(format: "%04d", index), isDirectory: true)
    }

    /// Делает пакет видимым для приложения одной атомарной операцией.
    static func commit(_ batch: URL, in root: URL) throws {
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let committed = root.appendingPathComponent("\(stamp)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.moveItem(at: batch, to: committed)
    }

    static func discard(_ batch: URL) {
        try? FileManager.default.removeItem(at: batch)
    }

    // MARK: - Приложение

    /// Переносит файлы всех завершённых пакетов в `destination` (по порядку) и удаляет пакеты.
    static func takeAll(from root: URL, movingTo destination: URL) -> [URL] {
        let fileManager = FileManager.default
        var result: [URL] = []
        for batch in sortedChildren(of: root) {
            for slot in sortedChildren(of: batch) {
                for file in sortedChildren(of: slot) {
                    let target = destination
                        .appendingPathComponent(batch.lastPathComponent, isDirectory: true)
                        .appendingPathComponent(slot.lastPathComponent, isDirectory: true)
                        .appendingPathComponent(file.lastPathComponent)
                    do {
                        try fileManager.createDirectory(at: target.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                        do {
                            try fileManager.moveItem(at: file, to: target)
                        } catch {
                            try fileManager.copyItem(at: file, to: target)
                        }
                        result.append(target)
                    } catch {
                        continue
                    }
                }
            }
            try? fileManager.removeItem(at: batch)
        }
        return result
    }

    private static func sortedChildren(of url: URL) -> [URL] {
        let children = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil,
                                                                     options: [.skipsHiddenFiles])) ?? []
        return children.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
