import Foundation
import HealthKit
import Observation
import Supabase

/// Čtení spánku a tepu z Apple Health a odeslání na `ingest-sleep`.
///
/// Šetří cally (Free tier): anchored query zjistí, jestli přibyly nové spánkové vzorky;
/// když ne, nic se neposílá. Když ano, pošle se okno 3 dnů (server si vybere hlavní spánek
/// a zpětné dohrání přepíše 0 ve výzvách). Tep jen v časech spánku.
@MainActor
@Observable
final class HealthSync {
    static let shared = HealthSync()

    enum Status: Equatable {
        case idle
        case syncing
        case done(Date, nights: Int)
        case nothingNew(Date)
        case failed(String)
    }

    private(set) var status: Status = .idle
    /// Zavolá se po úspěšném nahrání (feed se obnoví).
    var onUploaded: (() -> Void)?

    private let store = HKHealthStore()
    private let sleepType = HKCategoryType(.sleepAnalysis)
    private let hrType = HKQuantityType(.heartRate)
    private var observer: HKObserverQuery?
    /// Přišel požadavek během běžící synchronizace → po dokončení ještě jednou
    /// (`true` = aspoň jeden z nich byl ruční `force`).
    private var rerun: Bool?
    private static let anchorKey = "healthSleepAnchor"
    private static let windowDays = 3

    /// Začátek okna: poledne dne před nejstarším dnem okna. Hranice „teď − 3 dny“ by mohla
    /// spadnout doprostřed noci a server by dostal jen její konec (#32).
    static func windowStart(now: Date = .now, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        let day = calendar.date(byAdding: .day, value: -(windowDays + 1), to: today)!
        return calendar.date(byAdding: .hour, value: 12, to: day)!
    }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // MARK: Oprávnění

    func requestAuthorization() async throws {
        guard isAvailable else { return }
        var share: Set<HKSampleType> = []
        #if DEBUG
        share = [sleepType, hrType]   // jen kvůli testovacím nocím v simulátoru
        #endif
        try await store.requestAuthorization(toShare: share, read: [sleepType, hrType])
    }

