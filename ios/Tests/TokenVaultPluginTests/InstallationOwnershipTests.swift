import XCTest

@testable import TokenVaultPlugin

final class InstallationOwnershipTests: XCTestCase {
    func testNewInstallationOwnsOnlySlotsItWrites() {
        let suiteName = "com.afanasievn.tokenvault.ownership.\(UUID().uuidString)"
        let previousDefaults = UserDefaults(suiteName: suiteName)!
        defer { previousDefaults.removePersistentDomain(forName: suiteName) }

        let previousInstall = InstallationOwnership(defaults: previousDefaults)
        previousInstall.markOwned("refresh")

        previousDefaults.removePersistentDomain(forName: suiteName)
        let reinstalledDefaults = UserDefaults(suiteName: suiteName)!
        let currentInstall = InstallationOwnership(defaults: reinstalledDefaults)
        currentInstall.markOwned("device")

        XCTAssertFalse(currentInstall.owns("refresh"))
        XCTAssertTrue(currentInstall.owns("device"))
    }

    func testRemovingOneSlotDoesNotChangeAnotherSlotsOwnership() {
        let suiteName = "com.afanasievn.tokenvault.ownership.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let ownership = InstallationOwnership(defaults: defaults)

        ownership.markOwned("refresh")
        ownership.markOwned("device")
        ownership.removeOwnership(of: "refresh")

        XCTAssertFalse(ownership.owns("refresh"))
        XCTAssertTrue(ownership.owns("device"))
    }

    func testRemoveAllClearsEveryOwnedSlot() {
        let suiteName = "com.afanasievn.tokenvault.ownership.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let ownership = InstallationOwnership(defaults: defaults)

        ownership.markOwned("refresh")
        ownership.markOwned("device")
        ownership.removeAll()

        XCTAssertFalse(ownership.owns("refresh"))
        XCTAssertFalse(ownership.owns("device"))
    }
}
