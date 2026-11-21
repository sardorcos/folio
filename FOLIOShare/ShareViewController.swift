import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Точка входа расширения «Поделиться» (NSExtensionPrincipalClass).
/// Расширение только копирует PDF и изображения в общую папку; обработку делает приложение FOLIO.
final class ShareViewController: UIViewController {
    private lazy var model = ShareModel(context: extensionContext)

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareView(model: model))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        model.start()
    }
}

@MainActor
final class ShareModel: ObservableObject {
    enum Phase: Equatable {
        case saving(done: Int, total: Int)
        case saved(count: Int, skipped: Int)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .saving(done: 0, total: 0)

    private weak var context: NSExtensionContext?
    private var batch: URL?
    private var task: Task<Void, Never>?

    init(context: NSExtensionContext?) {
        self.context = context
    }

    func start() {
        let providers = (context?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        let items: [(provider: NSItemProvider, type: UTType)] = providers.compactMap { provider in
            Self.supportedType(of: provider).map { (provider, $0) }
        }
        guard !items.isEmpty else {
            phase = .failed(String(localized: "FOLIO принимает PDF и изображения. Среди выбранного таких файлов нет."))
            return
        }
        guard let root = FolioInbox.directory else {
            phase = .failed(String(localized: "Нет доступа к общей папке FOLIO. Проверьте настройку App Group в проекте."))
            return
        }
        phase = .saving(done: 0, total: items.count)
        task = Task { [weak self] in
            await self?.save(items, to: root)
        }
    }

    private func save(_ items: [(provider: NSItemProvider, type: UTType)], to root: URL) async {
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let batch = try FolioInbox.makeIncomingBatch(in: root)
            self.batch = batch
            var saved = 0
            for (index, item) in items.enumerated() {
                if Task.isCancelled { return }
                let slot = FolioInbox.slot(index, in: batch)
                do {
                    try await Self.copy(item.provider, type: item.type, index: index, to: slot)
                    saved += 1
                } catch {
                    try? FileManager.default.removeItem(at: slot)
                }
                phase = .saving(done: index + 1, total: items.count)
            }
            guard saved > 0 else {
                FolioInbox.discard(batch)
                self.batch = nil
                phase = .failed(String(localized: "Не удалось получить файлы из приложения-источника."))
                return
            }
            try FolioInbox.commit(batch, in: root)
            self.batch = nil
            phase = .saved(count: saved, skipped: items.count - saved)
        } catch {
            if let batch { FolioInbox.discard(batch) }
            batch = nil
            phase = .failed(error.localizedDescription)
        }
    }

    func finish() {
        context?.completeRequest(returningItems: nil)
    }

    func cancel() {
        task?.cancel()
        if let batch { FolioInbox.discard(batch) }
        batch = nil
        context?.cancelRequest(withError: CocoaError(.userCancelled))
    }

    // MARK: - Работа с NSItemProvider

    nonisolated static func supportedType(of provider: NSItemProvider) -> UTType? {
        if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) { return .pdf }
        for identifier in provider.registeredTypeIdentifiers {
            if let type = UTType(identifier), type.conforms(to: .image) { return type }
        }
        return nil
    }

    /// Копирует файл в папку пакета. Если источник отдаёт только данные (без файла), записывает их сам.
    private nonisolated static func copy(_ provider: NSItemProvider, type: UTType, index: Int, to folder: URL) async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let baseName = provider.suggestedName ?? (type.conforms(to: .pdf)
            ? String(localized: "Документ")
            : String(localized: "Изображение \(index + 1)"))
        let fileExtension = type.preferredFilenameExtension ?? (type.conforms(to: .pdf) ? "pdf" : "jpg")
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                _ = provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, error in
                    guard let url else {
                        continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                        return
                    }
                    do {
                        // Файл провайдера существует только внутри этого замыкания — копируем сразу.
                        let name = url.pathExtension.isEmpty ? "\(baseName).\(fileExtension)" : url.lastPathComponent
                        try FileManager.default.copyItem(at: url, to: folder.appendingPathComponent(name))
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } catch {
            let data: Data = try await withCheckedThrowingContinuation { continuation in
                _ = provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, error in
                    if let data {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                    }
                }
            }
            try data.write(to: folder.appendingPathComponent("\(baseName).\(fileExtension)"))
        }
    }
}

struct ShareView: View {
    @ObservedObject var model: ShareModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Spacer()
                content
                Spacer()
                if case .saved = model.phase {
                    Button {
                        model.finish()
                    } label: {
                        Text("Готово").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else if case .failed = model.phase {
                    Button {
                        model.cancel()
                    } label: {
                        Text("Закрыть").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
            .padding(24)
            .navigationTitle(Text(verbatim: "FOLIO"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if case .saving = model.phase {
                        Button("Отмена") { model.cancel() }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .saving(let done, let total):
            VStack(spacing: 14) {
                if total > 1 {
                    ProgressView(value: Double(done), total: Double(total)).frame(maxWidth: 220)
                } else {
                    ProgressView().controlSize(.large)
                }
                Text("Передаём файлы в FOLIO…").font(.headline)
            }
        case .saved(let count, let skipped):
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text("Файлы переданы: \(count)")
                    .font(.title3.weight(.semibold))
                Text("Откройте FOLIO — файлы будут уже там. Если черновик пуст, они сразу откроются в редакторе.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if skipped > 0 {
                    Text("Не удалось получить: \(skipped)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        case .failed(let message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text(verbatim: message)
                    .font(.headline)
                    .multilineTextAlignment(.center)
            }
        }
    }
}
