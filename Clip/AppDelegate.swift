import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DebugLog.write("applicationDidFinishLaunching called")
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        Task { @MainActor in
            ExtensionStore.shared.loadAll()

            SelectionMonitor.shared.onSelection = { selection, point in
                ActionPopover.shared.show(
                    selection: selection,
                    actions: BuiltInActions.all + ExtensionStore.shared.popupActions(),
                    at: point
                )
            }
            SelectionMonitor.shared.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in SelectionMonitor.shared.stop() }
    }
}
