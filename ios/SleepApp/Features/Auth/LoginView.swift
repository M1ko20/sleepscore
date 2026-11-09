import AuthenticationServices
import CryptoKit
import SwiftUI

/// Přihlášení: Sign in with Apple, pod ním viditelné přihlášení e-mailem
/// (účty zakládáme jen ručně – demo účet pro App Review a testovací účty, issue #18).
struct LoginView: View {
    @Environment(Session.self) private var session
    @State private var email = ""
    @State private var password = ""
    @State private var showEmail = false
    @State private var busy = false
    @State private var message: String?
    /// Nonce poslaný Applu (jako SHA-256) – Supabase ho ověří proti identity tokenu.
    @State private var nonce = ""

    private var canSubmit: Bool { email.contains("@") && password.count >= 6 && !busy }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer()
            Text("Přihlášení")
                .font(Font.app.title)
                .foregroundStyle(Color.app.textPrimary)
            Text("Účet založíš přes Apple. E-mail ani jméno nikde neukazujeme.")
                .captionStyle()
                .padding(.bottom, 12)

            if showEmail {
                TextField("", text: $email, prompt: prompt("E-mail"))
                    .textFieldStyle(AppTextFieldStyle())
                    .keyboardType(.emailAddress)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("", text: $password, prompt: prompt("Heslo"))
                    .textFieldStyle(AppTextFieldStyle())
                    .textContentType(.password)
                    .onSubmit { if canSubmit { submitEmail() } }
            }

            if let message {
                Text(message).captionStyle()
            }

            Spacer()

            if showEmail {
                Button(busy ? "Přihlašuju…" : "Přihlásit") { submitEmail() }
                    .buttonStyle(.primary)
                    .disabled(!canSubmit)
            } else {
                SignInWithAppleButton(.signIn, onRequest: prepare, onCompletion: complete)
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.controlRadius))
                    .disabled(busy)
                    .accessibilityIdentifier("signInWithApple")
            }
            Button(showEmail ? "Zpět na Apple" : "Přihlásit e-mailem") {
                message = nil
                showEmail.toggle()
            }
            .buttonStyle(.plainText)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("toggleEmailLogin")
        }
        .padding(Metrics.screenPadding)
    }

    private func prompt(_ text: String) -> Text {
        Text(text).foregroundStyle(Color.app.textTertiary)
    }

    private func submitEmail() {
        busy = true
        message = nil
        Task {
            defer { busy = false }
            do {
                try await session.signIn(email: email, password: password)
            } catch {
                log.error("email sign-in failed: \(String(describing: error))")
                message = "E-mail nebo heslo nesedí."
            }
        }
    }

    // MARK: Sign in with Apple

    private func prepare(_ request: ASAuthorizationAppleIDRequest) {
        message = nil
        nonce = Self.randomNonce()
        request.requestedScopes = []   // jméno ani e-mail nepotřebujeme, přezdívku si zvolí sám
        request.nonce = Self.sha256(nonce)
    }

    private func complete(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            log.error("apple sign-in failed: \(String(describing: error))")
            message = "Přihlášení přes Apple se nepovedlo. Zkus to znovu."
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8) else {
                message = "Přihlášení přes Apple se nepovedlo. Zkus to znovu."
                return
            }
            let code = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
            busy = true
            Task {
                defer { busy = false }
                do {
                    try await session.signInWithApple(idToken: idToken, nonce: nonce, authorizationCode: code)
                } catch {
                    log.error("apple sign-in (supabase) failed: \(String(describing: error))")
                    message = "Přihlášení přes Apple se nepovedlo. Zkus to znovu."
                }
            }
        }
    }

    private static func randomNonce(length: Int = 32) -> String {
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in chars.randomElement(using: &generator)! })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
