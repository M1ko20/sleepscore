import Foundation
import Observation
import Supabase
import os

let log = Logger(subsystem: "cz.mikolas.sleepscore", category: "app")

/// Stav přihlášení a vlastního profilu.
@MainActor
@Observable
final class Session {
    enum State: Equatable {
        case loading
        case signedOut
        /// Přihlášen, ale bez profilu (ještě neuplatnil pozvánku) – onboarding.
        case needsProfile(userID: UUID)
        case ready(Profile)
        /// Přihlášen, ale profil se nepodařilo načíst (síť) – nehádat, nabídnout znovu.
        case offline
    }

    private(set) var state: State = .loading

    /// Kód zadaný před přihlášením. Přežije restart appky.
    var pendingInviteCode: String? {
        didSet { UserDefaults.standard.set(pendingInviteCode, forKey: "pendingInviteCode") }
    }

    private var listenTask: Task<Void, Never>?
    #if DEBUG
    private static var debugLoginDone = false
    #endif

    init() {
        pendingInviteCode = UserDefaults.standard.string(forKey: "pendingInviteCode")
    }

    var profile: Profile? {
        if case .ready(let p) = state { return p }
        return nil
    }

    func start() {
        guard listenTask == nil else { return }
        #if DEBUG
        // Screenshoty ze simulátoru: `simctl launch … -debugLogin email:heslo`
        let args = ProcessInfo.processInfo.arguments
        if !Self.debugLoginDone, let i = args.firstIndex(of: "-debugLogin"), i + 1 < args.count {
            Self.debugLoginDone = true   // jen jednou – jinak se start() volá dokola
            let parts = args[i + 1].split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                listenTask = Task {
                    try? await Backend.client.auth.signOut()
                    do { try await Backend.client.auth.signIn(email: parts[0], password: parts[1]) }
                    catch { log.error("debugLogin failed: \(String(describing: error))") }
                    self.listenTask = nil
                    self.start()
                }
                return
            }
        }
        #endif
        listenTask = Task { [weak self] in
            for await (event, session) in Backend.client.auth.authStateChanges {
                guard let self else { return }
                log.info("auth event \(String(describing: event)) session=\(session != nil) expired=\(session?.isExpired ?? false)")
                switch event {
                case .initialSession, .signedIn, .signedOut, .userDeleted:
                    await self.update(for: session)
                default:
                    break
                }
            }
        }
    }

    func signIn(email: String, password: String) async throws {
        try await Backend.client.auth.signIn(email: email, password: password)
    }

    func signOut() async {
        HealthSync.shared.stopObserving()
        HealthSync.shared.resetAnchor()
        try? await Backend.client.auth.signOut()
    }

    /// Onboarding skončil – přepne do appky.
    func finishOnboarding(with profile: Profile) {
        pendingInviteCode = nil
        state = .ready(profile)
    }

    /// Znovu načte stav po chybě sítě.
    func retry() async {
        state = .loading
        await update(for: try? await Backend.client.auth.session)
    }

    func reloadProfile() async {
        guard case .ready(let current) = state,
              let fresh = try? await API.profile(id: current.id) else { return }
        state = .ready(fresh)
    }

    private func update(for session: Supabase.Session?) async {
        // Prošlá session nevadí – SDK token obnoví při dalším požadavku; když to nejde, přijde signedOut.
        guard let session else {
            state = .signedOut
            return
        }
        let userID = session.user.id
        do {
            if let profile = try await withTimeout(seconds: 15, { try await API.profile(id: userID) }) {
                state = .ready(profile)
            } else {
                state = .needsProfile(userID: userID)
            }
        } catch {
            log.error("profile load failed: \(String(describing: error))")
            state = .offline
        }
    }
}

struct TimeoutError: Error {}

/// Pojistka nad timeoutem URLSession (retry v SDK ho umí natáhnout).
func withTimeout<T: Sendable>(seconds: Double, _ work: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await work() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw TimeoutError()
        }
        defer { group.cancelAll() }
        return try await group.next()!
    }
}
