import AppKit
import SwiftUI

@MainActor
final class AccessibilityOnboardingWindowController {
    static let shared = AccessibilityOnboardingWindowController()

    private var window: NSWindow?

    private init() {}

    func show() {
        if window == nil {
            let root = PermissionsOnboardingView(isPresented: Binding(
                get: { true },
                set: { [weak self] newValue in
                    if newValue == false { self?.window?.close() }
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
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
