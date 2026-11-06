import SwiftUI

/// Detail noci (design.md → Detail noci).
struct NightDetailView: View {
    let postID: UUID

    @Environment(Session.self) private var session
    @Environment(FeedStore.self) private var store
    @State private var heartRate: [HeartRatePoint] = []
    @State private var comments: [Comment] = []
    @State private var draft = ""
    @State private var sending = false
    @State private var editing = false
    @FocusState private var composing: Bool

    private var me: UUID? { session.profile?.id }

    var body: some View {
        Group {
            if let post = store.post(postID) {
                content(post)
            } else {
                Text("Karta už není k dispozici.").captionStyle()
            }
        }
        .background(Color.app.bg)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadExtras() }
    }

    private func content(_ post: FeedPost) -> some View {
        let night = post.night
        let tz = post.author.timeZone
        let isMine = post.author.id == me
        return ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // Autor a datum
                NavigationLink(value: post.author) {
                    HStack(spacing: 10) {
                        Avatar(profile: post.author, size: 36)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(isMine ? "Ty" : post.author.displayName)
                                .font(Font.app.body.weight(.semibold)).foregroundStyle(Color.app.textPrimary)
                            Text(Fmt.nightDate(night.nightDate)).captionStyle()
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isMine)

                if let title = post.title, !title.isEmpty {
                    Text(title).font(Font.app.title).foregroundStyle(Color.app.textPrimary)
                }
                if let body = post.body, !body.isEmpty {
                    Text(body).font(Font.app.body).foregroundStyle(Color.app.textPrimary)
                }

                // Skóre + 3 statistiky
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(night.score.map(String.init) ?? "–").font(Font.app.scoreXL)
                            .foregroundStyle(Color.app.textPrimary)
                        Text("Skóre").statLabel()
                    }
                    HStack(spacing: 28) {
                        StatBlock(value: Fmt.duration(minutes: night.totalSleepMin), label: "Délka")
                        StatBlock(value: Fmt.time(night.sleepStart, in: tz), label: "Usnutí")
                        StatBlock(value: Fmt.time(night.sleepEnd, in: tz), label: "Vstávání")
                    }
                }

                Hypnogram(segments: night.segments, start: night.sleepStart, end: night.sleepEnd,
                          heartRate: heartRate, timeZone: tz)

                stageBars(night)
                breakdown(night)

                if !night.tags.isEmpty {
                    section("Tagy") { Text(store.tagLine(night.tags)).statLabel().foregroundStyle(Color.app.textPrimary) }
                }

                if let photo = post.photoPath {
                    PostPhoto(path: photo)
                }

                let achievements = night.achievementCodes.compactMap { store.achievementNames[$0] }
                if !achievements.isEmpty {
                    section("Odznaky") {
                        ForEach(achievements, id: \.self) { name in
                            HStack(spacing: 8) {
                                Image(systemName: "hexagon").foregroundStyle(Color.app.accent)
                                Text(name).foregroundStyle(Color.app.textPrimary)
                            }
                            .font(Font.app.body)
                        }
                    }
                }

                if !isMine {
                    ReactionPicker(current: post.reactions.first { $0.userID == me }?.kind) { kind in
                        guard let me else { return }
                        Task { await store.react(post.id, me: me, kind: kind) }
                    }
                }
                ReactionSummary(reactions: post.reactions, me: me)

                commentsSection(post)
            }
            .padding(Metrics.screenPadding)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { composer(post) }
        .toolbar {
            if isMine {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Upravit") { editing = true }
                }
            }
        }
        .sheet(isPresented: $editing) { EditPostSheet(post: post) }
    }

    // MARK: Sekce

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).statLabel()
            content()
        }
    }

    private func stageBars(_ night: Night) -> some View {
        let rows: [(SleepStage, Int)] = [(.awake, night.awakeMin), (.rem, night.remMin), (.core, night.coreMin), (.deep, night.deepMin)]
        let maxMin = max(1, rows.map(\.1).max() ?? 1)
        return section("Fáze") {
            ForEach(rows, id: \.0) { stage, minutes in
                HStack(spacing: 12) {
                    Text(stage.label).statLabel().frame(width: 52, alignment: .leading)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(stage.color)
                            .frame(width: max(2, geo.size.width * CGFloat(minutes) / CGFloat(maxMin)))
                    }
                    .frame(height: 8)
                    Text(Fmt.duration(minutes: minutes))
                        .font(Font.app.caption.monospacedDigit())
                        .foregroundStyle(Color.app.textPrimary)
                        .frame(width: 64, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func breakdown(_ night: Night) -> some View {
        let parts: [(key: String, label: String)] = [
            ("duration", "Délka"), ("stages", "Fáze"), ("interruptions", "Přerušovanost"),
            ("regularity", "Pravidelnost"), ("heart_rate", "Tep"),
        ]
        return section("Rozpad skóre") {
            ForEach(parts, id: \.key) { part in
                let value = night.scoreBreakdown?[part.key] ?? nil
                HStack(spacing: 12) {
                    Text(part.label).font(Font.app.caption)
                        .foregroundStyle(value == nil ? Color.app.textTertiary : Color.app.textPrimary)
                        .frame(width: 104, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.app.surfaceRaised)
                            if let value {
                                Capsule().fill(Color.app.textPrimary)
                                    .frame(width: geo.size.width * CGFloat(value) / 100)
                            }
                        }
                    }
                    .frame(height: 3)
                    Text(value.map { "\(Int($0.rounded()))" } ?? "bez dat")
                        .font(Font.app.caption.monospacedDigit())
                        .foregroundStyle(value == nil ? Color.app.textTertiary : Color.app.textPrimary)
                        .frame(width: 52, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func commentsSection(_ post: FeedPost) -> some View {
        section("Komentáře") {
            if comments.isEmpty {
                Text("Zatím ticho.").captionStyle()
            }
            ForEach(comments) { c in
                HStack(alignment: .top, spacing: 10) {
                    Avatar(profile: c.author)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(c.author.id == me ? "Ty" : c.author.displayName)
                                .font(Font.app.caption.weight(.semibold)).foregroundStyle(Color.app.textPrimary)
                            Text(Fmt.postStamp(c.createdAt)).font(Font.app.caption).foregroundStyle(Color.app.textTertiary)
                        }
                        Text(c.body).font(Font.app.body).foregroundStyle(Color.app.textPrimary)
                    }
                    Spacer(minLength: 0)
                }
                .contextMenu {
                    if c.author.id == me || post.author.id == me {
                        Button("Smazat", role: .destructive) { delete(c, post: post) }
                    }
                }
            }
        }
    }

    private func composer(_ post: FeedPost) -> some View {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return HStack(spacing: 8) {
            TextField("", text: $draft, prompt: Text("Komentář").foregroundStyle(Color.app.textTertiary), axis: .vertical)
                .lineLimit(1...4)
                .font(Font.app.body)
                .foregroundStyle(Color.app.textPrimary)
                .focused($composing)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Color.app.surfaceRaised, in: RoundedRectangle(cornerRadius: Metrics.controlRadius))
            if !text.isEmpty {
                Button { send(post) } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.app.accentInk)
                        .frame(width: 44, height: 44)
                        .background(Color.app.accent, in: RoundedRectangle(cornerRadius: Metrics.controlRadius))
                }
                .disabled(sending)
                .accessibilityLabel("Odeslat")
            }
        }
        .padding(.horizontal, Metrics.screenPadding)
        .padding(.vertical, 8)
        .background(Color.app.bg.overlay(alignment: .top) { Rectangle().fill(Color.app.hairline).frame(height: 1) })
    }

    // MARK: Akce

    private func loadExtras() async {
        guard let post = store.post(postID) else { return }
        async let hr = API.heartRate(nightID: post.night.id)
        async let cs = API.comments(postID: postID)
        heartRate = (try? await hr) ?? []
        if let list = try? await cs {
            comments = list
            store.setCommentCount(postID: postID, list.count)
        }
    }

    private func send(_ post: FeedPost) {
        guard let me else { return }
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, body.count <= 1000 else { return }
        sending = true
        Task {
            defer { sending = false }
            if let c = try? await API.addComment(postID: post.id, userID: me, body: body) {
                comments.append(c)
                draft = ""
                store.setCommentCount(postID: post.id, comments.count)
            }
        }
    }

    private func delete(_ c: Comment, post: FeedPost) {
        Task {
            if (try? await API.deleteComment(id: c.id)) != nil {
                comments.removeAll { $0.id == c.id }
                store.setCommentCount(postID: post.id, comments.count)
            }
        }
    }
}
