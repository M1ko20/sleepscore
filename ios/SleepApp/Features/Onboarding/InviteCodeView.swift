import SwiftUI

/// Krok 1: kód pozvánky. Jedno pole, velké písmo, 8 znaků.
struct InviteCodeView: View {
    @Binding var code: String
    var error: String?
    var busy: Bool
    var onContinue: () -> Void
    var secondary: (title: String, action: () -> Void)?

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer()
            Text("Sem se dostaneš jen přes kamaráda.")
                .font(Font.app.title)
                .foregroundStyle(Color.app.textPrimary)
            Text("Zadej kód z pozvánky.").captionStyle()

            TextField("", text: $code, prompt: Text("K7MPQX2R").foregroundStyle(Color.app.textTertiary))
                .font(.system(size: 34, weight: .heavy).width(.condensed).monospaced())
                .tracking(4)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.app.textPrimary)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .focused($focused)
                .frame(minHeight: 72)
                .background(Color.app.surfaceRaised, in: RoundedRectangle(cornerRadius: Metrics.controlRadius))
                .padding(.top, 12)
                .onChange(of: code) { _, new in
                    let clean = InviteCode.sanitize(new)
                    if clean != new { code = clean }
                }
                .onSubmit { if code.count == InviteCode.length { onContinue() } }

            if let error {
                Text(error).font(Font.app.caption).foregroundStyle(Color.app.textPrimary)
            }

            Spacer()

            Button(busy ? "Ověřuju…" : "Pokračovat", action: onContinue)
                .buttonStyle(.primary)
                .disabled(code.count != InviteCode.length || busy)
            if let secondary {
                Button(secondary.title, action: secondary.action)
                    .buttonStyle(.plainText)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(Metrics.screenPadding)
        .onAppear { focused = true }
    }
}
