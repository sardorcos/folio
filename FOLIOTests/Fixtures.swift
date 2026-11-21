import ImageIO
import PDFKit
import UIKit
import UniformTypeIdentifiers
import XCTest

/// Тестовые файлы создаются на лету: в репозитории нет пользовательских документов.
enum Fixtures {
    static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FOLIOTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// PDF, в котором ширина каждой страницы задана явно — по ней проверяется порядок страниц.
    static func makePDF(widths: [CGFloat], at url: URL) throws {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 400, height: 600))
        try renderer.writePDF(to: url) { context in
            for (index, width) in widths.enumerated() {
                context.beginPage(withBounds: CGRect(x: 0, y: 0, width: width, height: 600), pageInfo: [:])
                ("Страница \(index + 1)" as NSString).draw(at: CGPoint(x: 20, y: 20),
                                                           withAttributes: [.font: UIFont.systemFont(ofSize: 24)])
            }
        }
    }

    static func makeEncryptedPDF(at url: URL, password: String) throws {
        let plain = url.deletingLastPathComponent().appendingPathComponent("plain-\(UUID().uuidString).pdf")
        try makePDF(widths: [400, 400], at: plain)
        let document = try XCTUnwrap(PDFDocument(url: plain))
        XCTAssertTrue(document.write(to: url, withOptions: [.userPasswordOption: password,
                                                            .ownerPasswordOption: password + "-owner"]))
    }

    /// JPEG заданного размера. `noisy` даёт плохо сжимаемое изображение для проверки сжатия.
    static func makeJPEG(width: Int, height: Int, noisy: Bool = false, orientation: Int = 1) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let size = CGSize(width: width, height: height)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            if noisy {
                var generator = SystemRandomNumberGenerator()
                for _ in 0..<6000 {
                    UIColor(red: .random(in: 0...1, using: &generator),
                            green: .random(in: 0...1, using: &generator),
                            blue: .random(in: 0...1, using: &generator), alpha: 1).setFill()
                    let rect = CGRect(x: .random(in: 0..<size.width, using: &generator),
                                      y: .random(in: 0..<size.height, using: &generator),
                                      width: .random(in: 4...40, using: &generator),
                                      height: .random(in: 4...40, using: &generator))
                    context.fill(rect)
                }
            }
        }
        let cgImage = try XCTUnwrap(image.cgImage)
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data as CFMutableData,
                                                                          UTType.jpeg.identifier as CFString, 1, nil))
        let properties: [CFString: Any] = [
            kCGImagePropertyOrientation: orientation,
            kCGImageDestinationLossyCompressionQuality: 0.95
        ]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    static func pageWidths(of url: URL) throws -> [Int] {
        let document = try XCTUnwrap(PDFDocument(url: url))
        return (0..<document.pageCount).compactMap { index in
            document.page(at: index).map { Int($0.bounds(for: .mediaBox).width.rounded()) }
        }
    }
}
