import HealthKit
import HealthKitUI
import SwiftUI

extension View {
    /// Žádost o přístup ke Zdraví přes SwiftUI (`healthDataAccessRequest`). Systémové okno
    /// ukáže SwiftUI nad aktuální obrazovkou, když se `trigger` změní. Když už se uživatel
    /// vyjádřil, okno se neukáže a hned se zavolá `onFinish`.
    func healthAccessRequest<T: Equatable>(trigger: T, onFinish: @escaping @MainActor () -> Void = {}) -> some View {
        let health = HealthSync.shared
        return healthDataAccessRequest(
            store: health.store,
            shareTypes: health.shareTypes,
            readTypes: health.readTypes,
            trigger: trigger
        ) { result in
            Task { @MainActor in
                health.authorizationFinished(result)
                onFinish()
            }
        }
    }
}
