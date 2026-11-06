import SwiftUI

/// Karta výsledku výzvy ve feedu (design.md → Karta výsledku výzvy).
struct ChallengeResultCard: View {
    let post: ChallengeResultPost
    let me: UUID?

    private var c: Challenge { post.challenge }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Výzva · \(Fmt.days(c.durationDays))").statLabel()
                Spacer()
                Text(Fmt.postStamp(post.createdAt)).font(Font.app.caption.monospacedDigit())
                    .foregroundStyle(Color.app.textSecondary)
            }

            if c.type == .teamGoal {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Fmt.avg(c.teamAverage)).font(Font.app.scoreL).foregroundStyle(Color.app.textPrimary)
                    Text("/ \(c.targetScore ?? 0)").font(Font.app.stat).foregroundStyle(Color.app.textSecondary)
                }
                Text(c.accepted.map { ChallengeCopy.name($0.profile, me: me) }.joined(separator: ", ")).captionStyle()
            } else {
                let top = Array(c.standings.prefix(c.type == .duel ? 2 : 3))
                HStack(alignment: .top, spacing: 16) {
                    ForEach(Array(top.enumerated()), id: \.element.id) { i, p in
                        let win = p.result == .win || p.result == .draw
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ChallengeCopy.name(p.profile, me: me).uppercased())
                                .font(Font.app.label).tracking(0.6).foregroundStyle(Color.app.textSecondary)
                                .lineLimit(1)
                            Text(Fmt.avg(p.finalAvg)).font(Font.app.scoreL)
                                .foregroundStyle(win ? Color.app.textPrimary : Color.app.textSecondary)
                            Text("vyhrané \(Fmt.days(p.daysWon ?? 0))").captionStyle()
                        }
                        if i < top.count - 1 && c.type == .duel {
                            Text(":").font(Font.app.scoreL).foregroundStyle(Color.app.textTertiary).padding(.top, 14)
                        }
                    }
                    Spacer(minLength: 0)
                }
                if c.type == .freeForAll && c.accepted.count > 3 {
                    Text("+\(c.accepted.count - 3) dalších").captionStyle()
                }
            }

            Text(ChallengeCopy.resultLine(c, me: me))
                .font(Font.app.body).foregroundStyle(Color.app.textPrimary)
        }
        .cardStyle()
    }
}
