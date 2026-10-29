import AppKit
import UserNotifications

enum ActivityNotificationText {
    static func title(for activity: RecentActivity) -> String {
        activity.kind.name + " · " + activity.reason.message
    }
    static func body(for activity: RecentActivity, showsDetails: Bool) -> String {
        guard showsDetails else { return L("자세한 내용은 NotchAgent에서 확인하세요.", "Open NotchAgent for details.") }
        return activity.title == activity.folder ? activity.folder : activity.title + " · " + activity.folder
    }
}

@MainActor
final class ActivityNotifications: NSObject, UNUserNotificationCenterDelegate {
    var openSession: ((UUID) -> Void)?
    var openActivity: ((UUID) -> Void)?
    private let center = UNUserNotificationCenter.current()
    private var authorized = false

    override init() {
        super.init()
        center.delegate = self
    }
    func requestPermission() async -> String? {
        do {
            authorized = try await center.requestAuthorization(options: [.alert, .sound])
            return authorized ? nil : deniedMessage
        } catch { return error.localizedDescription }
    }
    func refreshPermission() async -> String? {
        let settings = await center.notificationSettings()
        authorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        return settings.authorizationStatus == .denied ? deniedMessage : nil
    }
    private var deniedMessage: String {
        L("시스템 설정 → 알림 → NotchAgent에서 알림을 허용하세요.", "Allow notifications in System Settings → Notifications → NotchAgent.")
    }
    func deliver(_ activity: RecentActivity, notification: Bool, sound: Bool, showsDetails: Bool) {
        guard notification && authorized else {
            if sound { NSSound(named: NSSound.Name("Pop"))?.play() }
            return
        }
        let content = UNMutableNotificationContent()
        content.title = ActivityNotificationText.title(for: activity)
        content.body = ActivityNotificationText.body(for: activity, showsDetails: showsDetails)
        content.userInfo = ["sessionID": activity.sessionID.uuidString, "activityID": activity.id.uuidString]
        if sound { content.sound = .default }
        center.add(UNNotificationRequest(identifier: activity.id.uuidString, content: content, trigger: nil)) { error in
            if error != nil { Log.app.notice("activity notification could not be delivered") }
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            let info = response.notification.request.content.userInfo
            if let raw = info["activityID"] as? String, let id = UUID(uuidString: raw) {
                Task { @MainActor [weak self] in self?.openActivity?(id) }
            } else if let raw = info["sessionID"] as? String, let id = UUID(uuidString: raw) {
                Task { @MainActor [weak self] in self?.openSession?(id) }
            }
        }
        completionHandler()
    }
}
