import SwiftUI
import AppKit

struct MenuBarMenuView: View {
    var body: some View {
        Button("Preferences…") { PreferencesWindowController.shared.show() }
        Button("Open Extensions Folder") { ExtensionStore.shared.openExtensionsFolder() }
        Divider()
        Button("Quit Clip") { NSApp.terminate(nil) }
    }
}
