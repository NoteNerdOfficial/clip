import AppKit
import ApplicationServices

/// Detects a text selection in any other app by watching for a drag-select or
/// multi-click, then tries reading it back via several methods, roughly in
/// order of least likely to be restricted: the system Find pasteboard, System
/// Events, in-process Accessibility API, then simulating Cmd-C as a last resort.
@MainActor
final class SelectionMonitor {
    static let shared = SelectionMonitor()

    private var monitor: Any?
    private var mouseDownLocation: NSPoint?
    private var mouseDownClickCount: Int = 0
    private var mouseDownFindChangeCount: Int = 0

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
            mouseDownFindChangeCount = NSPasteboard(name: .find).changeCount
        case .leftMouseUp:
            guard let downLocation = mouseDownLocation else {
                DebugLog.write("mouseUp with no tracked mouseDown — ignoring")
                return
            }
            let upLocation = NSEvent.mouseLocation
            let distance = hypot(upLocation.x - downLocation.x, upLocation.y - downLocation.y)
            let dragged = distance > 4
            let multiClick = mouseDownClickCount >= 2
            let findChangeCountAtMouseDown = mouseDownFindChangeCount
            mouseDownLocation = nil
            let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
            DebugLog.write("mouseUp in \(frontApp) — distance=\(distance) clickCount=\(mouseDownClickCount) dragged=\(dragged) multiClick=\(multiClick)")
            guard dragged || multiClick else { return }
            // Give the target app a brief moment to finish committing its selection
            // state before reading/copying it — some apps (e.g. Electron-based ones)
            // finalize selection asynchronously relative to the raw mouse event.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.captureSelection(at: upLocation, findChangeCountAtMouseDown: findChangeCountAtMouseDown)
            }
        default:
            break
        }
    }

    private func captureSelection(at point: NSPoint, findChangeCountAtMouseDown: Int) {
        // Don't trigger on our own popup / windows.
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier {
            DebugLog.write("captureSelection — skipped, frontmost is Clip itself")
            return
        }

        let sourceApp = NSWorkspace.shared.frontmostApplication?.localizedName
        let frontBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        // Tried in order, least privileged / least likely to be blocked first:
        // 0. In Chrome specifically: ask Chrome to run window.getSelection()
        //    directly in the page via its own AppleScript "execute javascript"
        //    command — confirmed to be how PopClip does it there (Automation
        //    permission scoped to Google Chrome.app specifically, no System
        //    Events, no Accessibility). Requires Chrome's View > Developer >
        //    "Allow JavaScript from Apple Events" to be turned on.
        // 1. Read the system Find pasteboard — a plain pasteboard (same trust
        //    level as the regular clipboard, no special permission at all) that
        //    AppKit and modern Chromium text views keep in sync with the current
        //    selection as you select it, no keystroke needed.
        // 2. Ask System Events (a separate, Apple-signed process, gated by the
        //    Automation permission) to read the selection on our behalf.
        // 3. Read it directly in-process via the Accessibility API.
        // 4. Simulate Cmd-C and diff the pasteboard.
        if frontBundleID == "com.google.Chrome", let chromeText = readSelectionViaChromeJS() {
            DebugLog.write("captureSelection — got selection via Chrome JS execute, length=\(chromeText.count)")
            emit(text: chromeText, sourceApp: sourceApp, at: point)
            return
        }

        let findPasteboard = NSPasteboard(name: .find)
        if findPasteboard.changeCount != findChangeCountAtMouseDown,
           let text = findPasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            DebugLog.write("captureSelection — got selection via Find pasteboard, length=\(text.count)")
            emit(text: text, sourceApp: sourceApp, at: point)
            return
        }

        readSelectionViaSystemEvents { [weak self] systemEventsText in
            guard let self else { return }
            if let systemEventsText {
                DebugLog.write("captureSelection — got selection via System Events, length=\(systemEventsText.count)")
                self.emit(text: systemEventsText, sourceApp: sourceApp, at: point)
                return
            }

            if let axText = self.readSelectionViaAX() {
                DebugLog.write("captureSelection — got selection via in-process AX, length=\(axText.count)")
                self.emit(text: axText, sourceApp: sourceApp, at: point)
                return
            }

            DebugLog.write("captureSelection — Find pasteboard, System Events, and AX all empty, falling back to simulated Cmd-C")
            let priorChangeCount = NSPasteboard.general.changeCount
            DebugLog.write("captureSelection — priorChangeCount=\(priorChangeCount) AXIsProcessTrusted=\(AXIsProcessTrusted())")
            self.postCmdC()
            self.pollForChange(priorChangeCount: priorChangeCount, attemptsLeft: 12, point: point)
        }
    }

    /// Asks System Events — a separate, Apple-signed process, gated by the
    /// Automation permission rather than Accessibility — to read the focused
    /// element's selected text on our behalf via JXA. Runs off the main thread;
    /// completion is called back on the main actor.
    private func readSelectionViaSystemEvents(completion: @escaping (String?) -> Void) {
        let script = """
        function run() {
          const systemEvents = Application("System Events");
          const processes = systemEvents.processes.whose({ frontmost: true });
          if (processes.length === 0) return "";
          try {
            const focused = processes[0].attributes.byName("AXFocusedUIElement").value();
            const text = focused.attributes.byName("AXSelectedText").value();
            return text || "";
          } catch (e) {
            return "";
          }
        }
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", script]
        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = Pipe()

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try process.run()
            } catch {
                DebugLog.write("readSelectionViaSystemEvents — failed to launch osascript: \(error)")
                DispatchQueue.main.async { completion(nil) }
                return
            }
            process.waitUntilExit()
            let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                completion(text?.isEmpty == false ? text : nil)
            }
        }
    }

    /// Asks Chrome to run `window.getSelection().toString()` in the active tab
    /// via its own AppleScript "execute javascript" command. Requires Chrome's
    /// View > Developer > "Allow JavaScript from Apple Events" to be enabled;
    /// returns nil (not an error) if that's off, so callers fall through cleanly.
    private func readSelectionViaChromeJS() -> String? {
        let script = """
        function run() {
          try {
            const chrome = Application("Google Chrome");
            const win = chrome.windows[0];
            if (!win) return "";
            const result = win.activeTab.execute({ javascript: "window.getSelection().toString()" });
            return result || "";
          } catch (e) {
            return "";
          }
        }
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", script]
        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            DebugLog.write("readSelectionViaChromeJS — failed to launch osascript: \(error)")
            return nil
        }
        process.waitUntilExit()
        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
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
