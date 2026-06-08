import UserNotifications
import AppKit

@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    weak var sessionStore: SessionStore?

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func sendIdleNotification(for session: SessionInfo) {
        let content = UNMutableNotificationContent()
        content.title = session.displayName.isEmpty ? "Unnamed Session" : session.displayName
        content.body = "입력 대기 중"
        content.sound = .default
        content.userInfo = ["sessionId": session.sessionId]

        let request = UNNotificationRequest(
            identifier: "idle-\(session.sessionId)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    func dismissIdleNotification(for sessionId: String) {
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: ["idle-\(sessionId)"])
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let sessionId = response.notification.request.content.userInfo["sessionId"] as? String
        Task { @MainActor in
            if let id = sessionId,
               let session = self.sessionStore?.sessions.first(where: { $0.sessionId == id }) {
                ITermController.open(session)
            }
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
