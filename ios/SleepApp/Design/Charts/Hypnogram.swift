import SwiftUI

extension SleepStage {
    var color: Color {
        switch self {
        case .awake: Color.app.stageAwake
        case .rem: Color.app.stageREM
        case .core, .asleep: Color.app.stageCore
        case .deep: Color.app.stageDeep
        }
    }
}

/// Malý hypnogram na kartě ve feedu (výška 36 pt, bez popisků).
struct MiniHypnogram: View {
    let segments: [Segment]
    let start: Date
    let end: Date

    var body: some View {
        Canvas { ctx, size in
            let span = end.timeIntervalSince(start)
            guard span > 0 else { return }
            let rowH = size.height / 4
            for seg in segments {
                let x0 = max(0, seg.start.timeIntervalSince(start) / span) * size.width
                let x1 = min(1, seg.end.timeIntervalSince(start) / span) * size.width
                let rect = CGRect(x: x0, y: CGFloat(seg.stage.row) * rowH + 1,
                                  width: max(1, x1 - x0), height: rowH - 2)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(seg.stage.color))
            }
        }
        .frame(height: 36)
        .accessibilityHidden(true)
    }
}

/// Hypnogram v detailu: řádek na fázi, tep jako tenká linka, dotyk a tah = čas + fáze + tep.
struct Hypnogram: View {
    let segments: [Segment]
    let start: Date
    let end: Date
    var heartRate: [HeartRatePoint] = []
    var timeZone: TimeZone = .current

    @State private var scrub: Date?

