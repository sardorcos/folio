import SwiftUI
import VisionKit
import UIKit

struct FolioScannerView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onComplete: ([Data]) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let camera = VNDocumentCameraViewController()
        camera.delegate = context.coordinator
        return camera
    }

    func updateUIViewController(_ camera: VNDocumentCameraViewController, context: Context) { }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: FolioScannerView
        init(parent: FolioScannerView) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            let images = (0..<scan.pageCount).compactMap { index in
                scan.imageOfPage(at: index).jpegData(compressionQuality: 0.90)
            }
            parent.dismiss()
            parent.onComplete(images)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.dismiss()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: Error) {
            parent.dismiss()
        }
    }
}
