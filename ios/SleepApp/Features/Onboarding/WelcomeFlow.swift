import SwiftUI

/// Nepřihlášený: kód pozvánky → přihlášení. Kód se ověří až po přihlášení (anon nesmí nic).
struct WelcomeFlow: View {
    @Environment(Session.self) private var session
    @State private var code = ""
    @State private var showLogin = false

    var body: some View {
        NavigationStack {
            InviteCodeView(
                code: $code,
                busy: false,
                onContinue: {
                    session.pendingInviteCode = code
                    showLogin = true
                },
                secondary: ("Už mám účet", {
                    session.pendingInviteCode = nil
                    showLogin = true
                })
            )
            .background(Color.app.bg)
            .navigationDestination(isPresented: $showLogin) {
                DevLoginView().background(Color.app.bg)
            }
        }
        .onAppear { code = session.pendingInviteCode ?? "" }
    }
}
