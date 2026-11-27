import XCTest
@testable import MuseFleet

@MainActor
final class AppLockTests: XCTestCase {
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
