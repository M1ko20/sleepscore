import SwiftUI

/// Primární: plné accent, max. jedno na obrazovce.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: Metrics.buttonHeight)
            .foregroundStyle(Color.app.accentInk)
            .background(Color.app.accent.opacity(isEnabled ? 1 : 0.35),
                        in: RoundedRectangle(cornerRadius: Metrics.controlRadius))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: Metrics.buttonHeight)
            .foregroundStyle(Color.app.textPrimary)
            .background(Color.app.surfaceRaised, in: RoundedRectangle(cornerRadius: Metrics.controlRadius))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// Textové: jen textSecondary, bez podtržení.
struct TextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Font.app.body)
            .foregroundStyle(Color.app.textSecondary)
            .frame(minHeight: 44)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle { static var primary: Self { .init() } }
extension ButtonStyle where Self == SecondaryButtonStyle { static var secondary: Self { .init() } }
extension ButtonStyle where Self == TextButtonStyle { static var plainText: Self { .init() } }

/// Vstupní pole: surfaceRaised, rádius 10.
struct AppTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(Font.app.body)
            .foregroundStyle(Color.app.textPrimary)
            .padding(.horizontal, 14)
            .frame(minHeight: Metrics.buttonHeight)
            .background(Color.app.surfaceRaised, in: RoundedRectangle(cornerRadius: Metrics.controlRadius))
    }
}
