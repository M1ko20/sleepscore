import SwiftUI

/// Jednorázová obrazovka po uzavření výzvy. Konfety jen při výhře (jediné v appce).
struct ChallengeResultView: View {
    let challenge: Challenge
    let me: UUID
    var onClose: () -> Void
    var onRematch: (ProfileLite) -> Void

    @State private var soulLanded = false

    private var mine: Participant? { challenge.me(me) }
    private var result: ChallengeResult? { mine?.result }
    private var winner: Participant? { challenge.accepted.first { $0.result == .win } }
    private var losers: [Participant] { challenge.accepted.filter { $0.result == .loss } }

    var body: some View {
        ZStack {
            Color.app.bg.ignoresSafeArea()
            if result == .win && challenge.type != .teamGoal { Confetti().ignoresSafeArea().allowsHitTesting(false) }

            VStack(alignment: .leading, spacing: 20) {
                Spacer()
                Text(ChallengeCopy.title(challenge, me: me).uppercased() + " · " + Fmt.days(challenge.durationDays).uppercased())
                    .statLabel()
                Text(headline)
                    .font(.system(size: 64, weight: .black).width(.condensed))
                    .foregroundStyle(result == .win ? Color.app.accent : Color.app.textPrimary)
                Text(line).font(Font.app.title).foregroundStyle(Color.app.textPrimary)

                HStack(alignment: .firstTextBaseline, spacing: 28) {
                    StatBlock(value: Fmt.avg(challenge.average(me)), label: "Tvůj průměr", font: Font.app.scoreL)
                    if challenge.type == .teamGoal {
                        StatBlock(value: "\(challenge.targetScore ?? 0)", label: "Cíl")
                    } else {
                        StatBlock(value: Fmt.days(challenge.daysWon(me)), label: "Vyhrané dny")
                    }
                }

                if result == .win, challenge.type != .teamGoal, !losers.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(losers) { l in
                            Avatar(profile: l.profile, size: 48).saturation(0)
                        }
                    }
                    .scaleEffect(soulLanded ? 1 : 1.6)
                    .opacity(soulLanded ? 1 : 0)
                    .offset(y: soulLanded ? 0 : -60)
                    Text(losers.count == 1 ? "Ovečka běží do stáda." : "Ovečky běží do stáda.").captionStyle()
                }

                Spacer()
                if result == .loss, challenge.type == .duel, let w = winner {
                    Button("Odplata") { onRematch(w.profile) }.buttonStyle(.primary)
                }
                Button("Zavřít", action: onClose)
                    .buttonStyle(result == .loss && challenge.type == .duel ? AnyButtonStyle(.plainText) : AnyButtonStyle(.secondary))
                    .frame(maxWidth: .infinity)
            }
            .padding(Metrics.screenPadding)
        }
        .onAppear {
            withAnimation(.spring(duration: 0.9, bounce: 0.3).delay(0.5)) { soulLanded = true }
        }
    }

    private var headline: String {
        switch result {
        case .win: "VÝHRA"
        case .loss: "PROHRA"
        case .draw: "REMÍZA"
        case nil: "KONEC"
        }
    }

    private var line: String {
        switch (challenge.type, result) {
        case (.teamGoal, .win): return "Cíl splněn. Všichni berou výhru."
        case (.teamGoal, _): return "Cíl nesplněn. Prohra pro všechny."
        case (_, .win):
            return losers.count == 1 ? "Bereš ovečku: \(losers[0].profile.displayName)." : (2...4).contains(losers.count) ? "Bereš \(losers.count) ovečky." : "Bereš \(losers.count) oveček."
        case (_, .loss):
            return "\(winner?.profile.displayName ?? "Soupeř") bere tvoji ovečku. Příště dřív do postele."
        case (_, .draw): return "Stejný průměr. Nikdo nic nebere."
        default: return ""
        }
    }
}

/// Type-erased ButtonStyle (přepínání stylu podle stavu).
struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: ButtonStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

/// Konfety: jen accent a textPrimary, ~2,5 s, pak zmizí.
struct Confetti: View {
    private struct Piece {
        let x: Double, delay: Double, speed: Double, spin: Double, size: CGSize, accent: Bool, drift: Double
    }

    @State private var start = Date()
    private let pieces: [Piece] = (0..<90).map { _ in
        Piece(x: .random(in: 0...1), delay: .random(in: 0...0.6), speed: .random(in: 0.7...1.3),
              spin: .random(in: -6...6), size: CGSize(width: .random(in: 5...9), height: .random(in: 9...14)),
              accent: Bool.random(), drift: .random(in: -40...40))
    }

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSince(start)
                guard t < 3.2 else { return }
                for p in pieces {
                    let lt = t - p.delay
                    guard lt > 0 else { continue }
                    let y = -20 + lt * lt * 260 * p.speed + lt * 120
                    guard y < size.height + 20 else { continue }
                    let x = p.x * size.width + sin(lt * 3) * p.drift
                    var c = ctx
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .radians(lt * p.spin))
                    c.opacity = max(0, 1 - max(0, t - 2.4) / 0.8)
                    c.fill(Path(CGRect(origin: CGPoint(x: -p.size.width / 2, y: -p.size.height / 2), size: p.size)),
                           with: .color(p.accent ? Color.app.accent : Color.app.textPrimary))
                }
            }
        }
        .onAppear { start = .now }
    }
}
