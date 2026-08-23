import Foundation

struct ExtensionOption: Codable, Identifiable {
    enum Kind: String, Codable {
        case string
        case bool
        case secret
    }

    let key: String
    let label: String
    let type: Kind
    let placeholder: String?
    let defaultValue: String?
    /// Short helper text shown under the field explaining what to enter and why.
    let description: String?

    var id: String { key }
}

struct ExtensionManifest: Codable {
    let identifier: String
    let name: String
    /// SF Symbol name shown as the popup button icon.
    let icon: String
    /// "text" | "url" | "email" | "any" — which selection kinds this extension applies to.
    let match: String
    /// Shown under the extension's name in Preferences.
    let description: String?
    let options: [ExtensionOption]

    func matches(_ selection: ClipSelection) -> Bool {
        switch match {
        case "url": return selection.kind == .url
        case "email": return selection.kind == .email
        default: return true // "text" / "any" / anything else: applies to all selections
        }
    }
}

/// A manifest.json + action.js pair loaded from an `<Name>.extension` folder.
struct LoadedExtension: Identifiable {
    let folderURL: URL
    let manifest: ExtensionManifest
    var enabled: Bool

    var id: String { manifest.identifier }
    var actionURL: URL { folderURL.appendingPathComponent("action.js") }
    var configURL: URL { folderURL.appendingPathComponent("config.json") }
}
