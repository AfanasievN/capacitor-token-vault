import Capacitor
import Foundation

/// Capacitor bridge. Holds no logic beyond argument plumbing - the Keychain work is in
/// TokenVault.swift so it can be tested without a bridge.
@objc(TokenVaultPlugin)
public class TokenVaultPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "TokenVaultPlugin"
    public let jsName = "TokenVault"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "getCapabilities", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setToken", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getToken", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "removeToken", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "clear", returnType: CAPPluginReturnPromise),
    ]

    private lazy var vault = TokenVault(bundleIdentifier: Bundle.main.bundleIdentifier)
    private static let defaultName = "refresh"

    @objc public func getCapabilities(_ call: CAPPluginCall) {
        call.resolve([
            "backend": "keychain",
            "secure": true,
            "persistent": true,
            // The item is encrypted with a data-protection class key derived by the
            // hardware AES engine from the device UID, so it cannot be moved off this
            // device. That is what the flag claims - not Secure Enclave residency, which
            // applies to keys rather than payloads.
            "hardwareBacked": true,
        ])
    }

    @objc public func setToken(_ call: CAPPluginCall) {
        guard let value = call.options["value"] as? String, !value.isEmpty else {
            reject(call, message: "value must be a non-empty string", code: "INVALID_ARGUMENT")
            return
        }
        run(call) { try self.vault.set(name: self.name(from: call), value: value) }
    }

    @objc public func getToken(_ call: CAPPluginCall) {
        run(call) {
            let value = try self.vault.get(name: self.name(from: call))
            return ["value": value as Any]
        }
    }

    @objc public func removeToken(_ call: CAPPluginCall) {
        run(call) { try self.vault.remove(name: self.name(from: call)) }
    }

    @objc public func clear(_ call: CAPPluginCall) {
        run(call) { try self.vault.clear() }
    }

    private func name(from call: CAPPluginCall) -> String {
        (call.options["name"] as? String) ?? TokenVaultPlugin.defaultName
    }

    /// Keychain calls block; keep them off the WebView thread.
    private func run(_ call: CAPPluginCall, _ work: @escaping () throws -> [String: Any]?) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result = try work()
                call.resolve(result ?? [:])
            } catch let error as TokenVaultError {
                self.reject(call, message: error.message, code: error.code, error: error)
            } catch {
                self.reject(call, message: "unexpected keychain failure", code: "STORAGE_FAILURE", error: error)
            }
        }
    }

    /// Capacitor's SwiftPM binary exposes the Objective-C error handler but not the
    /// `CAPPluginCall.reject` convenience extension. Keep rejection construction in one
    /// place so JavaScript still receives the documented stable error code.
    private func reject(_ call: CAPPluginCall, message: String, code: String, error: Error? = nil) {
        call.errorHandler(CAPPluginCallError(message: message, code: code, error: error, data: nil))
    }

    private func run(_ call: CAPPluginCall, _ work: @escaping () throws -> Void) {
        run(call) {
            try work()
            return nil
        }
    }
}
