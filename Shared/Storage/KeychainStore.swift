// KeychainStore.swift
//
// Thin wrapper around the Security framework's generic-password APIs. Stores
// the GitHub PAT in the sandboxed app's keychain (a per-bundle Data Vault),
// which means:
//
//   - The keychain item is NOT accessible to other apps or the `security`
//     CLI — only this signed bundle can read it.
//   - No `keychain-access-groups` entitlement is required.
//   - The item survives app reinstalls (keychain persists separately from the
//     app bundle and DerivedData).
//   - Encrypted at rest using the user's account password as the KEK; the
//     OS unlocks the keychain when the user logs in.
//
// The user supplies the PAT through the Settings sheet — see SettingsView.
// We never accept the PAT through the chat or environment to keep it from
// being captured in logs or git history.

import Foundation
import Security
#if canImport(LocalAuthentication)
import LocalAuthentication
#endif

public enum KeychainStore {

    /// Service identifier — opaque to the user; pick something unique to this
    /// app so it doesn't collide with anything else in the keychain.
    public static let githubTokenService = "MacMonitor.GitHubToken"

    /// We only ever have one GitHub token per install — the account label is
    /// cosmetic (shows up in Keychain Access.app if the user inspects), not
    /// a primary key.
    public static let githubTokenAccount = "github.com"

    public enum KeychainError: Error, LocalizedError {
        case unhandled(OSStatus)
        case decodeFailure

        public var errorDescription: String? {
            switch self {
            case .unhandled(let status):
                return "Keychain error (OSStatus \(status))"
            case .decodeFailure:
                return "Keychain returned data that wasn't UTF-8"
            }
        }
    }

    // MARK: - GitHub token

    public static func saveGitHubToken(_ token: String) throws {
        // Trim whitespace defensively — copy-paste from 1Password sometimes
        // grabs a trailing newline.
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        try set(value: trimmed, service: githubTokenService, account: githubTokenAccount)
    }

    /// Session-level unlock flag. When `UserSettings.touchIDGateEnabled` is
    /// true and this is false, `readGitHubToken()` returns nil to force the
    /// caller to `unlockSession()` first. Reset on process restart.
    private static var sessionUnlocked = false

    public static func readGitHubToken() -> String? {
        // If the Touch ID gate is on and the user hasn't unlocked this
        // session yet, refuse to surface the token. The caller (typically
        // GitHubClient) will get nil → its request returns .missingToken →
        // the user sees a "biometric required" prompt from the ViewModel
        // and re-tries via unlockSession().
        if UserSettings.touchIDGateEnabled && !sessionUnlocked {
            return nil
        }
        return try? get(service: githubTokenService, account: githubTokenAccount)
    }

    /// Triggers the Touch ID prompt (or device password fallback) and on
    /// success marks the session unlocked so subsequent sync reads succeed.
    /// Call once on app launch when `UserSettings.touchIDGateEnabled` is
    /// true, then again any time the user explicitly re-locks.
    @discardableResult
    public static func unlockSession(reason: String = "Unlock your GitHub token") async -> Bool {
        #if canImport(LocalAuthentication)
        let context = LAContext()
        var error: NSError?
        // Use deviceOwnerAuthentication (biometrics OR password) so users
        // without Touch ID sensors can still unlock.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No biometrics and no password configured → user can't unlock.
            // Fail closed: stay locked, surface the error upstream.
            return false
        }
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
            sessionUnlocked = success
            return success
        } catch {
            return false
        }
        #else
        // No LocalAuthentication framework — unlock unconditionally (we're
        // already token-gated by the OS keychain).
        sessionUnlocked = true
        return true
        #endif
    }

    /// Forget the session unlock — next read will require Touch ID again.
    /// Useful when the user disables the gate then re-enables it.
    public static func lockSession() {
        sessionUnlocked = false
    }

    public static func deleteGitHubToken() throws {
        try delete(service: githubTokenService, account: githubTokenAccount)
    }

    /// Presence check — does a token exist in the keychain? Uses an
    /// existence-only query (NOT `readGitHubToken()`), so it stays correct
    /// when the Touch ID gate is engaged: the gate guards *reading the
    /// secret*, but mere existence isn't sensitive. Routing through
    /// `readGitHubToken()` made this falsely report "no token" on a locked
    /// session → the popover showed onboarding for Touch-ID users.
    public static var hasGitHubToken: Bool {
        itemExists(service: githubTokenService, account: githubTokenAccount)
    }

    // MARK: - Generic CRUD

    /// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`: the token is
    /// available as soon as the user has logged in once after boot, and is
    /// pinned to THIS device (won't sync via iCloud Keychain). Good default
    /// for a build-monitor token — you wouldn't want it on your phone.
    private static let accessible = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    private static func set(value: String, service: String, account: String) throws {
        guard let data = value.data(using: .utf8) else { throw KeychainError.decodeFailure }

        // Try update first; if no existing item, fall through to add.
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  account,
        ]
        let update: [String: Any] = [
            kSecValueData as String:    data,
            kSecAttrAccessible as String: accessible,
        ]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var add = query
            add[kSecValueData as String]    = data
            add[kSecAttrAccessible as String] = accessible
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unhandled(addStatus) }
        default:
            throw KeychainError.unhandled(status)
        }
    }

    private static func get(service: String, account: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  account,
            kSecReturnData as String:   true,
            kSecMatchLimit as String:   kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
        guard let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.decodeFailure
        }
        return string
    }

    /// Existence test that never returns the secret value — so it doesn't
    /// trip the Touch ID gate or any keychain ACL. `kSecReturnData: false`
    /// + nil result means SecItemCopyMatching just reports match/no-match.
    private static func itemExists(service: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  account,
            kSecMatchLimit as String:   kSecMatchLimitOne,
            kSecReturnData as String:   false,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    private static func delete(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        // errSecItemNotFound is fine — already gone.
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }
}
