import Foundation
import Security

/// Keychain wrapper for token slots. Pure Foundation + Security — no Capacitor types,
/// so it is unit-testable without a bridge (see ios/Tests).
///
/// Fixed attributes (docs/DESIGN.md):
/// - `kSecClassGenericPassword` — one item per slot, keyed by service + account.
/// - `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — requires an unlocked device AND
///   keeps the item out of iTunes/iCloud backups, so a restore onto another device
///   cannot carry the token with it.
/// - `kSecAttrSynchronizable = false` — never offered to iCloud Keychain.
/// - `kSecUseDataProtectionKeychain = true` — the modern (app-sandbox-scoped) keychain
///   rather than the legacy file-based one.
public enum TokenVaultError: Error, Equatable {
    case invalidArgument(String)
    case storageFailure(OSStatus)

    /// Code handed to JS. Never includes the token value.
    public var code: String {
        switch self {
        case .invalidArgument: return "INVALID_ARGUMENT"
        case .storageFailure: return "STORAGE_FAILURE"
        }
    }

    public var message: String {
        switch self {
        case let .invalidArgument(what): return what
        case let .storageFailure(status): return "keychain operation failed (OSStatus \(status))"
        }
    }
}

public struct TokenVault {
    private let service: String
    private let defaults: UserDefaults

    /// Marker kept in UserDefaults — which iOS *does* delete with the app, unlike the
    /// Keychain (see `isSameInstallation`).
    private static let installMarkerKey = "token-vault.installation"

    /// - Parameters:
    ///   - bundleIdentifier: the host app's bundle id; the service is derived from it so
    ///     two apps on one device never share a slot.
    ///   - defaults: injectable for tests; production uses `.standard`.
    public init(bundleIdentifier: String?, defaults: UserDefaults = .standard) {
        let base = bundleIdentifier ?? "capacitor.app"
        self.service = "\(base).token-vault"
        self.defaults = defaults
    }

    /// iOS keeps Keychain items when an app is deleted (the iOS 10.3 beta change that
    /// removed them was rolled back, and Apple has never documented the behavior). So a
    /// freshly installed app can find a token written by a *previous installation* — quite
    /// possibly by a different person, on a resold or shared device.
    ///
    /// UserDefaults, unlike the Keychain, does go away with the app. A marker written next
    /// to every token therefore answers "did *this* installation store it?". No marker plus
    /// a stored item means the item is inherited: `get` treats it as absent and clears it,
    /// so the app asks for a fresh sign-in instead of resuming a stranger's session.
    private func isSameInstallation() -> Bool {
        defaults.string(forKey: TokenVault.installMarkerKey) != nil
    }

    private func markInstallation() {
        guard !isSameInstallation() else { return }
        defaults.set(UUID().uuidString, forKey: TokenVault.installMarkerKey)
    }

    private static let namePattern = try! NSRegularExpression(pattern: "^[a-zA-Z0-9._-]{1,64}$")

    private func validate(name: String) throws {
        let range = NSRange(name.startIndex..., in: name)
        guard TokenVault.namePattern.firstMatch(in: name, range: range) != nil else {
            throw TokenVaultError.invalidArgument("token name must match ^[a-zA-Z0-9._-]{1,64}$")
        }
    }

    private func baseQuery(name: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: name,
            kSecAttrSynchronizable as String: false,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    public func set(name: String, value: String) throws {
        try validate(name: name)
        guard let data = value.data(using: .utf8), !data.isEmpty else {
            throw TokenVaultError.invalidArgument("value must be a non-empty string")
        }

        markInstallation()

        // Delete-then-add instead of SecItemUpdate: it is one code path and it
        // guarantees the accessibility attribute of the *new* write wins even if an
        // older build stored the item with different protection.
        SecItemDelete(baseQuery(name: name) as CFDictionary)

        var attributes = baseQuery(name: name)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw TokenVaultError.storageFailure(status) }
    }

    public func get(name: String) throws -> String? {
        try validate(name: name)

        // Inherited from a previous installation of this app — not ours to hand back.
        if !isSameInstallation() {
            try? clear()
            return nil
        }

        var query = baseQuery(name: name)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw TokenVaultError.storageFailure(status) }
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            // Present but unreadable: treat as absent after clearing the bad item, so a
            // corrupt slot cannot lock a user out of signing in again.
            SecItemDelete(baseQuery(name: name) as CFDictionary)
            return nil
        }
        return value
    }

    public func remove(name: String) throws {
        try validate(name: name)
        let status = SecItemDelete(baseQuery(name: name) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TokenVaultError.storageFailure(status)
        }
    }

    /// Removes every slot of this service — logout / account switch. The installation
    /// marker stays: it says "this install owns whatever is here", and after a wipe there
    /// is nothing to disown.
    public func clear() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecUseDataProtectionKeychain as String: true,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TokenVaultError.storageFailure(status)
        }
    }
}
