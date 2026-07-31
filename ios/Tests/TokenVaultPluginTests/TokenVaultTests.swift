import XCTest

@testable import TokenVaultPlugin

/// Runs against the real Keychain on a simulator: the attributes are the point of this
/// plugin, so asserting them is the test that matters.
final class TokenVaultTests: XCTestCase {
    /// A UserDefaults suite per test run stands in for "this installation" so the
    /// reinstall behavior can be exercised without deleting the app.
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var vault: TokenVault!

    override func setUp() {
        super.setUp()
        suiteName = "com.afanasievn.tokenvault.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        vault = TokenVault(bundleIdentifier: "com.afanasievn.tokenvault.tests", defaults: defaults)
        try? vault.clear()
    }

    override func tearDown() {
        try? vault.clear()
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    /// Simulates a reinstall: the app's UserDefaults are gone, the Keychain item is not.
    private func freshInstallation() -> TokenVault {
        defaults.removePersistentDomain(forName: suiteName)
        let reinstalled = UserDefaults(suiteName: suiteName)!
        return TokenVault(bundleIdentifier: "com.afanasievn.tokenvault.tests", defaults: reinstalled)
    }

    func testRoundTrip() throws {
        try vault.set(name: "refresh", value: "rt-1")
        XCTAssertEqual(try vault.get(name: "refresh"), "rt-1")
    }

    func testMissingSlotReadsAsNil() throws {
        XCTAssertNil(try vault.get(name: "refresh"))
    }

    func testOverwriteKeepsOneItem() throws {
        try vault.set(name: "refresh", value: "first")
        try vault.set(name: "refresh", value: "second")
        XCTAssertEqual(try vault.get(name: "refresh"), "second")
    }

    func testNamedSlotsAreIndependent() throws {
        try vault.set(name: "refresh", value: "a")
        try vault.set(name: "secondary", value: "b")
        XCTAssertEqual(try vault.get(name: "refresh"), "a")
        XCTAssertEqual(try vault.get(name: "secondary"), "b")
    }

    func testRemoveIsIdempotent() throws {
        XCTAssertNoThrow(try vault.remove(name: "refresh"))
        try vault.set(name: "refresh", value: "rt")
        try vault.remove(name: "refresh")
        XCTAssertNil(try vault.get(name: "refresh"))
    }

    func testClearRemovesEverySlot() throws {
        try vault.set(name: "refresh", value: "a")
        try vault.set(name: "secondary", value: "b")
        try vault.clear()
        XCTAssertNil(try vault.get(name: "refresh"))
        XCTAssertNil(try vault.get(name: "secondary"))
    }

    func testRejectsMalformedName() {
        XCTAssertThrowsError(try vault.set(name: "bad name!", value: "rt")) { error in
            XCTAssertEqual(error as? TokenVaultError, .invalidArgument("token name must match ^[a-zA-Z0-9._-]{1,64}$"))
        }
    }

    func testRejectsEmptyValue() {
        XCTAssertThrowsError(try vault.set(name: "refresh", value: "")) { error in
            XCTAssertEqual((error as? TokenVaultError)?.code, "INVALID_ARGUMENT")
        }
    }

    /// iOS keeps Keychain items across app deletion, so a fresh install must not resume a
    /// session it never created — possibly a different person's on a resold device.
    func testTokenFromAPreviousInstallationIsNotReturned() throws {
        try vault.set(name: "refresh", value: "rt-of-previous-install")

        let reinstalled = freshInstallation()

        XCTAssertNil(try reinstalled.get(name: "refresh"))
        // …and the inherited item is gone, not merely hidden.
        XCTAssertNil(try vault.get(name: "refresh"))
    }

    /// The flip side: within one installation the token must survive a new instance
    /// (that is the whole point of persisting it).
    func testTokenSurvivesWithinTheSameInstallation() throws {
        try vault.set(name: "refresh", value: "rt")

        let sameInstall = TokenVault(bundleIdentifier: "com.afanasievn.tokenvault.tests", defaults: defaults)

        XCTAssertEqual(try sameInstall.get(name: "refresh"), "rt")
    }

    /// The security posture itself: device-only accessibility (⇒ not in backups) and no
    /// iCloud synchronization. A regression here is invisible in behavior tests.
    func testStoredItemAttributes() throws {
        try vault.set(name: "refresh", value: "rt")

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.afanasievn.tokenvault.tests.token-vault",
            kSecAttrAccount as String: "refresh",
            kSecUseDataProtectionKeychain as String: true,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, &item), errSecSuccess)

        let attributes = try XCTUnwrap(item as? [String: Any])
        XCTAssertEqual(
            attributes[kSecAttrAccessible as String] as! CFString,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        )
        XCTAssertEqual(attributes[kSecAttrSynchronizable as String] as? Bool, false)
    }
}
