import Foundation

enum PythonScriptRunner {
    /// Locate a Python script by name, searching source tree and bundle paths.
    static func resolveScript(named filename: String) -> URL? {
        let fileManager = FileManager.default
        let currentDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        let bundleDirectory = Bundle.main.bundleURL.deletingLastPathComponent()

        var candidates = [URL]()

        // Prefer source-tree paths so that the adjacent .venv is found by
        // resolvePythonExecutable.  Bundle resource copy is the last resort.

        // executable-relative: Contents/MacOS/../../../../python/scripts → source tree
        if let execURL = Bundle.main.executableURL {
            let execDir = execURL.deletingLastPathComponent() // Contents/MacOS
            candidates.append(
                execDir.appendingPathComponent("../../../../python/scripts/\(filename)")
            )
        }

        candidates.append(contentsOf: [
            currentDirectory.appendingPathComponent("python/scripts/\(filename)"),
            currentDirectory.appendingPathComponent("apps/mac-client/python/scripts/\(filename)"),
            bundleDirectory.appendingPathComponent("../python/scripts/\(filename)"),
            bundleDirectory.appendingPathComponent("python/scripts/\(filename)")
        ])

        // Bundle resource copy (no .venv alongside, used as fallback)
        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(
                resourceURL.appendingPathComponent("python/scripts/\(filename)")
            )
        }

        let resolved = candidates.map { $0.standardizedFileURL }

        for candidate in resolved where fileManager.fileExists(atPath: candidate.path) {
            return candidate
        }

        return nil
    }

    /// Find the Python executable (venv preferred, system fallback).
    static func resolvePythonExecutable(scriptURL: URL) -> URL? {
        let fileManager = FileManager.default

        var candidates = [URL]()

        // 1. venv adjacent to the script's python root (works in source tree)
        let pythonRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
        candidates.append(pythonRoot.appendingPathComponent(".venv/bin/python"))

        // 2. exec-relative: walk from Contents/MacOS back to source tree
        if let execURL = Bundle.main.executableURL {
            let macosDir = execURL.deletingLastPathComponent()
            candidates.append(
                macosDir.appendingPathComponent("../../../../python/.venv/bin/python")
            )
        }

        // 3. User-configured Python path via environment variable
        if let envPath = ProcessInfo.processInfo.environment["VERBATIMFLOW_PYTHON_PATH"] {
            candidates.append(URL(fileURLWithPath: envPath))
        }

        for candidate in candidates {
            let resolved = candidate.standardizedFileURL
            if fileManager.fileExists(atPath: resolved.path) {
                return resolved
            }
        }

        let systemPython = URL(fileURLWithPath: "/usr/bin/python3")
        if fileManager.fileExists(atPath: systemPython.path) {
            return systemPython
        }

        return nil
    }

    /// Run a subprocess, draining stdout/stderr to avoid pipe buffer deadlock.
    static func runSubprocess(
        _ process: Process,
        outputPipe: Pipe,
        errorPipe: Pipe
    ) throws -> (stdout: String, stderr: String) {
        let lock = NSLock()
        var outputData = Data()
        var errorData = Data()

        let outputHandle = outputPipe.fileHandleForReading
        let errorHandle = errorPipe.fileHandleForReading

        outputHandle.readabilityHandler = { handle in
            let data = handle.availableData
            lock.lock()
            outputData.append(data)
            lock.unlock()
        }
        errorHandle.readabilityHandler = { handle in
            let data = handle.availableData
            lock.lock()
            errorData.append(data)
            lock.unlock()
        }

        try process.run()
        process.waitUntilExit()

        outputHandle.readabilityHandler = nil
        errorHandle.readabilityHandler = nil

        lock.lock()
        outputData.append(outputHandle.readDataToEndOfFile())
        errorData.append(errorHandle.readDataToEndOfFile())
        lock.unlock()

        let stdout = String(data: outputData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stderr = String(data: errorData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return (stdout, stderr)
    }
}
