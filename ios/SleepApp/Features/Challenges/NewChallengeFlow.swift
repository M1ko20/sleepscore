import SwiftUI

/// Nová výzva: typ → soupeři → délka → sázka (+ cíl) → odeslat.
struct NewChallengeFlow: View {
    var prefill: ProfileLite?
    /// true = Odplata po prohře, false = Vyzvat z profilu.
    var rematch = true

    @Environment(Session.self) private var session
    @Environment(ChallengeStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private enum Step: Int { case type, opponents, duration, stake }

    @State private var step: Step = .type
    @State private var type: ChallengeType = .duel
    @State private var picked: Set<UUID> = []
    @State private var days = 7
    @State private var customDays = ""
    @State private var stake = ""
    @State private var target = 80
    @State private var busy = false
    @State private var error: String?

    init(prefill: ProfileLite? = nil, rematch: Bool = true) {
        self.prefill = prefill
        self.rematch = rematch
        if let prefill {
            _picked = State(initialValue: [prefill.id])
            _step = State(initialValue: .duration)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(stepTitle).font(Font.app.title).foregroundStyle(Color.app.textPrimary)
                    switch step {
                    case .type: typeStep
                    case .opponents: opponentsStep
                    case .duration: durationStep
                    case .stake: stakeStep
                    }
                    if let error { Text(error).font(Font.app.caption).foregroundStyle(Color.app.textPrimary) }
                }
                .padding(Metrics.screenPadding)
            }
            .background(Color.app.bg)
            .safeAreaInset(edge: .bottom) {
                Button(primaryTitle, action: next)
                    .buttonStyle(.primary)
                    .disabled(!canContinue || busy)
                    .padding(Metrics.screenPadding)
                    .background(Color.app.bg)
            }
            .navigationTitle("Nová výzva")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if step == .type || (prefill != nil && step == .duration) {
                        Button("Zrušit") { dismiss() }
                    } else {
                        Button("Zpět") { back() }
                    }
                }
            }
        }
        .presentationBackground(Color.app.bg)
    }

    private var stepTitle: String {
        switch step {
        case .type: "Jaká výzva"
        case .opponents: type == .duel ? "Koho vyzveš" : "Koho pozveš"
        case .duration: prefill.map { "\(rematch ? "Odplata" : "Výzva"): \($0.displayName)" } ?? "Na jak dlouho"
        case .stake: type == .teamGoal ? "Cíl a sázka" : "O co se hraje"
        }
    }

    private var primaryTitle: String {
        if step == .stake { return busy ? "Posílám…" : "Odeslat" }
        return "Pokračovat"
    }

    private var effectiveDays: Int? {
        if days > 0 { return days }
        return Int(customDays).flatMap { $0 >= 7 && $0 <= 365 ? $0 : nil }
    }

    private var canContinue: Bool {
        switch step {
        case .type: true
        case .opponents: type == .duel ? picked.count == 1 : picked.count >= 2
        case .duration: effectiveDays != nil
        case .stake: stake.count <= 200
        }
    }

    // MARK: Kroky

    private var typeStep: some View {
        VStack(spacing: 8) {
            option(.duel, "1 na 1. Vyšší průměr bere ovečku.")
            option(.freeForAll, "Vítěz bere vše: ovečky i sázky všech. Aspoň 3 hráči.")
            option(.teamGoal, "Skupina proti cíli. Bez oveček, do bilance se počítá.")
        }
    }

    private func option(_ t: ChallengeType, _ detail: String) -> some View {
        Button {
            if t != type { picked = [] }
            type = t
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(t.label).font(Font.app.body.weight(.semibold)).foregroundStyle(Color.app.textPrimary)
                Text(detail).captionStyle().multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.app.surfaceRaised, in: RoundedRectangle(cornerRadius: Metrics.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: Metrics.controlRadius)
                .strokeBorder(type == t ? Color.app.accent : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(type == t ? .isSelected : [])
    }

    @ViewBuilder private var opponentsStep: some View {
        if store.friends.isEmpty {
            Text("Zatím nemáš kamarády. Pošli pozvánku.").captionStyle()
        }
        VStack(spacing: 0) {
            ForEach(store.friends) { f in
                let on = picked.contains(f.id)
                Button {
                    if type == .duel { picked = [f.id] }
                    else if on { picked.remove(f.id) } else { picked.insert(f.id) }
                } label: {
                    HStack(spacing: 12) {
                        Avatar(profile: f, size: 36)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(f.displayName).font(Font.app.body.weight(.semibold)).foregroundStyle(Color.app.textPrimary)
                            Text("@\(f.username)").captionStyle()
                        }
                        Spacer()
                        Image(systemName: on ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(on ? Color.app.accent : Color.app.textTertiary)
                    }
                    .frame(minHeight: 60)
                    .contentShape(Rectangle())
                    .overlay(alignment: .bottom) { Rectangle().fill(Color.app.hairline).frame(height: 1) }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        if type != .duel {
            Text("Vyber aspoň 2. Spustíš, až přijmou aspoň 2.").captionStyle()
        }
    }

    private var durationStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach([7, 14, 30], id: \.self) { d in chip("\(d) dní", selected: days == d) { days = d } }
                chip("Vlastní", selected: days == 0) { days = 0 }
            }
            if days == 0 {
                TextField("", text: $customDays, prompt: Text("Počet dní (min. 7)").foregroundStyle(Color.app.textTertiary))
                    .textFieldStyle(AppTextFieldStyle())
                    .keyboardType(.numberPad)
            }
            Text(type == .duel ? "Startuje den po přijetí. Rozhoduje průměrné sleep score."
                               : "Startuje den po spuštění. Rozhoduje průměrné sleep score.")
                .captionStyle()
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Font.app.caption.weight(.semibold))
                .foregroundStyle(Color.app.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color.app.surfaceRaised, in: RoundedRectangle(cornerRadius: Metrics.controlRadius))
                .overlay(RoundedRectangle(cornerRadius: Metrics.controlRadius)
                    .strokeBorder(selected ? Color.app.accent : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var stakeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            if type == .teamGoal {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Cílový průměr").statLabel()
                    HStack {
                        Text("\(target)").font(Font.app.scoreL).foregroundStyle(Color.app.textPrimary)
                        Spacer()
                        Stepper("", value: $target, in: 50...100).labelsHidden()
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Sázka").statLabel()
                TextField("", text: $stake, prompt: Text("prohraný platí pivo").foregroundStyle(Color.app.textTertiary))
                    .textFieldStyle(AppTextFieldStyle())
                Text(type == .teamGoal ? "Nepovinná. U společného cíle se dluhy nevedou."
                                       : "Nepovinná. Appka povede, kdo komu dluží.")
                    .captionStyle()
            }
        }
    }

    // MARK: Navigace

    private func back() {
        error = nil
        step = Step(rawValue: step.rawValue - 1) ?? .type
    }

    private func next() {
        error = nil
        guard step == .stake else {
            step = Step(rawValue: step.rawValue + 1)!
            return
        }
        guard let me = session.profile?.id, let d = effectiveDays else { return }
        busy = true
        let s = stake.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            defer { busy = false }
            do {
                try await store.create(type: prefill == nil ? type : .duel, opponents: Array(picked), days: d,
                                       stake: s.isEmpty ? nil : s, target: type == .teamGoal ? target : nil, me: me)
                dismiss()
            } catch {
                self.error = serverMessage(error)
            }
        }
    }
}
