import Foundation
import AppKit
import UserNotifications
import BatteryCore
enum NotificationAccess { case allowed, denied, notAsked, unavailable }
@MainActor protocol NotificationSink: AnyObject {
    func deliver(_ e:AlertEvent)
    func remove(_ ids:[String])
    func access(_ done:@escaping @MainActor (NotificationAccess)->Void)
    func request(_ done:@escaping @MainActor (NotificationAccess)->Void)
}
/// Used when the binary runs outside an .app bundle, where UserNotifications would abort the process.
final class NoNotificationSink: NotificationSink {
    func deliver(_ e:AlertEvent) {}
    func remove(_ ids:[String]) {}
    func access(_ done:@escaping @MainActor (NotificationAccess)->Void) { done(.unavailable) }
    func request(_ done:@escaping @MainActor (NotificationAccess)->Void) { done(.unavailable) }
}
final class SystemNotificationSink: NotificationSink {
    private let center=UNUserNotificationCenter.current()
    func deliver(_ e:AlertEvent) {
        let c=UNMutableNotificationContent()
        c.title=e.title;c.body=e.body;c.threadIdentifier=e.thread;c.userInfo=["section":e.section];c.sound = .default
        center.add(UNNotificationRequest(identifier:e.id,content:c,trigger:nil)) { _ in }
    }
    func remove(_ ids:[String]) { center.removeDeliveredNotifications(withIdentifiers:ids) }
    func access(_ done:@escaping @MainActor (NotificationAccess)->Void) {
        center.getNotificationSettings { s in
            let a:NotificationAccess
            switch s.authorizationStatus {
            case .authorized,.provisional:a = .allowed
            case .denied:a = .denied
            default:a = .notAsked
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { done(a) } }
        }
    }
    func request(_ done:@escaping @MainActor (NotificationAccess)->Void) {
        center.requestAuthorization(options:[.alert,.sound]) { [weak self] _,_ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.access(done) } }
        }
    }
}
enum NotificationRuntime {
    static var bundled:Bool { Bundle.main.bundleURL.pathExtension=="app" && Bundle.main.bundleIdentifier != nil }
    @MainActor static func makeSink() -> NotificationSink { bundled ? SystemNotificationSink():NoNotificationSink() }
}
/// Receives notification clicks, including the one that launched the app, and shows foreground notifications.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared=NotificationRouter()
    @MainActor var open:((String)->Void)? { didSet { if let p=pending,let open { pending=nil;open(p) } } }
    @MainActor private var pending:String?
    @MainActor func route(_ section:String) { if let open { open(section) } else { pending=section } }
    func userNotificationCenter(_ center:UNUserNotificationCenter,willPresent notification:UNNotification,withCompletionHandler completionHandler:@escaping (UNNotificationPresentationOptions)->Void) {
        completionHandler([.banner,.list,.sound])
    }
    func userNotificationCenter(_ center:UNUserNotificationCenter,didReceive response:UNNotificationResponse,withCompletionHandler completionHandler:@escaping ()->Void) {
        let section=AlertEvent.route(response.notification.request.content.userInfo["section"])
        DispatchQueue.main.async { MainActor.assumeIsolated { NotificationRouter.shared.route(section) };completionHandler() }
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification:Notification) {
        if NotificationRuntime.bundled { UNUserNotificationCenter.current().delegate=NotificationRouter.shared }
    }
    /// A dashboard card is easy to miss, so a copy outside Applications asks once at launch; the card stays for "Not now".
    func applicationDidFinishLaunching(_ notification:Notification) {
        Task { @MainActor in AppModel.shared.askToMoveIfNeeded() }
    }
}
