import SwiftUI

/// Krok 3: přezdívka (kontrola dostupnosti za běhu) a jméno. Uplatní pozvánku.
struct ProfileSetupView: View {
    let code: String
    var onBack: () -> Void
    var onDone: (Profile) -> Void

    private enum Availability: Equatable { case unknown, checking, free, taken, invalid }

    @State private var username = ""
    @State private var displayName = ""
    @State private var availability: Availability = .unknown
    @State private var busy = false
    @State private var error: String?

    private static let pattern = /^[a-z0-9_.]{3,20}$/

    private var trimmedName: String { displayName.trimmingCharacters(in: .whitespaces) }
    private var canSubmit: Bool {
        availability == .free && !trimmedName.isEmpty && trimmedName.count <= 40 && !busy
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer()
            Text("Kdo jsi").font(Font.app.title).foregroundStyle(Color.app.textPrimary)
            Text("Kamarádi tě najdou podle přezdívky.").captionStyle().padding(.bottom, 12)

            Text("Přezdívka").statLabel()
            HStack(spacing: 0) {
                Text("@").foregroundStyle(Color.app.textTertiary)
                TextField("", text: $username, prompt: Text("adam").foregroundStyle(Color.app.textTertiary))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.username)
            }
            .font(Font.app.body)
            .foregroundStyle(Color.app.textPrimary)
            .padding(.horizontal, 14)
            .frame(minHeight: Metrics.buttonHeight)
            .background(Color.app.surfaceRaised, in: RoundedRectangle(cornerRadius: Metrics.controlRadius))
            Text(availabilityText).captionStyle().frame(minHeight: 18)

            Text("Jméno").statLabel().padding(.top, 4)
            TextField("", text: $displayName, prompt: Text("Adam").foregroundStyle(Color.app.textTertiary))
                .textFieldStyle(AppTextFieldStyle())
                .textContentType(.givenName)

            if let error {
                Text(error).font(Font.app.caption).foregroundStyle(Color.app.textPrimary)
            }

            Spacer()

            Button(busy ? "Zakládám…" : "Pokračovat", action: submit)
                .buttonStyle(.primary)
                .disabled(!canSubmit)
            Button("Jiný kód", action: onBack)
                .buttonStyle(.plainText)
                .frame(maxWidth: .infinity)
        }
        .padding(Metrics.screenPadding)
        .onChange(of: username) { _, new in
            let lower = new.lowercased()
            if lower != new { username = lower }
        }
        .task(id: username) { await checkAvailability() }
    }

    private var availabilityText: String {
        switch availability {
        case .unknown: "3–20 znaků: a–z, 0–9, tečka, podtržítko."
        case .checking: "Kontroluju…"
        case .free: "Volná."
        case .taken: "Zabraná."
        case .invalid: "Jen a–z, 0–9, tečka, podtržítko. 3–20 znaků."
        }
    }

    private func checkAvailability() async {
        let name = username
        guard !name.isEmpty else { availability = .unknown; return }
        guard name.wholeMatch(of: Self.pattern) != nil else { availability = .invalid; return }
        availability = .checking
        try? await Task.sleep(for: .milliseconds(400))   // debounce
        guard !Task.isCancelled else { return }
        let free = (try? await API.usernameAvailable(name)) ?? false
        guard !Task.isCancelled else { return }
        availability = free ? .free : .taken
    }

    private func submit() {
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                let profile = try await API.redeemInvite(code: code, username: username, displayName: trimmedName)
                onDone(profile)
            } catch {
                self.error = serverMessage(error)
                if self.error == "Přezdívka je zabraná." { availability = .taken }
            }
        }
    }
}
