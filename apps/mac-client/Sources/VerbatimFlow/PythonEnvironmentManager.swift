import CryptoKit
import Foundation
import os.log

enum PythonEnvStatus: Sendable {
    case ready
    case setting(String)
    case failed(String)
    case noPython
}

enum PythonEnvironmentManager {
    private static let logger = Logger(
        subsystem: "com.verbatimflow.app",
        category: "PythonEnv"
    )

    static var appSupportVenvDir: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("VerbatimFlow")
            .appendingPathComponent(".venv")
    }

    static var appSupportPythonURL: URL {
        appSupportVenvDir.appendingPathComponent("bin/python")
    }

    static func findSystemPython() -> URL? {
        // Prefer Homebrew Python (newer, has MLX support) over system Python
        let candidates = [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3"
        ]
        for path in candidates {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    static func bundledRequirementsURL() -> URL? {
        Bundle.main.resourceURL?
            .appendingPathComponent("python/requirements.txt")
    }

    static func isReady() -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: appSupportPythonURL.path) else {
            return false
        }
        guard let reqURL = bundledRequirementsURL(),
              fm.fileExists(atPath: reqURL.path) else {
            return false
        }
        guard let currentHash = sha256Hex(of: reqURL),
              let saved = storedHash() else {
            return false
        }
        return currentHash == saved
    }

    static func ensureReady(onStatus: @escaping @Sendable (PythonEnvStatus) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            if isReady() {
                logger.info("Python venv already up-to-date")
                onStatus(.ready)
                return
            }

            guard let systemPython = findSystemPython() else {
                logger.error("No system Python found")
                onStatus(.noPython)
                return
            }
            logger.info("Using system Python: \(systemPython.path)")

            let venvDir = appSupportVenvDir
            let parentDir = venvDir.deletingLastPathComponent()
            let fm = FileManager.default

            do {
                if !fm.fileExists(atPath: parentDir.path) {
                    onStatus(.setting("Creating application support directory..."))
                    try fm.createDirectory(
                        at: parentDir, withIntermediateDirectories: true
                    )
                }
            } catch {
                let msg = "Failed to create directory: \(error.localizedDescription)"
                logger.error("\(msg)")
                onStatus(.failed(msg))
                return
            }

            // Create venv
            onStatus(.setting("Creating Python virtual environment..."))
            let (venvExit, _, venvErr) = runProcess(
                systemPython.path, arguments: ["-m", "venv", venvDir.path]
            )
            if venvExit != 0 {
                let msg = "venv creation failed: \(venvErr)"
                logger.error("\(msg)")
                onStatus(.failed(msg))
                return
            }

            // Install requirements
            guard let reqURL = bundledRequirementsURL(),
                  fm.fileExists(atPath: reqURL.path) else {
                logger.warning("No bundled requirements.txt found, skipping pip install")
                onStatus(.ready)
                return
            }

            onStatus(.setting("Installing Python dependencies..."))
            let pipPath = venvDir
                .appendingPathComponent("bin/pip").path
            let (pipExit, _, pipErr) = runProcess(
                pipPath, arguments: ["install", "-r", reqURL.path]
            )
            if pipExit != 0 {
                let msg = "pip install failed: \(pipErr)"
                logger.error("\(msg)")
                onStatus(.failed(msg))
                return
            }

            // Write hash
            if let hash = sha256Hex(of: reqURL) {
                writeHash(hash)
            }

            logger.info("Python venv ready")
            onStatus(.ready)
        }
    }

    // MARK: - Private

    private static func sha256Hex(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static var hashFileURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("VerbatimFlow")
            .appendingPathComponent(".requirements_hash")
    }

    private static func storedHash() -> String? {
        try? String(contentsOf: hashFileURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func writeHash(_ hash: String) {
        try? hash.write(to: hashFileURL, atomically: true, encoding: .utf8)
    }

    private static func runProcess(
        _ executablePath: String,
        arguments: [String]
    ) -> (exitCode: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        // Clean environment to avoid venv contamination
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "VIRTUAL_ENV")
        env.removeValue(forKey: "PYTHONHOME")
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        // Drain pipes concurrently to avoid deadlock when output exceeds buffer
        let lock = NSLock()
        var outData = Data()
        var errData = Data()
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            lock.lock()
            outData.append(data)
            lock.unlock()
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            lock.lock()
            errData.append(data)
            lock.unlock()
        }

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            return (-1, "", error.localizedDescription)
        }

        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil

        lock.lock()
        outData.append(outPipe.fileHandleForReading.readDataToEndOfFile())
        errData.append(errPipe.fileHandleForReading.readDataToEndOfFile())
        lock.unlock()

        let stdout = String(data: outData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stderr = String(data: errData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (process.terminationStatus, stdout, stderr)
    }
}
