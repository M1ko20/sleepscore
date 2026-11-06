import SwiftUI

/// Testovací přihlášení e-mailem. Do Apple Developer Programu místo Sign in with Apple.
struct DevLoginView: View {
    @Environment(Session.self) private var session
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var message: String?

    private var canSubmit: Bool { email.contains("@") && password.count >= 6 && !busy }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer()
            Text("Přihlášení")
                .font(Font.app.title)
                .foregroundStyle(Color.app.textPrimary)
            Text("Testovací účet (zakládá se přes admin API). Sign in with Apple přijde s Developer Programem.")
                .captionStyle()
                .padding(.bottom, 12)

            TextField("", text: $email, prompt: prompt("E-mail"))
                .textFieldStyle(AppTextFieldStyle())
                .keyboardType(.emailAddress)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("", text: $password, prompt: prompt("Heslo"))
                .textFieldStyle(AppTextFieldStyle())
                .textContentType(.password)

            if let message {
                Text(message).captionStyle()
            }

            Spacer()

            Button(busy ? "Přihlašuju…" : "Přihlásit") { submit() }
                .buttonStyle(.primary)
                .disabled(!canSubmit)
        }
        .padding(Metrics.screenPadding)
    }

    private func prompt(_ text: String) -> Text {
        Text(text).foregroundStyle(Color.app.textTertiary)
    }

    private func submit() {
        busy = true
        message = nil
        Task {
            defer { busy = false }
            do {
                try await session.signIn(email: email, password: password)
            } catch {
                message = "Nepovedlo se: \(error.localizedDescription)"
            }
        }
    }
}
