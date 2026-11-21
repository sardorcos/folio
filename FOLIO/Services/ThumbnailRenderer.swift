import PDFKit
import UIKit

/// Рендер миниатюр страниц вне главного потока с кэшем.
/// Документы PDFKit открываются один раз и используются последовательно внутри актора.
actor ThumbnailRenderer {
    static let shared = ThumbnailRenderer()

    private var documents: [URL: PDFDocument] = [:]
    private var openOrder: [URL] = []
    private let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 400
        return cache
    }()

    func thumbnail(url: URL, pageIndex: Int, rotation: Int, size: CGSize) -> UIImage? {
        let degrees = PDFWorker.normalizedRotation(rotation)
        let key = "\(url.lastPathComponent)#\(pageIndex)#\(degrees)#\(Int(size.width))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let document = document(for: url), let page = document.page(at: pageIndex) else { return nil }
        let base = page.thumbnail(of: size, for: .cropBox)
        let image = degrees == 0 ? base : base.folioRotated(byDegrees: degrees)
        cache.setObject(image, forKey: key)
        return image
    }

    /// Вызывается после удаления документа.
    func forget(url: URL) {
        documents[url] = nil
        openOrder.removeAll { $0 == url }
        cache.removeAllObjects()
    }

    func forgetAll() {
        documents.removeAll()
        openOrder.removeAll()
        cache.removeAllObjects()
    }

    private func document(for url: URL) -> PDFDocument? {
        if let open = documents[url] { return open }
        guard let opened = PDFDocument(url: url) else { return nil }
        documents[url] = opened
        openOrder.append(url)
        if openOrder.count > 12 {
            let oldest = openOrder.removeFirst()
            documents[oldest] = nil
        }
        return opened
    }
}

extension UIImage {
    /// Поворот по часовой стрелке (как `PDFPage.rotation`).
    func folioRotated(byDegrees degrees: Int) -> UIImage {
        let turn = PDFWorker.normalizedRotation(degrees)
        guard turn != 0 else { return self }
        let swap = turn % 180 != 0
        let newSize = swap ? CGSize(width: size.height, height: size.width) : size
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: newSize, format: format).image { context in
            let cg = context.cgContext
            cg.translateBy(x: newSize.width / 2, y: newSize.height / 2)
            cg.rotate(by: CGFloat(turn) * .pi / 180)
            draw(in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
        }
    }
}
