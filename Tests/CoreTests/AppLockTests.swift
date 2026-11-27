import XCTest
import Security
@testable import MuseFleet

@MainActor
final class AppLockTests: XCTestCase {
    func testHostedApplicationCanAccessAnIsolatedKeychainItem() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.dungprovaidai.musefleet.tests." + UUID().uuidString,
            kSecAttrAccount as String: "fixture"
        ]
        XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, nil), errSecItemNotFound)
        let bytes = Data([0, 1])
        let item = query.merging([kSecValueData as String: bytes]) { _, new in new }
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            XCTFail("Hosted app cannot access Keychain; OSStatus \(status). Check simulator signing.")
            return
        }
        defer { SecItemDelete(query as CFDictionary) }
        let lookup = query.merging([kSecReturnData as String: true]) { _, new in new }
        var result: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(lookup as CFDictionary, &result), errSecSuccess)
        XCTAssertEqual(result as? Data, bytes)
    }

    func testAlreadyUnlockedActivationDoesNotStartDeviceAuthentication() async {
        let lock = AppLock()
        await lock.unlock(enabled: false)
        XCTAssertFalse(lock.isLocked)
        await lock.unlock(enabled: true)
        XCTAssertFalse(lock.isLocked)
        XCTAssertFalse(lock.isAuthenticating)
        XCTAssertNil(lock.errorMessage)
    }

    func testLockImmediatelyClosesAnUnlockedSession() async {
        let lock = AppLock()
        await lock.unlock(enabled: false)
        lock.lock(enabled: true)
        XCTAssertTrue(lock.isLocked)
    }
}