    /// Je ve Zdraví za posledních `days` dní aspoň jeden spánkový záznam?
    /// Při odmítnutém přístupu iOS vrací prázdno (neřekne, že je zakázaný) → false.
    func hasRecentSleep(days: Int = 14) async -> Bool {
        guard isAvailable else { return false }
        let start = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: 1, sortDescriptors: nil) { _, samples, _ in
                cont.resume(returning: !(samples ?? []).isEmpty)
            }
            store.execute(q)
        }
    }

    // MARK: Pozadí

    /// Sledování zapnuté (přihlášený člen) – při startu appky se hned obnoví v `AppDelegate`.
    private static let observingKey = "healthObserving"
    static var shouldResumeObserving: Bool { UserDefaults.standard.bool(forKey: observingKey) }

    /// Spustí observer + background delivery. Volat po přihlášení (s profilem) a při každém
    /// startu appky v `didFinishLaunching` – když iOS appku probudí na pozadí kvůli nové noci,
    /// observer musí existovat dřív, než se načte session a UI, jinak se aktualizace ztratí.
    func startObserving() {
        UserDefaults.standard.set(true, forKey: Self.observingKey)
        guard isAvailable, observer == nil else { return }
        let query = HKObserverQuery(sampleType: sleepType, predicate: nil) { _, completion, error in
            guard error == nil else { completion(); return }
            Task { @MainActor in
                await HealthSync.shared.sync()
                completion()
            }
        }
        observer = query
        store.execute(query)
        store.enableBackgroundDelivery(for: sleepType, frequency: .hourly) { ok, error in
            if !ok { log.error("background delivery: \(String(describing: error))") }
        }
    }

    func stopObserving() {
        UserDefaults.standard.removeObject(forKey: Self.observingKey)
        if let observer { store.stop(observer) }
        observer = nil
        store.disableAllBackgroundDelivery { _, _ in }
    }

    /// Při odhlášení – další účet na stejném telefonu musí poslat vše znovu.
    func resetAnchor() {
        UserDefaults.standard.removeObject(forKey: Self.anchorKey)
    }

    // MARK: Synchronizace

    /// - Parameter force: poslat okno i bez nových vzorků (ruční „Synchronizovat“).
    func sync(force: Bool = false) async {
        guard isAvailable else { return }
        guard status != .syncing else { rerun = (rerun ?? false) || force; return }
        status = .syncing
        defer {
            if let again = rerun {
                rerun = nil
                Task { await self.sync(force: again) }
            }
        }
        do {
            let (hasNew, newAnchor) = try await newSleepSamples()
            log.info("health sync: new sleep samples=\(hasNew) force=\(force)")
            guard hasNew || force else {
                status = .nothingNew(.now)
                return
            }
            let (nights, failed) = try await upload()
            // Noc, kterou server neuložil, se zkusí znovu: bez uloženého anchoru se příště
            // vzorky hlásí jako nové a okno se pošle znovu.
            if let newAnchor, !failed { saveAnchor(newAnchor) }
            status = failed ? .failed("Některou noc se nepodařilo uložit. Zkusím to znovu.") : .done(.now, nights: nights)
            onUploaded?()
        } catch {
            log.error("health sync failed: \(String(describing: error))")
            status = .failed("Synchronizace selhala.")
        }
    }

    /// Přibyly od posledně spánkové vzorky ze zařízení?
    private func newSleepSamples() async throws -> (Bool, HKQueryAnchor?) {
        let anchor = loadAnchor()
        let since = Self.windowStart()
        let predicate = HKQuery.predicateForSamples(withStart: since, end: nil)
        let descriptor = HKAnchoredObjectQueryDescriptor(
            predicates: [.categorySample(type: sleepType, predicate: predicate)],
            anchor: anchor
        )
        let result = try await descriptor.result(for: store)
        let fresh = result.addedSamples.contains { !$0.isUserEntered }
        return (fresh || !result.deletedObjects.isEmpty, result.newAnchor)
    }

    /// Vrací počet uložených nocí a jestli některá na serveru selhala.
    private func upload() async throws -> (Int, Bool) {
        let samples = try await sleepSamples()
        log.info("health upload: \(samples.count) sleep samples")
        guard !samples.isEmpty else { return (0, false) }
        let windows = Self.mergedWindows(samples.map { ($0.startDate, $0.endDate) })
        let hr = try await heartRate(in: windows)

        let payload = IngestPayload(
            timezone: TimeZone.current.identifier,
            samples: samples.compactMap(IngestPayload.Sample.init),
            heart_rate: hr
        )
        let response: IngestResponse = try await Backend.client.functions.invoke(
            "ingest-sleep", options: FunctionInvokeOptions(body: payload)
        )
        log.info("ingest: \(response.nights.map { "\($0.date)=\($0.score.map(String.init) ?? "-") \($0.status)" })")
        let saved = response.nights.filter { $0.status == "created" || $0.status == "updated" }.count
        return (saved, response.nights.contains { $0.status == "error" })
    }

    private func sleepSamples() async throws -> [HKCategorySample] {
        let since = Self.windowStart()
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: sleepType, predicate: HKQuery.predicateForSamples(withStart: since, end: nil))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return try await descriptor.result(for: store).filter { !$0.isUserEntered }
    }

    private func heartRate(in windows: [(Date, Date)]) async throws -> [IngestPayload.HeartRate] {
        guard !windows.isEmpty else { return [] }
        let predicates = windows.map { HKQuery.predicateForSamples(withStart: $0.0, end: $0.1) }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: hrType, predicate: NSCompoundPredicate(orPredicateWithSubpredicates: predicates))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let unit = HKUnit.count().unitDivided(by: .minute())
        return try await descriptor.result(for: store)
            .filter { !$0.isUserEntered }
            .map { .init(t: $0.startDate, bpm: $0.quantity.doubleValue(for: unit).rounded()) }
    }

    /// Sloučí překrývající se úseky (mezera ≤ 60 min) do oken pro dotaz na tep.
    static func mergedWindows(_ ranges: [(Date, Date)]) -> [(Date, Date)] {
        var out: [(Date, Date)] = []
        for r in ranges.sorted(by: { $0.0 < $1.0 }) {
            if let last = out.last, r.0.timeIntervalSince(last.1) <= 3600 {
                out[out.count - 1].1 = max(last.1, r.1)
            } else {
                out.append(r)
            }
        }
        return out
    }

    // MARK: Anchor

    private func loadAnchor() -> HKQueryAnchor? {
        guard let data = UserDefaults.standard.data(forKey: Self.anchorKey) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private func saveAnchor(_ anchor: HKQueryAnchor) {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true) {
            UserDefaults.standard.set(data, forKey: Self.anchorKey)
        }
    }
}

private extension HKSample {
    var isUserEntered: Bool { (metadata?[HKMetadataKeyWasUserEntered] as? Bool) == true }
}

// MARK: Formát pro ingest-sleep

struct IngestPayload: Encodable, Sendable {
    struct Sample: Encodable, Sendable {
        let uuid: String
        let start: String
        let end: String
        let stage: String
        let source: String
        let userEntered: Bool

        init?(_ s: HKCategorySample) {
            guard let stage = Self.stage(s.value) else { return nil }   // inBed se neposílá
            uuid = s.uuid.uuidString
            start = s.startDate.ISO8601Format()
            end = s.endDate.ISO8601Format()
            self.stage = stage
            source = s.sourceRevision.source.name
            userEntered = false
        }

        static func stage(_ raw: Int) -> String? {
            switch HKCategoryValueSleepAnalysis(rawValue: raw) {
            case .asleepCore: "core"
            case .asleepDeep: "deep"
            case .asleepREM: "rem"
            case .awake: "awake"
            case .asleepUnspecified: "asleep"
            default: nil
            }
        }
    }

    struct HeartRate: Encodable, Sendable {
        let t: String
        let bpm: Double
        init(t: Date, bpm: Double) { self.t = t.ISO8601Format(); self.bpm = bpm }
    }

    let timezone: String
    let samples: [Sample]
    let heart_rate: [HeartRate]
}

struct IngestResponse: Decodable, Sendable {
    struct NightResult: Decodable, Sendable {
        let date: String
        let score: Int?
        let status: String
    }
    let nights: [NightResult]
}
