import Foundation

enum ContentKind: String {
    case text
    case url
    case email
}

struct ClipSelection {
    let text: String
    let kind: ContentKind
    let sourceApp: String?
}

/// One entry in the popup. Extensions (Phase 4) contribute these dynamically;
/// built-in actions can be added the same way.
struct PopupAction: Identifiable {
    let id: String
    let name: String
    /// SF Symbol name, or a custom svg/png/pdf filename resolved against `iconFolderURL`.
    let iconName: String
    /// Folder to resolve a custom icon filename against. Nil for built-in actions (SF Symbol only).
    let iconFolderURL: URL?
    let matches: (ClipSelection) -> Bool
    let perform: (ClipSelection) -> Void
}
