import AppKit

/// Detects a text selection in any other app by watching for a drag-select or
/// multi-click, then simulating Cmd-C and diffing the pasteboard.
@MainActor
final class SelectionMonitor {
    static let shared = SelectionMonitor()

    private var monitor: Any?
    private var mouseDownLocation: NSPoint?
    private var mouseDownClickCount: Int = 0

    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    var onSelection: ((ClipSelection, NSPoint) -> Void)?

    private init() {}

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            mouseDownLocation = NSEvent.mouseLocation
            mouseDownClickCount = event.clickCount
        case .leftMouseUp:
            guard let downLocation = mouseDownLocation else { return }
            let upLocation = NSEvent.mouseLocation
            let dragged = hypot(upLocation.x - downLocation.x, upLocation.y - downLocation.y) > 4
            let multiClick = mouseDownClickCount >= 2
            mouseDownLocation = nil
            guard dragged || multiClick else { return }
            // Give the target app a brief moment to finish committing its selection
            // state before synthesizing the copy — some apps (e.g. Electron-based
            // ones) finalize selection asynchronously relative to the raw mouse event,
            // so a Cmd-C posted the instant mouse-up fires can copy nothing.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.captureSelection(at: upLocation)
            }
        default:
            break
        }
    }

    private func captureSelection(at point: NSPoint) {
        // Don't trigger on our own popup / windows.
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier {
            return
        }

        let priorChangeCount = NSPasteboard.general.changeCount
        postCmdC()
        pollForChange(priorChangeCount: priorChangeCount, attemptsLeft: 12, point: point)
    }

    private func pollForChange(priorChangeCount: Int, attemptsLeft: Int, point: NSPoint) {
        let pasteboard = NSPasteboard.general
        if pasteboard.changeCount != priorChangeCount {
            // Deliberately left on the clipboard, matching what a real Cmd-C would
            // have done — the user can still paste it normally elsewhere, popup or not.
            let newString = pasteboard.string(forType: .string)
            guard let text = newString?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
            let selection = ClipSelection(
                text: text,
                kind: classify(text),
                sourceApp: NSWorkspace.shared.frontmostApplication?.localizedName
            )
            onSelection?(selection, point)
            return
        }

        guard attemptsLeft > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            self?.pollForChange(priorChangeCount: priorChangeCount, attemptsLeft: attemptsLeft - 1, point: point)
        }
    }

    private func postCmdC() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        // Without this, macOS's brief post-hardware-event suppression window can
        // silently drop a synthetic keystroke posted right after the real mouse-up
        // that triggered it — which is exactly our timing here.
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalKeyboardEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true) // kVK_ANSI_C
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private func classify(_ text: String) -> ContentKind {
        guard let detector = Self.detector else { return .text }
        let range = NSRange(text.startIndex..., in: text)
        if let match = detector.firstMatch(in: text, options: [], range: range),
           match.range == range,
           let url = match.url {
            return url.scheme == "mailto" ? .email : .url
        }
        return .text
    }
}
