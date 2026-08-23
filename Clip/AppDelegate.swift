import AppKit
import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        Task { @MainActor in
            ExtensionStore.shared.loadAll()

            if !AXIsProcessTrusted() {
                showOnboarding()
            }

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

    @MainActor
    private func showOnboarding() {
        let root = PermissionsOnboardingView(isPresented: Binding(
            get: { true },
            set: { [weak self] newValue in
                if newValue == false { self?.onboardingWindow?.close() }
            }
        ))
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Clip"
        window.styleMask = [.titled, .closable]
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
    }
}
