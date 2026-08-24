import Foundation
import UserNotifications

/// Runs an extension's action.js via /usr/bin/osascript -l JavaScript (JXA, built into macOS).
/// The selection + resolved option values are passed as a single JSON-encoded argument.
enum ExtensionRunner {
    static func run(actionPath: String, payload: [String: Any]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", actionPath, jsonString]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            notifyFailure(message: "Couldn't launch action: \(error.localizedDescription)")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                DispatchQueue.main.async {
                    notifyFailure(message: message?.isEmpty == false ? message! : "Unknown error")
                }
            }
        }
    }

    private static func notifyFailure(message: String) {
        // Always visible in Console/log stream, independent of whether the user
        // granted notification permission (which the popup toast depends on).
        NSLog("[Clip] action failed: \(message)")

        let content = UNMutableNotificationContent()
        content.title = "Clip action failed"
        content.body = message
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
