import SwiftUI

/// Logo Bedrival (měsíc s krátery). Kreslí `MoonLogoDrawing` – stejný tvar jako ikona appky.
struct MoonLogo: View {
    var size: CGFloat = 56

    var body: some View {
        Canvas { context, canvasSize in
            context.withCGContext { cg in
                MoonLogoDrawing.draw(in: cg, rect: CGRect(origin: .zero, size: canvasSize))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// „☾ BEDRIVAL“ – podpis na sdílených obrázcích (recap, Wrapped).
struct BrandMark: View {
    var body: some View {
        HStack(spacing: 4) {
            MoonLogo(size: 22)
            Text("Bedrival").font(Font.app.label).tracking(1.2).textCase(.uppercase)
                .foregroundStyle(Color.app.accent)
        }
    }
}

#Preview {
    VStack(spacing: 24) {
        MoonLogo(size: 160)
        BrandMark()
    }
    .padding()
    .background(Color.app.bg)
}
