import SwiftUI
import UIKit

/// Единый дизайн-язык FOLIO. Все цвета адаптивные (светлая/тёмная тема),
/// контраст текста проверен по WCAG AA (≥ 4.5:1).
enum FolioTheme {
    /// Акцент для текста, иконок и ссылок. Светлая: #2952E6, тёмная: #7F9CFF.
    static let blue = dynamic(light: 0x2952E6, dark: 0x7F9CFF)
    /// Заливка главных кнопок под белым текстом. Тёмная: #4169F0 (контраст с белым 4.7:1).
    static let fill = dynamic(light: 0x2952E6, dark: 0x4169F0)
    /// Мягкий фон для вторичных кнопок и плашек.
    static let blueSoft = dynamic(light: 0xEAF0FF, dark: 0x1F2B4D)
    static let green = dynamic(light: 0x0E7A56, dark: 0x30D18C)
    static let secondary = Color(uiColor: .secondaryLabel)
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let line = Color(uiColor: .separator)
    static let corner: CGFloat = 18

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

// MARK: - Кнопки

struct FolioPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FolioButtonBody(configuration: configuration, prominent: true)
    }
}

struct FolioSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FolioButtonBody(configuration: configuration, prominent: false)
    }
}

/// Отдельный View, чтобы читать `isEnabled` из окружения: у неактивной кнопки должен быть неактивный вид.
private struct FolioButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .headline) private var minHeight: CGFloat = 52

    var body: some View {
        configuration.label
            .font(prominent ? .headline : .subheadline.weight(.semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(background, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var foreground: Color {
        guard isEnabled else { return Color(uiColor: .tertiaryLabel) }
        return prominent ? .white : FolioTheme.blue
    }

    private var background: Color {
        guard isEnabled else { return Color(uiColor: .tertiarySystemFill) }
        return prominent ? FolioTheme.fill : FolioTheme.blueSoft
    }
}

struct FolioQuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Компоненты

struct FolioBrandMark: View {
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: "doc.on.doc.fill")
            .font(.system(size: size * 0.46, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(FolioTheme.fill, in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct FolioSectionHeader: View {
    let title: LocalizedStringKey
    var trailing: LocalizedStringKey? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let trailing, let action {
                Button(trailing, action: action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FolioTheme.blue)
                    .buttonStyle(FolioQuietButtonStyle())
            }
        }
    }
}

struct FolioToolTile: View {
    let name: LocalizedStringKey
    let detail: LocalizedStringKey
    let symbol: String
    let action: () -> Void
    @ScaledMetric(relativeTo: .title3) private var iconSize: CGFloat = 43

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(FolioTheme.blue)
                    .frame(width: iconSize, height: iconSize)
                    .background(FolioTheme.blueSoft, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 82)
            .background(FolioTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(FolioQuietButtonStyle())
        .accessibilityElement(children: .combine)
    }
}

struct FolioInlineMessage: View {
    let symbol: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    var tint: Color = FolioTheme.blue

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.footnote).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(FolioTheme.card, in: RoundedRectangle(cornerRadius: FolioTheme.corner))
        .accessibilityElement(children: .combine)
    }
}

/// Круглая радиокнопка-строка с правильными признаками доступности.
struct FolioChoiceRow: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(FolioTheme.blue)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(FolioTheme.card, in: RoundedRectangle(cornerRadius: 15))
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .strokeBorder(isSelected ? FolioTheme.blue : .clear, lineWidth: 1.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
