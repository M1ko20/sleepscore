import SwiftUI

/// Přihlášený bez profilu: (kód) → přezdívka a jméno → Apple Health → appka.
struct OnboardingFlow: View {
    @Environment(Session.self) private var session

    private enum Step { case code, profile, health(Profile) }

    @State private var step: Step = .code
    @State private var code = ""
    @State private var codeError: String?
    @State private var busy = false
    @State private var didAutoCheck = false

    var body: some View {
        Group {
            switch step {
            case .code:
                InviteCodeView(
                    code: $code, error: codeError, busy: busy,
                    onContinue: checkCode,
                    secondary: ("Odhlásit", { Task { await session.signOut() } })
                )
            case .profile:
                ProfileSetupView(code: code, onBack: { step = .code }) { profile in
                    step = .health(profile)
                }
            case .health(let profile):
                HealthIntroView { session.finishOnboarding(with: profile) }
            }
        }
        .background(Color.app.bg)
        .task {
            // Kód zadaný před přihlášením rovnou ověř.
            guard !didAutoCheck, let pending = session.pendingInviteCode, !pending.isEmpty else { return }
            didAutoCheck = true
            code = pending
            checkCode()
        }
    }

    private func checkCode() {
        busy = true
        codeError = nil
        Task {
            defer { busy = false }
            do {
                if try await API.checkInvite(code) {
                    session.pendingInviteCode = code
                    step = .profile
                } else {
                    codeError = "Kód neplatí nebo už ho někdo použil."
                }
            } catch {
                codeError = serverMessage(error)
            }
        }
    }
}
