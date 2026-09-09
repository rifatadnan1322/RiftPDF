import Foundation

/// Appends to ~/Library/Logs/RiftPDF-diagnostic.log so a problem that only
/// happens on someone else's machine can still be diagnosed.
enum Diagnostic {
    private static let file: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs", isDirectory: true)
        return dir.appendingPathComponent("RiftPDF-diagnostic.log")
    }()

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    static func log(_ message: String) {
        let entry = "[\(stamp.string(from: Date()))] \(message)\n"
        guard let data = entry.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: file)
        }
    }

    static func size(_ path: String?) -> String {
        guard let path,
              let bytes = (try? FileManager.default.attributesOfItem(atPath: path)[.size]) as? Int
        else { return "n/a" }
        return "\(bytes)"
    }
}
