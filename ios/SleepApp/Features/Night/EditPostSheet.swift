import SwiftUI

/// Úprava karty: název, komentář, tagy. Fotka přijde se Storage.
struct EditPostSheet: View {
    let post: FeedPost

    @Environment(FeedStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var bodyText: String
    @State private var tags: Set<String>
    @State private var saving = false
    @State private var error: String?

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
                        TextField("", text: $title, prompt: Text("Spal jsem jak dřevo").foregroundStyle(Color.app.textTertiary))
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
                try await API.updatePost(id: post.id, title: t.isEmpty ? nil : t, body: b.isEmpty ? nil : b)
                try await API.setTags(nightID: post.night.id, add: tags.subtracting(old), remove: old.subtracting(tags))
                store.applyEdit(postID: post.id, title: t.isEmpty ? nil : t, body: b.isEmpty ? nil : b, tags: Array(tags))
                dismiss()
            } catch {
                self.error = serverMessage(error)
            }
        }
    }
}
