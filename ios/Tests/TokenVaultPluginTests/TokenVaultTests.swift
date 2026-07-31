import XCTest

@testable import TokenVaultPlugin

/// Runs against the real Keychain on a simulator: the attributes are the point of this
/// plugin, so asserting them is the test that matters.
final class TokenVaultTests: XCTestCase {
    private let vault = TokenVault(bundleIdentifier: "com.afanasievn.tokenvault.tests")

    override func setUp() {
        super.setUp()
        try? vault.clear()
    }

    override func tearDown() {
        try? vault.clear()
        super.tearDown()
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
