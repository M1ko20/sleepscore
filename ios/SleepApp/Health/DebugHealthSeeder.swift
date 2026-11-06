#if DEBUG
import Foundation
import HealthKit

/// Jen DEBUG: zapíše do Apple Health v simulátoru realistickou noc končící dnes ráno.
/// Zdroj = tahle appka (ne ruční záznam), takže projde filtrem jako data ze zařízení.
enum DebugHealthSeeder {
    static func insertNight(daysAgo: Int = 0) async throws {
        let store = HKHealthStore()
        let cal = Calendar.current
        let wakeDay = cal.date(byAdding: .day, value: -daysAgo, to: cal.startOfDay(for: .now))!
        var rng = SystemRandomNumberGenerator()
        let bed = cal.date(byAdding: .minute, value: -Int.random(in: 40...90, using: &rng), to: wakeDay)!   // 22:30–23:20
        let end = cal.date(byAdding: .minute, value: Int.random(in: 380...470, using: &rng), to: bed)!

        var samples: [HKSample] = []
        var t = bed
        var cycle = 0
        let meta: [String: Any] = [HKMetadataKeyWasUserEntered: false]
        func add(_ v: HKCategoryValueSleepAnalysis, _ minutes: Double) {
            guard minutes >= 1, t < end else { return }
            let e = min(end, t.addingTimeInterval(minutes * 60))
            samples.append(HKCategorySample(type: HKCategoryType(.sleepAnalysis), value: v.rawValue, start: t, end: e, metadata: meta))
            t = e
        }
        while t < end {
            let frac = t.timeIntervalSince(bed) / end.timeIntervalSince(bed)
            if cycle > 0, Bool.random() { add(.awake, .random(in: 1.5...5)) }
            add(.asleepCore, .random(in: 18...28))
            add(.asleepDeep, max(0, .random(in: 20...40) * (1 - frac * 1.3)))
            add(.asleepCore, .random(in: 18...28))
            add(.asleepREM, .random(in: 8...15) + frac * .random(in: 10...25))
            cycle += 1
        }

        let unit = HKUnit.count().unitDivided(by: .minute())
        let base = Double.random(in: 50...57)
        var x = bed
        while x < end {
            let bpm = base + .random(in: -3...3)
            samples.append(HKQuantitySample(type: HKQuantityType(.heartRate),
                                            quantity: HKQuantity(unit: unit, doubleValue: bpm.rounded()),
                                            start: x, end: x, metadata: meta))
            x = x.addingTimeInterval(120)
        }
        try await store.save(samples)
    }
}
#endif
