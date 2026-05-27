// UserSettings.swift
//
// Persistent app preferences (NOT secrets — those go in Keychain).
//
// Storage strategy:
//   1. Primary: `NSUbiquitousKeyValueStore` — iCloud key-value sync. Your
//      repo list and refresh cadence follow you across all your Macs
//      signed into the same iCloud account.
//   2. Fallback: `UserDefaults.standard` — used when iCloud is unavailable
//      (no iCloud account, sandbox restriction, sync transient failure).
//
// Both stores are written on every save so the two stay aligned. On read
// we prefer iCloud when present, fall back to local. This pattern matches
// Apple's recommended approach for small user-preference data that should
// sync but must work offline.
//
// Posts `UserSettings.didChangeNotification` on the main queue whenever a
// value changes, locally or via iCloud sync from another device. ViewModels
// can subscribe and trigger a refresh.

import Foundation

public enum UserSettings {

    // MARK: - Notification
    public static let didChangeNotification = Notification.Name("MacMonitor.UserSettings.didChange")

    // MARK: - Keys
    private enum Key {
        static let repositorySlugs       = "macmonitor.repositorySlugs"        // [String]
        static let refreshIntervalSeconds = "macmonitor.refreshIntervalSeconds" // Int
        static let touchIDGateEnabled    = "macmonitor.touchIDGateEnabled"      // Bool
    }

    private static let ubiquitous = NSUbiquitousKeyValueStore.default
    private static let local = UserDefaults.standard

    // MARK: - repositorySlugs

    /// Repo slugs to monitor, in `owner/name` form. Default falls back to
    /// the mock's first repository (currently JP1222/Yolo-Rollo).
    public static var repositorySlugs: [String] {
        get {
            if let arr = ubiquitous.array(forKey: Key.repositorySlugs) as? [String], !arr.isEmpty {
                return arr
            }
            if let arr = local.stringArray(forKey: Key.repositorySlugs), !arr.isEmpty {
                return arr
            }
            return ["JP1222/Yolo-Rollo"]
        }
        set {
            let cleaned = newValue
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.contains("/") }
            ubiquitous.set(cleaned, forKey: Key.repositorySlugs)
            local.set(cleaned, forKey: Key.repositorySlugs)
            ubiquitous.synchronize()
            postChange()
        }
    }

    // MARK: - refreshIntervalSeconds

    /// Polling interval for the DashboardViewModel's GitHub API fetch loop.
    /// Bounded 10s ... 600s (1h) — anything outside is clamped at access.
    public static var refreshIntervalSeconds: Int {
        get {
            let v = ubiquitous.object(forKey: Key.refreshIntervalSeconds) as? Int
                ?? (local.object(forKey: Key.refreshIntervalSeconds) as? Int)
                ?? 15
            return min(600, max(10, v))
        }
        set {
            let clamped = min(600, max(10, newValue))
            ubiquitous.set(clamped, forKey: Key.refreshIntervalSeconds)
            local.set(clamped, forKey: Key.refreshIntervalSeconds)
            ubiquitous.synchronize()
            postChange()
        }
    }

    // MARK: - touchIDGateEnabled

    /// If true, KeychainStore wraps token reads in a LAContext biometric
    /// challenge. Default: false (existing UX). Opt-in for high-security.
    public static var touchIDGateEnabled: Bool {
        get {
            (ubiquitous.object(forKey: Key.touchIDGateEnabled) as? Bool)
                ?? local.bool(forKey: Key.touchIDGateEnabled)
        }
        set {
            ubiquitous.set(newValue, forKey: Key.touchIDGateEnabled)
            local.set(newValue, forKey: Key.touchIDGateEnabled)
            ubiquitous.synchronize()
            postChange()
        }
    }

    // MARK: - iCloud → local replication

    /// Call once on app launch so iCloud changes posted while the app was
    /// closed get observed. Bridges `NSUbiquitousKeyValueStore` change
    /// notifications into our app-wide `didChangeNotification`.
    public static func startObservingICloud() {
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: ubiquitous,
            queue: .main
        ) { _ in postChange() }
        ubiquitous.synchronize()
    }

    private static func postChange() {
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }
}
