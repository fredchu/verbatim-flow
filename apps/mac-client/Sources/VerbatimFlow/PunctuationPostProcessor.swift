import Foundation

enum PunctuationPostProcessor {
    private static let timeoutSeconds: Double = 60  // generous for first-time model download

    /// Run sherpa-onnx punctuation + terminology correction via Python script.
    /// Returns processed text, or throws on failure.
    /// When `skipPunctuation` is true, only terminology correction runs (for LLM modes that add their own punctuation).
    static func process(text: String, language: String, skipPunctuation: Bool = false) throws -> String {
        guard !text.isEmpty else { return "" }

        guard let scriptURL = PythonScriptRunner.resolveScript(named: "postprocess_asr.py") else {
            throw AppError.postprocessScriptNotFound
        }

        guard let pythonURL = PythonScriptRunner.resolvePythonExecutable(scriptURL: scriptURL) else {
            throw AppError.pythonRuntimeNotFound
        }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = pythonURL
        var args = [
            scriptURL.path,
            "--language", language
        ]
        if skipPunctuation {
            args.append("--no-punctuation")
        }
        process.arguments = args
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Write stdin
        let inputData = text.data(using: .utf8) ?? Data()
        inputPipe.fileHandleForWriting.write(inputData)
        inputPipe.fileHandleForWriting.closeFile()

        let (outputText, errorText) = try PythonScriptRunner.runSubprocess(
            process,
            outputPipe: outputPipe,
            errorPipe: errorPipe
        )

        if process.terminationStatus != 0 {
            let details = errorText.isEmpty ? outputText : errorText
            throw AppError.postprocessFailed(details)
        }

        let result = outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? text : result
    }
}
