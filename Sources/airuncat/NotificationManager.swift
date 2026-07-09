import UserNotifications
import AppKit

@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

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
        // Store cwd so delegate can open iTerm without needing SessionStore
        content.userInfo = ["sessionId": session.sessionId, "cwd": session.cwd]

        let request = UNNotificationRequest(
            identifier: "idle-\(session.sessionId)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    /// 사용량 임계/리셋 알림 (R8). 같은 id는 최신 1건으로 대체된다.
    func sendUsageAlert(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: "usage-\(id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    func dismissIdleNotification(for sessionId: String) {
        let id = "idle-\(sessionId)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let sessionId = info["sessionId"] as? String
        let cwd = info["cwd"] as? String ?? ""

        Task { @MainActor in
            if let id = sessionId {
                // Construct minimal stub — ITermController only needs sessionId + cwd
                let stub = SessionInfo(
                    id: id, sessionId: id, title: "", customName: nil,
                    projectName: "", cwd: cwd, gitBranch: "",
                    firstInstruction: "", lastUserMessage: "", toolName: "", toolDetail: "",
                    lastActivity: Date(), messageCount: 0, workState: .responded, aiKind: .claude
                )
                ITermController.open(stub)
            }
            completionHandler()
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
