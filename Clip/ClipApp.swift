import SwiftUI
import AppKit

@main
struct ClipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenuView()
        } label: {
            MenuBarIcon()
        }
    }
}

private struct MenuBarIcon: View {
    var body: some View {
        if let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "svg"),
           let nsImage = NSImage(contentsOfFile: url.path) {
            let _ = { nsImage.isTemplate = true }()
            Image(nsImage: nsImage)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
        } else {
            Image(systemName: "wand.and.stars")
        }
    }
}
