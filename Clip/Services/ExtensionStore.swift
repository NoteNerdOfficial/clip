import Foundation
import AppKit

@MainActor
final class ExtensionStore: ObservableObject {
    static let shared = ExtensionStore()

    @Published private(set) var extensions: [LoadedExtension] = []

    private let fileManager = FileManager.default

    private var extensionsDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Clip/Extensions", isDirectory: true)
    }

    private init() {}

    /// Copies bundled default extensions into the user's Extensions folder on first run,
    /// then loads everything found there.
    func loadAll() {
        installBundledDefaultsIfNeeded()
        reload()
    }

    func reload() {
        try? fileManager.createDirectory(at: extensionsDirectory, withIntermediateDirectories: true)

        let folders = (try? fileManager.contentsOfDirectory(at: extensionsDirectory, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "extension" } ?? []

        extensions = folders.compactMap { folder in
            let manifestURL = folder.appendingPathComponent("manifest.json")
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? JSONDecoder().decode(ExtensionManifest.self, from: data) else {
                return nil
            }
            return LoadedExtension(folderURL: folder, manifest: manifest, enabled: isEnabled(manifest.identifier))
        }
        .sorted { $0.manifest.name < $1.manifest.name }
    }

    func setEnabled(_ enabled: Bool, for identifier: String) {
        UserDefaults.standard.set(enabled, forKey: enabledKey(identifier))
        reload()
    }

    private func isEnabled(_ identifier: String) -> Bool {
        if UserDefaults.standard.object(forKey: enabledKey(identifier)) == nil { return true }
        return UserDefaults.standard.bool(forKey: enabledKey(identifier))
    }

    private func enabledKey(_ identifier: String) -> String { "extension.enabled.\(identifier)" }

    // MARK: Config (per-extension option values)

    func config(for ext: LoadedExtension) -> [String: String] {
        guard let data = try? Data(contentsOf: ext.configURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dict
    }

    func setConfig(_ config: [String: String], for ext: LoadedExtension) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        try? data.write(to: ext.configURL)
    }

    func openExtensionsFolder() {
        NSWorkspace.shared.open(extensionsDirectory)
    }

    // MARK: Popup actions

    func popupActions() -> [PopupAction] {
        extensions.filter(\.enabled).map { ext in
            PopupAction(
                id: ext.manifest.identifier,
                name: ext.manifest.name,
                iconName: ext.manifest.icon,
                iconFolderURL: ext.folderURL,
                matches: { ext.manifest.matches($0) },
                perform: { [weak self] selection in
                    guard let self else { return }
                    let payload: [String: Any] = [
                        "text": selection.text,
                        "kind": selection.kind.rawValue,
                        "sourceApp": selection.sourceApp ?? "",
                        "options": self.config(for: ext)
                    ]
                    ExtensionRunner.run(actionPath: ext.actionURL.path, payload: payload)
                }
            )
        }
    }

    // MARK: First-run install of bundled defaults

    private func installBundledDefaultsIfNeeded() {
        guard let bundledRoot = Bundle.main.url(forResource: "Extensions", withExtension: nil) else { return }
        try? fileManager.createDirectory(at: extensionsDirectory, withIntermediateDirectories: true)

        let bundledFolders = (try? fileManager.contentsOfDirectory(at: bundledRoot, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "extension" } ?? []

        for source in bundledFolders {
            let destination = extensionsDirectory.appendingPathComponent(source.lastPathComponent)
            guard !fileManager.fileExists(atPath: destination.path) else { continue }
            try? fileManager.copyItem(at: source, to: destination)
        }
    }
}
