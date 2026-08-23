import SwiftUI

struct PreferencesView: View {
    @ObservedObject var store = ExtensionStore.shared
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Clip")
                .font(.title2.bold())
                .padding([.top, .horizontal])

            List {
                Section("Extensions") {
                    ForEach(store.extensions) { ext in
                        ExtensionRow(ext: ext)
                    }
                }
                Section("General") {
                    Toggle("Launch at Login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { newValue in LaunchAtLogin.set(newValue) }
                    Button("Open Extensions Folder…") {
                        store.openExtensionsFolder()
                    }
                }
            }
            .listStyle(.inset)
        }
        .frame(width: 520, height: 480)
        .onAppear { store.reload() }
    }
}

private struct ExtensionRow: View {
    let ext: LoadedExtension
    @State private var isExpanded = false
    @State private var values: [String: String] = [:]

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 14) {
                if let description = ext.manifest.description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(ext.manifest.options) { option in
                    optionField(option)
                }
                if !ext.manifest.options.isEmpty {
                    Button("Save") {
                        ExtensionStore.shared.setConfig(values, for: ext)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.top, 6)
            .padding(.leading, 4)
        } label: {
            Toggle(isOn: Binding(
                get: { ext.enabled },
                set: { ExtensionStore.shared.setEnabled($0, for: ext.manifest.identifier) }
            )) {
                HStack(spacing: 6) {
                    ExtensionIconImage(iconValue: ext.manifest.icon, folderURL: ext.folderURL, size: 16)
                    Text(ext.manifest.name)
                }
            }
        }
        .onAppear {
            var loaded = ExtensionStore.shared.config(for: ext)
            for option in ext.manifest.options where loaded[option.key] == nil {
                if let defaultValue = option.defaultValue {
                    loaded[option.key] = defaultValue
                }
            }
            values = loaded
        }
    }

    @ViewBuilder
    private func optionField(_ option: ExtensionOption) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            switch option.type {
            case .string:
                TextField(option.label, text: binding(for: option.key), prompt: Text(option.placeholder ?? ""))
            case .secret:
                SecureField(option.label, text: binding(for: option.key), prompt: Text(option.placeholder ?? ""))
            case .bool:
                Toggle(option.label, isOn: Binding(
                    get: { values[option.key] == "true" },
                    set: { values[option.key] = $0 ? "true" : "false" }
                ))
            }
            if let description = option.description {
                Text(description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(get: { values[key] ?? "" }, set: { values[key] = $0 })
    }
}
