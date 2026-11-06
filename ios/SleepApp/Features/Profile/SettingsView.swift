import SwiftUI

/// Nastavení: jméno, Apple Health, odhlášení.
struct SettingsView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var saving = false
    @State private var error: String?

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool {
        !trimmed.isEmpty && trimmed.count <= 40 && trimmed != session.profile?.displayName && !saving
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Jméno").statLabel()
                        TextField("Jméno", text: $name)
                            .textFieldStyle(AppTextFieldStyle())
                            .textContentType(.name)
                            .submitLabel(.done)
                            .onSubmit(save)
                        HStack {
                            Text("@\(session.profile?.username ?? "") · přezdívka se měnit nedá").captionStyle()
                            Spacer()
                            if canSave {
                                Button(saving ? "Ukládám…" : "Uložit", action: save)
                                    .font(Font.app.body.weight(.semibold))
                                    .tint(Color.app.accent)
                            }
                        }
                        if let error { Text(error).captionStyle() }
                    }
                    HealthSection()
                    Button("Odhlásit") {
                        dismiss()
                        Task { await session.signOut() }
                    }
                    .buttonStyle(.plainText)
                }
                .padding(Metrics.screenPadding)
            }
            .background(Color.app.bg)
            .navigationTitle("Nastavení")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hotovo") { dismiss() }.tint(Color.app.textPrimary)
                }
            }
            .onAppear { name = session.profile?.displayName ?? "" }
        }
        .presentationBackground(Color.app.bg)
    }

    private func save() {
        guard canSave, let me = session.profile?.id else { return }
        saving = true
        Task {
            do {
                try await API.updateDisplayName(trimmed, me: me)
                await session.reloadProfile()
                error = nil
            } catch {
                self.error = serverMessage(error)
            }
            saving = false
        }
    }
}
