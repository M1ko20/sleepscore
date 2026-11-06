import PhotosUI
import SwiftUI

/// Nastavení: profilovka, jméno, Apple Health, odhlášení.
struct SettingsView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var saving = false
    @State private var error: String?
    @State private var pickedItem: PhotosPickerItem?
    @State private var avatarBusy = false
    @State private var avatarError: String?

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool {
        !trimmed.isEmpty && trimmed.count <= 40 && trimmed != session.profile?.displayName && !saving
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    avatarSection
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

    private var avatarSection: some View {
        let hasAvatar = session.profile?.avatarPath != nil
        return HStack(spacing: 16) {
            if let p = session.profile {
                Avatar(profile: p.lite, size: 72)
                    .opacity(avatarBusy ? 0.4 : 1)
                    .overlay { if avatarBusy { ProgressView().tint(Color.app.textPrimary) } }
            }
            VStack(alignment: .leading, spacing: 8) {
                PhotosPicker(selection: $pickedItem, matching: .images, photoLibrary: .shared()) {
                    Text(hasAvatar ? "Změnit fotku" : "Přidat fotku")
                        .font(Font.app.body.weight(.semibold))
                        .foregroundStyle(Color.app.accent)
                }
                if hasAvatar {
                    Button("Odebrat") { Task { await setAvatar(nil) } }
                        .font(Font.app.caption)
                        .foregroundStyle(Color.app.textSecondary)
                }
                if let avatarError { Text(avatarError).captionStyle() }
            }
            .disabled(avatarBusy)
        }
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }
            pickedItem = nil
            Task {
                avatarBusy = true
                defer { avatarBusy = false }
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let img = UIImage(data: data), let jpeg = ImageResize.avatar(img) else {
                    avatarError = "Fotku se nepodařilo načíst."
                    return
                }
                await setAvatar(jpeg)
            }
        }
    }

    /// Nahraje novou (nebo odebere) profilovku, starý soubor smaže.
    private func setAvatar(_ jpeg: Data?) async {
        guard let me = session.profile?.id else { return }
        let old = session.profile?.avatarPath
        avatarBusy = true
        defer { avatarBusy = false }
        do {
            var path: String?
            if let jpeg {
                let p = try await API.uploadImage(jpeg, bucket: .avatars, me: me)
                await ImageStore.shared.store(jpeg, .avatars, p)
                path = p
            }
            try await API.setAvatarPath(path, me: me)
            if let old {
                await API.removeImage(old, bucket: .avatars)
                await ImageStore.shared.remove(.avatars, old)
            }
            await session.reloadProfile()
            avatarError = nil
        } catch {
            avatarError = serverMessage(error)
        }
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
