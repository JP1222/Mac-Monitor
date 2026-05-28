// NotificationService.swift
//
// Posts macOS notification banners when a CI build transitions from "was
// passing" to "just failed". Each unique run ID is notified at most once
// per session — `lastNotifiedFailureIDs` deduplicates so we don't re-alert
// the same failure on every poll.
//
// Permission is requested lazily on the first notify attempt. macOS will
// show the system "Mac Monitor wants to send you notifications" prompt
// once; user's choice persists.
//
// Click the notification → opens the run's GitHub page in the browser.

import Foundation
import UserNotifications
#if canImport(AppKit)
import AppKit
#endif

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {

    static let shared = NotificationService()

    private var lastNotifiedFailureIDs: Set<String> = []
    private var authorized: Bool = false
    private var requestedAuthorization = false

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    /// Compare new snapshot's failure list to what we've already alerted on,
    /// send notifications for the new ones, update the dedupe set.
    func notifyFailures(in snapshot: DashboardSnapshot) async {
        // Failures finished in the last 10 minutes — anything older we assume
        // the user already knows about, and we don't want a wall of stale
        // alerts after a long offline period.
        let cutoff = Date().addingTimeInterval(-600)
        let newFailures = snapshot.recent.filter {
            $0.result == .failure && $0.finishedAt >= cutoff
        }

        let unNotified = newFailures.filter { !lastNotifiedFailureIDs.contains($0.id) }
        guard !unNotified.isEmpty else { return }

        guard await ensureAuthorized() else { return }

        for run in unNotified {
            await postNotification(run: run)
            lastNotifiedFailureIDs.insert(run.id)
        }

        // Bound the dedupe set so it doesn't grow forever — keep the 200
        // most recent IDs.
        if lastNotifiedFailureIDs.count > 200 {
            lastNotifiedFailureIDs = Set(lastNotifiedFailureIDs.suffix(200))
        }
    }

    /// Reset the dedupe set — useful for tests + after the user explicitly
    /// asks for a re-fetch.
    func resetDedupeState() {
        lastNotifiedFailureIDs.removeAll()
    }

    // MARK: - Authorization

    private func ensureAuthorized() async -> Bool {
        if authorized { return true }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .authorized {
            authorized = true
            return true
        }
        if requestedAuthorization { return false }
        requestedAuthorization = true
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
            authorized = granted
            return granted
        } catch {
            return false
        }
    }

    // MARK: - Post

    private func postNotification(run: RecentRun) async {
        let content = UNMutableNotificationContent()
        content.title = "CI failed · \(run.branch)"
        content.body = "\(run.workflow) · \(run.durationPretty)"
        content.sound = .default
        // Stash the URL in userInfo for the click handler.
        if let url = run.htmlURL {
            content.userInfo = ["url": url.absoluteString]
        }
        let request = UNNotificationRequest(
            identifier: "macmonitor.failure.\(run.id)",
            content: content,
            trigger: nil   // deliver immediately
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Click handler

    /// macOS calls this when the user clicks a delivered notification.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let urlString = response.notification.request.content.userInfo["url"] as? String,
           let url = URL(string: urlString) {
            #if canImport(AppKit)
            Task { @MainActor in NSWorkspace.shared.open(url) }
            #endif
        }
        completionHandler()
    }

    /// Show notification banner even while MacMonitor is "foreground"
    /// (since we're an LSUIElement app there's no real foreground, but
    /// this default lets the banner show after popover opens too).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
