import PhotosUI
import SwiftUI

/// Úprava karty: název, komentář, tagy, fotka (zmenšená na telefonu na ~200 kB).
struct EditPostSheet: View {
    let post: FeedPost

    @Environment(FeedStore.self) private var store
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var bodyText: String
    @State private var tags: Set<String>
    @State private var saving = false
    @State private var error: String?
    @State private var pickedItem: PhotosPickerItem?
    @State private var newPhoto: (data: Data, image: UIImage)?
    @State private var removePhoto = false
    @State private var loadingPhoto = false

    /// Fotka, která se po uložení ukáže (stávající, pokud ji nenahradím ani neodeberu).
    private var keptPath: String? { removePhoto || newPhoto != nil ? nil : post.photoPath }

    init(post: FeedPost) {
        self.post = post
        _title = State(initialValue: post.title ?? "")
        _bodyText = State(initialValue: post.body ?? "")
        _tags = State(initialValue: Set(post.night.tags))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    field("Název") {
                        TextField("", text: $title, prompt: Text(NightTitle.template(for: post.night, postID: post.id, timezone: post.author.timezone)).foregroundStyle(Color.app.textTertiary))
                            .textFieldStyle(AppTextFieldStyle())
                            .onChange(of: title) { _, v in if v.count > 80 { title = String(v.prefix(80)) } }
                    }
                    field("Komentář") {
                        TextField("", text: $bodyText, prompt: Text("Jak to šlo").foregroundStyle(Color.app.textTertiary), axis: .vertical)
                            .lineLimit(3...8)
                            .font(Font.app.body)
                            .foregroundStyle(Color.app.textPrimary)
                            .padding(14)
                            .background(Color.app.surfaceRaised, in: RoundedRectangle(cornerRadius: Metrics.controlRadius))
                            .onChange(of: bodyText) { _, v in if v.count > 1000 { bodyText = String(v.prefix(1000)) } }
                    }
                    field("Tagy") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                            ForEach(store.tagCatalog) { tag in
                                let on = tags.contains(tag.slug)
                                Button {
                                    if on { tags.remove(tag.slug) } else { tags.insert(tag.slug) }
                                } label: {
                                    Text(tag.label)
                                        .font(Font.app.caption.weight(.semibold))
                                        .foregroundStyle(Color.app.textPrimary)
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .background(Color.app.surfaceRaised, in: RoundedRectangle(cornerRadius: Metrics.controlRadius))
                                        .overlay(RoundedRectangle(cornerRadius: Metrics.controlRadius)
                                            .strokeBorder(on ? Color.app.accent : .clear, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(on ? .isSelected : [])
                            }
                        }
                    }
                    field("Fotka") { photoField }
                    if let error {
                        Text(error).font(Font.app.caption).foregroundStyle(Color.app.textPrimary)
                    }
                }
                .padding(Metrics.screenPadding)
            }
            .background(Color.app.bg)
            .safeAreaInset(edge: .bottom) {
                Button(saving ? "Ukládám…" : "Uložit", action: save)
                    .buttonStyle(.primary)
                    .disabled(saving)
                    .padding(Metrics.screenPadding)
                    .background(Color.app.bg)
            }
            .navigationTitle("Karta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zrušit") { dismiss() }
                }
            }
        }
        .presentationBackground(Color.app.bg)
    }

    @ViewBuilder
    private var photoField: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let newPhoto {
                Image(uiImage: newPhoto.image)
                    .resizable().scaledToFill()
                    .frame(maxWidth: .infinity)
                    .aspectRatio(4.0 / 5.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else if let keptPath {
                PostPhoto(path: keptPath)
            }
            HStack(spacing: 20) {
                PhotosPicker(selection: $pickedItem, matching: .images, photoLibrary: .shared()) {
                    Text(loadingPhoto ? "Načítám…" : (newPhoto != nil || keptPath != nil ? "Změnit fotku" : "Přidat fotku"))
                        .font(Font.app.body.weight(.semibold))
                        .foregroundStyle(Color.app.accent)
                }
                .disabled(loadingPhoto)
                if newPhoto != nil || keptPath != nil {
                    Button("Odebrat") {
                        newPhoto = nil
                        removePhoto = true
                    }
                    .font(Font.app.body)
                    .foregroundStyle(Color.app.textSecondary)
                }
            }
        }
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }
            pickedItem = nil
            loadingPhoto = true
            Task {
                defer { loadingPhoto = false }
                guard let raw = try? await item.loadTransferable(type: Data.self),
                      let img = UIImage(data: raw), let jpeg = ImageResize.photo(img),
                      let small = UIImage(data: jpeg) else {
                    error = "Fotku se nepodařilo načíst."
                    return
                }
                newPhoto = (jpeg, small)
            }
        }
    }

    private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).statLabel()
            content()
        }
    }

    private func save() {
        saving = true
        error = nil
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        let old = Set(post.night.tags)
        Task {
            defer { saving = false }
            do {
                let photoPath = try await savePhoto()
                try await API.updatePost(id: post.id, title: t.isEmpty ? nil : t, body: b.isEmpty ? nil : b)
                try await API.setTags(nightID: post.night.id, add: tags.subtracting(old), remove: old.subtracting(tags))
                store.applyEdit(postID: post.id, title: t.isEmpty ? nil : t, body: b.isEmpty ? nil : b,
                                tags: Array(tags), photoPath: photoPath)
                dismiss()
            } catch {
                self.error = serverMessage(error)
            }
        }
    }

    /// Nahraje novou / odebere fotku. Vrací cestu, která na kartě zůstane.
    private func savePhoto() async throws -> String? {
        guard newPhoto != nil || removePhoto else { return post.photoPath }
        guard let me = session.profile?.id else { return post.photoPath }
        var path: String?
        if let newPhoto {
            let p = try await API.uploadImage(newPhoto.data, bucket: .nightPhotos, me: me)
            await ImageStore.shared.store(newPhoto.data, .nightPhotos, p)
            path = p
        }
        do {
            try await API.setPostPhoto(path, postID: post.id)
        } catch {
            if let path { await API.removeImage(path, bucket: .nightPhotos) }   // ať nezůstane sirotek
            throw error
        }
        if let old = post.photoPath {
            await API.removeImage(old, bucket: .nightPhotos)
            await ImageStore.shared.remove(.nightPhotos, old)
        }
        return path
    }
}