    private let labelWidth: CGFloat = 52
    private let rowHeight: CGFloat = 26
    private let rows: [SleepStage] = [.awake, .rem, .core, .deep]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            readout.frame(height: 18)
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows, id: \.self) { stage in
                        Text(stage.label).statLabel()
                            .frame(height: rowHeight, alignment: .center)
                    }
                }
                .frame(width: labelWidth, alignment: .leading)

                GeometryReader { geo in
                    chart(size: geo.size)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                let f = min(max(v.location.x / geo.size.width, 0), 1)
                                scrub = start.addingTimeInterval(end.timeIntervalSince(start) * f)
                            }
                            .onEnded { _ in scrub = nil })
                }
                .frame(height: rowHeight * 4)

                if let range = hrRange {
                    VStack(alignment: .trailing) {
                        Text("\(Int(range.upperBound))")
                        Spacer()
                        Text("\(Int(range.lowerBound))")
                    }
                    .font(Font.app.label).monospacedDigit()
                    .foregroundStyle(Color.app.textTertiary)
                    .frame(width: 24, height: rowHeight * 4, alignment: .trailing)
                }
            }
            axis.padding(.leading, labelWidth).padding(.trailing, hrRange == nil ? 0 : 24)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var hrRange: ClosedRange<Double>? {
        let values = smoothedHR.map(\.bpm)
        guard let lo = values.min(), let hi = values.max(), hi > lo else { return nil }
        return lo.rounded(.down)...hi.rounded(.up)
    }

    /// Klouzavý průměr ±5 min – surový tep po 1–2 min je na čtení moc roztřesený.
    private var smoothedHR: [(t: Date, bpm: Double)] {
        let pts = heartRate.sorted { $0.t < $1.t }
        var out: [(t: Date, bpm: Double)] = []
        var lo = 0, hi = 0, sum = 0.0
        for p in pts {
            while hi < pts.count, pts[hi].t.timeIntervalSince(p.t) <= 300 { sum += pts[hi].bpm; hi += 1 }
            while p.t.timeIntervalSince(pts[lo].t) > 300 { sum -= pts[lo].bpm; lo += 1 }
            out.append((p.t, sum / Double(hi - lo)))
        }
        return out
    }

    private func chart(size: CGSize) -> some View {
        Canvas { ctx, size in
            let span = end.timeIntervalSince(start)
            guard span > 0 else { return }
            func x(_ d: Date) -> CGFloat { CGFloat(d.timeIntervalSince(start) / span) * size.width }

            for seg in segments {
                let x0 = max(0, x(seg.start)), x1 = min(size.width, x(seg.end))
                let rect = CGRect(x: x0, y: CGFloat(seg.stage.row) * rowHeight + 3,
                                  width: max(1, x1 - x0), height: rowHeight - 6)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(seg.stage.color))
            }

            if let range = hrRange {
                var path = Path()
                for (i, p) in smoothedHR.enumerated() where p.t >= start && p.t <= end {
                    let y = size.height - CGFloat((p.bpm - range.lowerBound) / (range.upperBound - range.lowerBound)) * size.height
                    let pt = CGPoint(x: x(p.t), y: y)
                    if i == 0 || path.isEmpty { path.move(to: pt) } else { path.addLine(to: pt) }
                }
                ctx.stroke(path, with: .color(Color.app.heartRate), lineWidth: 1)
            }

            if let scrub {
                let sx = x(scrub)
                ctx.fill(Path(CGRect(x: sx - 0.5, y: 0, width: 1, height: size.height)),
                         with: .color(Color.app.textPrimary))
            }
        }
    }

    @ViewBuilder private var readout: some View {
        if let scrub {
            let stage = segments.first { $0.start <= scrub && scrub < $0.end }?.stage
            let bpm = smoothedHR.min { abs($0.t.timeIntervalSince(scrub)) < abs($1.t.timeIntervalSince(scrub)) }?.bpm
            HStack(spacing: 12) {
                Text(Fmt.time(scrub, in: timeZone)).font(Font.app.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color.app.textPrimary)
                if let stage { Text(stage.label).statLabel() }
                if let bpm { Text("\(Int(bpm)) tepů").captionStyle() }
            }
            .padding(.leading, labelWidth)
        } else {
            Color.clear
        }
    }

    /// Začátek, konec a celé hodiny (bez kolizí s krajními popisky).
    private var axis: some View {
        GeometryReader { geo in
            let span = end.timeIntervalSince(start)
            let ticks = hourTicks(width: geo.size.width)
            let edge: CGFloat = 52   // místo pro krajní popisek „23:24“
            ZStack(alignment: .topLeading) {
                tick(start, at: 0, align: .leading)
                ForEach(ticks, id: \.self) { t in
                    let x = geo.size.width * t.timeIntervalSince(start) / span
                    if x > edge && x < geo.size.width - edge {
                        tick(t, at: x, align: .center)
                    }
                }
                tick(end, at: geo.size.width, align: .trailing)
            }
        }
        .frame(height: 14)
    }

    private func tick(_ date: Date, at x: CGFloat, align: HorizontalAlignment) -> some View {
        Text(Fmt.time(date, in: timeZone))
            .font(Font.app.label).monospacedDigit()
            .foregroundStyle(Color.app.textTertiary)
            .fixedSize()
            .alignmentGuide(.leading) { d in
                switch align {
                case .leading: -x
                case .trailing: -(x - d.width)
                default: -(x - d.width / 2)
                }
            }
    }

    private func hourTicks(width: CGFloat) -> [Date] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        guard var t = cal.nextDate(after: start, matching: DateComponents(minute: 0, second: 0), matchingPolicy: .nextTime)
        else { return [] }
        var out: [Date] = []
        let hours = end.timeIntervalSince(start) / 3600
        let step = width / hours < 40 ? 2 : 1   // popisek ~34 pt
        while t < end {
            if cal.component(.hour, from: t) % step == 0 { out.append(t) }
            t = t.addingTimeInterval(3600)
        }
        return out
    }

    private var accessibilitySummary: String {
        let total = segments.filter { $0.stage != .awake }.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) } / 60
        let deep = segments.filter { $0.stage == .deep }.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) } / 60
        return "Spánek \(Fmt.duration(minutes: Int(total))), z toho hluboký \(Fmt.duration(minutes: Int(deep)))"
    }
}
