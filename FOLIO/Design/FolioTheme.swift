import SwiftUI

/// Единый дизайн-язык FOLIO. Токены рассчитаны на iPhone, Dynamic Type и тёмную тему.
enum FolioTheme {
    static let blue = Color(red: 0.16, green: 0.32, blue: 0.90)
    static let blueSoft = Color(red: 0.91, green: 0.94, blue: 1.00)
    static let ink = Color(red: 0.075, green: 0.12, blue: 0.22)
    static let secondary = Color(red: 0.40, green: 0.46, blue: 0.56)
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let line = Color(uiColor: .separator).opacity(0.42)
    static let green = Color(red: 0.08, green: 0.56, blue: 0.40)
    static let corner: CGFloat = 18
}

struct FolioPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .padding(.horizontal, 16)
            .background(FolioTheme.blue, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.90 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct FolioSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(FolioTheme.blue)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 12)
            .background(FolioTheme.blueSoft, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct FolioQuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct FolioBrandMark: View {
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: "doc.on.doc.fill")
            .font(.system(size: size * 0.46, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(FolioTheme.blue, in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct FolioSectionHeader: View {
    let title: String
    var trailing: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
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
    let name: String
    let detail: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(FolioTheme.blue)
                    .frame(width: 43, height: 43)
                    .background(FolioTheme.blueSoft, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 82)
            .background(FolioTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(FolioQuietButtonStyle())
        .accessibilityLabel("\(name). \(detail)")
    }
}

struct FolioInlineMessage: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(FolioTheme.blue)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(FolioTheme.card, in: RoundedRectangle(cornerRadius: FolioTheme.corner))
    }
}
