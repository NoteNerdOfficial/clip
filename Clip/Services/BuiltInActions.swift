import AppKit

/// Actions that ship with Clip itself, not backed by an extension folder.
/// Shown before extension-provided actions in the popup.
enum BuiltInActions {
    static let all: [PopupAction] = [
        PopupAction(
            id: "com.clip.builtin.copy",
            name: "Copy",
            iconName: "doc.on.doc",
            iconFolderURL: nil,
            matches: { _ in true },
            perform: { selection in
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(selection.text, forType: .string)
            }
        )
    ]
}
