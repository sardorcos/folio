import CoreGraphics
import CoreText
import Foundation
import UIKit
import Vision

/// Строка, распознанная на странице. `box` — нормализованные координаты Vision (0…1, начало внизу слева).
struct RecognizedLine: Sendable, Equatable {
    let text: String
    let box: CGRect
}

/// Распознавание текста (OCR) на устройстве через Vision. Сеть не используется.
enum TextRecognizer {
    /// Языки распознавания: русский и английский.
    static let languages = ["ru-RU", "en-US"]

    static func recognizeLines(in image: CGImage) throws -> [RecognizedLine] {
        try Task.checkCancellation()
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.revision = VNRecognizeTextRequestRevision3
        request.recognitionLanguages = languages
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        try handler.perform([request])
        let observations = request.results ?? []
        return observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first,
                  candidate.confidence >= 0.3 else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return RecognizedLine(text: text, box: observation.boundingBox)
        }
    }

    /// Рисует распознанные строки невидимым текстом поверх изображения страницы.
    /// Так PDF остаётся визуально прежним, но текст можно найти, выделить и скопировать.
    /// - Parameters:
    ///   - pageRect: прямоугольник, в который нарисовано изображение (координаты UIKit, начало вверху слева).
    ///   - context: контекст `UIGraphicsPDFRenderer`.
    static func drawInvisibleText(_ lines: [RecognizedLine], in pageRect: CGRect, context: CGContext) {
        guard !lines.isEmpty else { return }
        context.saveGState()
        context.setTextDrawingMode(.invisible)
        for line in lines {
            let rect = CGRect(x: pageRect.minX + line.box.minX * pageRect.width,
                              y: pageRect.minY + (1 - line.box.maxY) * pageRect.height,
                              width: line.box.width * pageRect.width,
                              height: line.box.height * pageRect.height)
            guard rect.width > 1, rect.height > 1 else { continue }
            let font = UIFont.systemFont(ofSize: max(1, rect.height * 0.85))
            let attributed = NSAttributedString(string: line.text, attributes: [.font: font])
            let ctLine = CTLineCreateWithAttributedString(attributed as CFAttributedString)
            let width = CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil))
            guard width > 0 else { continue }
            context.saveGState()
            context.textMatrix = .identity
            // UIKit-контекст перевёрнут относительно Core Text: возвращаем ось Y и растягиваем строку по ширине рамки.
            context.translateBy(x: rect.minX, y: rect.maxY - rect.height * 0.18)
            context.scaleBy(x: rect.width / width, y: -1)
            context.textPosition = .zero
            CTLineDraw(ctLine, context)
            context.restoreGState()
        }
        context.restoreGState()
    }
}
