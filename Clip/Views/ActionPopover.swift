import AppKit
import SwiftUI

@MainActor
final class ActionPopover {
    static let shared = ActionPopover()

    private var panel: NSPanel?
    private var dismissMonitor: Any?
    private var keyMonitor: Any?

    private init() {}

    func show(selection: ClipSelection, actions: [PopupAction], at point: NSPoint) {
        let applicable = actions.filter { $0.matches(selection) }
        guard !applicable.isEmpty else { return }
        dismiss()

        let content = PopoverContentView(actions: applicable) { [weak self] action in
            action.perform(selection)
            self?.dismiss()
        }
        let hosting = NSHostingController(rootView: content)

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.contentViewController = hosting
        panel.hidesOnDeactivate = false

        let size = hosting.view.fittingSize
        panel.setFrame(
            NSRect(x: point.x - size.width / 2, y: point.y + 14, width: size.width, height: size.height),
            display: true
        )
        panel.orderFrontRegardless()
        self.panel = panel

        dismissMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.dismiss()
                return nil
            }
            return event
        }
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
        if let dismissMonitor { NSEvent.removeMonitor(dismissMonitor) }
        dismissMonitor = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}

private struct PopoverContentView: View {
    let actions: [PopupAction]
    let onSelect: (PopupAction) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(actions) { action in
                Button {
                    onSelect(action)
                } label: {
                    ExtensionIconImage(iconValue: action.iconName, folderURL: action.iconFolderURL, size: 16)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .help(action.name)
            }
        }
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .fixedSize()
    }
}
