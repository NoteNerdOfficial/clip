import AppKit
import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        DebugLog.write("applicationDidFinishLaunching called")
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
        // Size the window once from the content's natural size, then stop tracking.
        // NSWindow(contentViewController:) keeps the window and the hosting
        // controller's preferred size continuously in sync, which for
        // height-flexible SwiftUI content (wrapped text here) can feed back
        // into itself as a reentrant layout loop — a hard crash on macOS 26.
        hosting.sizingOptions = []
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Clip"
        window.contentViewController = hosting
        window.setContentSize(hosting.view.fittingSize)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
    }
}
