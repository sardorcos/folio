import SwiftUI
import VisionKit
import UIKit

/// Обёртка над системной камерой документов. Закрытие управляется снаружи (через состояние хранилища),
/// чтобы не зависеть от environment-значений внутри Coordinator.
struct FolioScannerView: UIViewControllerRepresentable {
    let onComplete: ([UIImage]) -> Void
    let onCancel: () -> Void
    let onError: (Error) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let camera = VNDocumentCameraViewController()
        camera.delegate = context.coordinator
        return camera
    }

    func updateUIViewController(_ camera: VNDocumentCameraViewController, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        var parent: FolioScannerView
        init(parent: FolioScannerView) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            // Только извлекаем изображения; сжатие и запись PDF выполняются вне главного потока.
            let images = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            parent.onComplete(images)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: Error) {
            parent.onError(error)
        }
    }
}
