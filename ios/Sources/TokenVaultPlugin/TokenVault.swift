import Foundation
import Security

/// Keychain wrapper for token slots. Pure Foundation + Security - no Capacitor types,
/// so it is unit-testable without a bridge (see ios/Tests).
///
/// Fixed attributes (docs/DESIGN.md):
/// - `kSecClassGenericPassword` - one item per slot, keyed by service + account.
/// - `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` - requires an unlocked device AND
///   keeps the item out of iTunes/iCloud backups, so a restore onto another device
///   cannot carry the token with it.
/// - `kSecAttrSynchronizable = false` - never offered to iCloud Keychain.
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

/// Tracks which named slots were written by the current app installation.
///
/// Keychain items can survive deletion while UserDefaults cannot. Ownership therefore has
/// to be recorded per slot: one newly written slot must never make a different inherited
/// slot readable after a reinstall.
struct InstallationOwnership {
    private static let keyPrefix = "token-vault.owned."
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func owns(_ name: String) -> Bool {
        defaults.bool(forKey: Self.keyPrefix + name)
    }

    func markOwned(_ name: String) {
        defaults.set(true, forKey: Self.keyPrefix + name)
    }

    func removeOwnership(of name: String) {
        defaults.removeObject(forKey: Self.keyPrefix + name)
    }

    func removeAll() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(Self.keyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }
}

public struct TokenVault {
    private let service: String
    private let ownership: InstallationOwnership

    /// - Parameters:
    ///   - bundleIdentifier: the host app's bundle id; the service is derived from it so
    ///     two apps on one device never share a slot.
    ///   - defaults: injectable for tests; production uses `.standard`.
    public init(bundleIdentifier: String?, defaults: UserDefaults = .standard) {
        let base = bundleIdentifier ?? "capacitor.app"
        self.service = "\(base).token-vault"
        self.ownership = InstallationOwnership(defaults: defaults)
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
        ]
    }

    public func set(name: String, value: String) throws {
        try validate(name: name)
        guard let data = value.data(using: .utf8), !data.isEmpty else {
            throw TokenVaultError.invalidArgument("value must be a non-empty string")
        }

        // Delete-then-add instead of SecItemUpdate: it is one code path and it
        // guarantees the accessibility attribute of the *new* write wins even if an
        // older build stored the item with different protection.
        SecItemDelete(baseQuery(name: name) as CFDictionary)

        var attributes = baseQuery(name: name)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw TokenVaultError.storageFailure(status) }
        ownership.markOwned(name)
    }

    public func get(name: String) throws -> String? {
        try validate(name: name)

        // Inherited from a previous installation of this app, not ours to hand back.
        // Remove this slot only; another slot may already belong to the current install.
        if !ownership.owns(name) {
            SecItemDelete(baseQuery(name: name) as CFDictionary)
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
        ownership.removeOwnership(of: name)
    }

    /// Removes every slot of this service and its installation ownership marker.
    public func clear() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TokenVaultError.storageFailure(status)
        }
        ownership.removeAll()
    }
}
