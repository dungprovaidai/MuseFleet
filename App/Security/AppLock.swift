import Foundation
import LocalAuthentication
import Observation
import Security

enum KeychainLock {
    private static let service = "com.dungprovaidai.musefleet.lock"
    static func enabled() -> Bool {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return false }
        // Fail closed when the Keychain is temporarily inaccessible.
        guard status == errSecSuccess, let data = result as? Data else { return true }
        return data == Data([1])
    }

    static func setEnabled(_ enabled: Bool) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: Data([enabled ? 1 : 0]),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemUpdate(base as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let added = SecItemAdd(base.merging(attributes) { _, new in new } as CFDictionary, nil)
            guard added == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(added)) }
        } else if status != errSecSuccess {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    private static var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "app-lock-enabled"]
    }
}

@MainActor @Observable
final class AppLock {
    private(set) var isLocked = true
    private(set) var isAuthenticating = false
    var errorMessage: String?
    @ObservationIgnored private var context: LAContext?
    @ObservationIgnored private var lockGeneration = 0

    func lock(enabled: Bool) {
        lockGeneration += 1
        context?.invalidate()
        context = nil
        isLocked = enabled
    }

    func unlock(enabled: Bool) async {
        guard enabled else { isLocked = false; return }
        guard !isAuthenticating else { return }
        isAuthenticating = true
        errorMessage = nil
        defer { isAuthenticating = false; context = nil }
        let authentication = LAContext()
        let generation = lockGeneration
        authentication.localizedCancelTitle = "Keep locked"
        context = authentication
        do {
            let success = try await authentication.evaluatePolicy(.deviceOwnerAuthentication,
                localizedReason: "Unlock your Muse accounts and conversations.")
            if success && generation == lockGeneration { isLocked = false }
        } catch {
            errorMessage = "MuseFleet is locked. Authenticate with biometrics or your device passcode to continue."
        }
    }

    func confirmSettingChange(enabled: Bool, store: FleetStore) async {
        let authentication = LAContext()
        let generation = lockGeneration
        do {
            let success = try await authentication.evaluatePolicy(.deviceOwnerAuthentication,
                localizedReason: enabled ? "Protect your Muse accounts with app lock." : "Turn off MuseFleet app lock.")
            guard success, generation == lockGeneration else { throw LAError(.authenticationFailed) }
            try KeychainLock.setEnabled(enabled)
            store.settings.appLockEnabled = enabled
            store.save()
        } catch {
            store.settings.appLockEnabled = KeychainLock.enabled()
            store.save()
            errorMessage = "App lock settings were not changed. Set up a device passcode or biometrics and try again."
        }
    }
}
