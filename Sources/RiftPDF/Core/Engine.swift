import Foundation

/// Bridge to the bundled Python engine. Every call streams progress back on the
/// main actor and resolves with the engine's `result` payload.
final class Engine: @unchecked Sendable {

    static let shared = Engine()

    struct Failure: LocalizedError {
        let message: String
        let detail: String?
        var errorDescription: String? { message }
        var isLibreOfficeMissing: Bool { message == "LIBREOFFICE_UNAVAILABLE" }
    }

    struct Capabilities {
        var pymupdf = ""
        var pikepdf = ""
        var libreOffice = false
        var ghostscript = false
        var qpdf = false
        var ready = false
    }

    private(set) var capabilities = Capabilities()

    // MARK: - locating the engine

    private lazy var location: (python: URL, script: URL)? = {
        var roots: [URL] = []
        if let env = ProcessInfo.processInfo.environment["RIFTPDF_ENGINE"] {
            roots.append(URL(fileURLWithPath: env))
        }
        if let res = Bundle.main.resourceURL {
            roots.append(res.appendingPathComponent("engine"))
        }
        // running straight from the checkout during development
        roots.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("engine"))
        roots.append(URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Desktop/RiftPDF/engine"))

        for root in roots {
            let script = root.appendingPathComponent("riftpdf_engine.py")
            let python = root.appendingPathComponent(".venv/bin/python3")
            let python2 = root.appendingPathComponent(".venv/bin/python")
            guard FileManager.default.fileExists(atPath: script.path) else { continue }
            for candidate in [python, python2] where FileManager.default.isExecutableFile(atPath: candidate.path) {
                return (candidate, script)
            }
        }
        return nil
    }()

    var isAvailable: Bool { location != nil }

    var engineRootDescription: String {
        location.map { $0.script.deletingLastPathComponent().path } ?? "not found"
    }

    // MARK: - running

    @discardableResult
    func run(_ command: String,
             _ payload: [String: Any],
             onProgress: (@Sendable @MainActor (Double, String) -> Void)? = nil) async throws -> [String: Any] {

        guard let location else {
            throw Failure(message: "The processing engine is missing.",
                          detail: "Expected riftpdf_engine.py and a .venv beside the app. Run setup.sh to rebuild it.")
        }

        // Payloads can be large (OCR word boxes, redaction lists) so hand them
        // over in a file rather than on the command line.
        let payloadURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("riftpdf-\(UUID().uuidString).json")
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        try data.write(to: payloadURL)
        defer { try? FileManager.default.removeItem(at: payloadURL) }

        let process = Process()
        process.executableURL = location.python
        process.arguments = [location.script.path, command, payloadURL.path]
        process.currentDirectoryURL = location.script.deletingLastPathComponent()
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        env["PYTHONIOENCODING"] = "utf-8"
        process.environment = env

        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err

        return try await withCheckedThrowingContinuation { continuation in
            let box = ResultBox()

            out.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                box.buffer.append(chunk)
                while let range = box.buffer.firstRange(of: Data([0x0A])) {
                    let line = box.buffer.subdata(in: box.buffer.startIndex..<range.lowerBound)
                    box.buffer.removeSubrange(box.buffer.startIndex..<range.upperBound)
                    guard !line.isEmpty,
                          let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                          let type = obj["type"] as? String else { continue }
                    switch type {
                    case "progress":
                        if let onProgress {
                            let v = obj["value"] as? Double ?? 0
                            let m = obj["message"] as? String ?? ""
                            Task { @MainActor in onProgress(v, m) }
                        }
                    case "result":
                        box.result = obj
                    case "error":
                        box.error = Failure(message: obj["message"] as? String ?? "Unknown engine error",
                                            detail: obj["detail"] as? String)
                    default: break
                    }
                }
            }

            process.terminationHandler = { proc in
                out.fileHandleForReading.readabilityHandler = nil
                let stderrText = String(data: err.fileHandleForReading.readDataToEndOfFile(),
                                        encoding: .utf8) ?? ""
                if let error = box.error {
                    continuation.resume(throwing: error)
                } else if let result = box.result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: Failure(
                        message: "The engine stopped without producing a result (exit \(proc.terminationStatus)).",
                        detail: stderrText.isEmpty ? nil : String(stderrText.suffix(2000))))
                }
            }

            do { try process.run() }
            catch { continuation.resume(throwing: Failure(message: "Could not start the engine.",
                                                          detail: error.localizedDescription)) }
        }
    }

    private final class ResultBox: @unchecked Sendable {
        var buffer = Data()
        var result: [String: Any]?
        var error: Failure?
    }

    // MARK: - capability probe

    func probe() async {
        guard isAvailable else { return }
        if let out = try? await run("--selftest", [:]) {
            var caps = Capabilities()
            caps.pymupdf = out["pymupdf"] as? String ?? ""
            caps.pikepdf = out["pikepdf"] as? String ?? ""
            caps.libreOffice = out["libreoffice"] as? Bool ?? false
            caps.ghostscript = out["ghostscript"] as? Bool ?? false
            caps.qpdf = out["qpdf"] as? Bool ?? false
            caps.ready = out["ok"] as? Bool ?? false
            capabilities = caps
        }
    }
}
