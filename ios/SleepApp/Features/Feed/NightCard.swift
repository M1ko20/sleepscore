import SwiftUI

/// Karta noci ve feedu (design.md → Karta noci).
struct NightCard: View {
    let post: FeedPost
    let me: UUID?
    var streak: Int?
    var tagLine: String
    var achievementNames: [String]
    var onEdit: (() -> Void)?
    var onOpen: () -> Void = {}
    var onReact: (ReactionKind?) -> Void

    @State private var picking = false
    @State private var shownScore = 0

    private var isMine: Bool { post.author.id == me }
    private var highlight: Bool { isMine && post.needsDetails && Calendar.current.isDateInToday(post.createdAt) }
    private var myReaction: ReactionKind? { post.reactions.first { $0.userID == me }?.kind }
    private var night: Night { post.night }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if isMine, post.hiddenAt != nil {
                HiddenByReportsNotice()
            }

            Text(post.displayTitle).font(Font.app.title).foregroundStyle(Color.app.textPrimary)
            if let body = post.body, !body.isEmpty {
                Text(body).font(Font.app.body).foregroundStyle(Color.app.textPrimary).lineLimit(3)
            }
            if let photo = post.photoPath {
                PostPhoto(path: photo)
            }

            HStack(alignment: .firstTextBaseline, spacing: 28) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(shownScore)")
                        .font(Font.app.scoreL)
                        .foregroundStyle(Color.app.textPrimary)
                        .contentTransition(.numericText(value: Double(shownScore)))
                    Text("Skóre").statLabel()
                }
                StatBlock(value: Fmt.duration(minutes: night.totalSleepMin), label: "Délka")
                StatBlock(value: Fmt.time(night.sleepStart, in: post.author.timeZone), label: "Usnutí")
            }
            .accessibilityElement(children: .combine)

            MiniHypnogram(segments: night.segments, start: night.sleepStart, end: night.sleepEnd)

            if !tagLine.isEmpty {
                Text(tagLine).statLabel()
            }

            if let first = achievementNames.first {
                HStack(spacing: 6) {
                    Image(systemName: "hexagon").font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.app.accent)
                    Text(achievementNames.count > 1 ? "\(first) +\(achievementNames.count - 1)" : first)
                        .font(Font.app.caption.weight(.semibold))
                        .foregroundStyle(Color.app.textPrimary)
                }
            }

            if picking {
                ReactionPicker(current: myReaction) { kind in
                    onReact(kind)
                    withAnimation(.snappy) { picking = false }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .bottomLeading)))
            }

            footer

            if highlight, let onEdit {
                Button(action: onEdit) {
                    HStack {
                        Text("Doplň název a tagy")
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .medium))
                    }
                    .font(Font.app.body.weight(.semibold))
                    .foregroundStyle(Color.app.accent)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .cardStyle(highlighted: highlight)
        // Klepnutí i podržení přímo na kartě, ne NavigationLink kolem ní: na iOS 17 long press
        // uvnitř NavigationLinku ve ScrollView spolkl klepnutí a zasekával scroll.
        // Tap před long pressem = scroll začne, i když prst chvíli stojí.
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
        .onLongPressGesture(minimumDuration: 0.35) {
            guard !isMine else { return }
            withAnimation(.snappy) { picking = true }
        }
        .task {
            guard shownScore == 0, let score = night.score else { return }
            withAnimation(.easeOut(duration: 0.6)) { shownScore = score }
        }
        .onChange(of: night.score) { _, new in shownScore = new ?? 0 }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Avatar(profile: post.author)
            Text(isMine ? "Ty" : post.author.displayName)
                .font(Font.app.body.weight(.semibold))
                .foregroundStyle(Color.app.textPrimary)
            Spacer()
            if let streak {
                Text("Série \(streak)").statLabel()
            }
            Text(Fmt.postStamp(post.createdAt)).font(Font.app.caption.monospacedDigit())
                .foregroundStyle(Color.app.textSecondary)
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            ReactionSummary(reactions: post.reactions, me: me)
            Spacer()
            if !isMine {
                Button {
                    withAnimation(.snappy) { picking.toggle() }
                } label: {
                    Image(systemName: myReaction?.symbol ?? "plus.circle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(myReaction == nil ? Color.app.textSecondary : Color.app.accent)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reagovat")
            }
            HStack(spacing: 4) {
                Image(systemName: "text.bubble").font(.system(size: 14, weight: .medium))
                Text("\(post.commentCount)").font(Font.app.caption.monospacedDigit())
            }
            .foregroundStyle(Color.app.textSecondary)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Komentáře \(post.commentCount)")
        }
        .frame(minHeight: 44)
    }
}

/// Vlastní obsah skrytý ostatním po hlášeních (backend.md → Moderace). Vidí jen autor.
struct HiddenByReportsNotice: View {
    var compact = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "eye.slash").font(.system(size: 12, weight: .semibold))
            Text(compact ? "Skryto ostatním po nahlášení"
                         : "Skryto ostatním po nahlášení. Projdeme to do 24 h.")
        }
        .font(Font.app.caption)
        .foregroundStyle(Color.app.destructive)
        .accessibilityElement(children: .combine)
    }
}
