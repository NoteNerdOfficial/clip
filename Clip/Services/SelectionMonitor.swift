import AppKit
import ApplicationServices

/// Detects a text selection in any other app by watching for a drag-select or
/// multi-click. Tries reading the selection directly via the Accessibility API
/// first (a passive read, no synthetic input); if the focused app doesn't
/// expose that, falls back to simulating Cmd-C and diffing the pasteboard.
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
        DebugLog.write("start() — AXIsProcessTrusted=\(AXIsProcessTrusted())")
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        DebugLog.write("start() — monitor installed=\(monitor != nil)")
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
            guard let downLocation = mouseDownLocation else {
                DebugLog.write("mouseUp with no tracked mouseDown — ignoring")
                return
            }
            let upLocation = NSEvent.mouseLocation
            let distance = hypot(upLocation.x - downLocation.x, upLocation.y - downLocation.y)
            let dragged = distance > 4
            let multiClick = mouseDownClickCount >= 2
            mouseDownLocation = nil
            let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
            DebugLog.write("mouseUp in \(frontApp) — distance=\(distance) clickCount=\(mouseDownClickCount) dragged=\(dragged) multiClick=\(multiClick)")
            guard dragged || multiClick else { return }
            // Give the target app a brief moment to finish committing its selection
            // state before reading/copying it — some apps (e.g. Electron-based ones)
            // finalize selection asynchronously relative to the raw mouse event.
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
            DebugLog.write("captureSelection — skipped, frontmost is Clip itself")
            return
        }

        if let axText = readSelectionViaAX() {
            DebugLog.write("captureSelection — got selection via Accessibility API, length=\(axText.count)")
            emit(text: axText, sourceApp: NSWorkspace.shared.frontmostApplication?.localizedName, at: point)
            return
        }

        DebugLog.write("captureSelection — AX read empty, falling back to simulated Cmd-C")
        let priorChangeCount = NSPasteboard.general.changeCount
        DebugLog.write("captureSelection — priorChangeCount=\(priorChangeCount) AXIsProcessTrusted=\(AXIsProcessTrusted())")
        postCmdC()
        pollForChange(priorChangeCount: priorChangeCount, attemptsLeft: 12, point: point)
    }

    /// Asks the currently focused UI element directly for its selected text —
    /// a passive Accessibility API read, no synthetic input involved.
    private func readSelectionViaAX() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedElement = focusedRef else {
            return nil
        }
        // swiftlint:disable:next force_cast
        let element = focusedElement as! AXUIElement

        var selectedRef: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedRef) == .success,
              let text = selectedRef as? String else {
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func pollForChange(priorChangeCount: Int, attemptsLeft: Int, point: NSPoint) {
        let pasteboard = NSPasteboard.general
        if pasteboard.changeCount != priorChangeCount {
            let newString = pasteboard.string(forType: .string)
            DebugLog.write("pollForChange — pasteboard changed, string=\(String((newString ?? "nil").prefix(40)))")
            guard let text = newString?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                DebugLog.write("pollForChange — trimmed string was empty, not showing popup")
                return
            }
            emit(text: text, sourceApp: NSWorkspace.shared.frontmostApplication?.localizedName, at: point)
            return
        }

        guard attemptsLeft > 0 else {
            DebugLog.write("pollForChange — gave up after all attempts, pasteboard never changed")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            self?.pollForChange(priorChangeCount: priorChangeCount, attemptsLeft: attemptsLeft - 1, point: point)
        }
    }

    private func emit(text: String, sourceApp: String?, at point: NSPoint) {
        let selection = ClipSelection(text: text, kind: classify(text), sourceApp: sourceApp)
        onSelection?(selection, point)
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
