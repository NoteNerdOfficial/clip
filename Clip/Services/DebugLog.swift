import Foundation

/// Plain-file diagnostic log, written to `~/Library/Application Support/Clip/debug.log`.
/// NSLog/unified-log output isn't reliably reaching Console.app or `log stream` for this
/// app (verified independent of any managed-Mac restrictions), so this is the trustworthy
/// way to see what Clip is actually doing.
enum DebugLog {
    private static let fileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Clip/debug.log")
    }()

    static func write(_ message: String) {
        let line = "\(Date()) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        let fm = FileManager.default
        try? fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        if fm.fileExists(atPath: fileURL.path), let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
        } else {
            try? data.write(to: fileURL)
        }
    }
}
