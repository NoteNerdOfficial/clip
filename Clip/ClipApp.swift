import SwiftUI

@main
struct ClipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Clip", systemImage: "wand.and.stars") {
            MenuBarMenuView()
        }
    }
}
