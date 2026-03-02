import Foundation

struct LocalRewriteResult: Sendable {
    let text: String
    let model: String
}

enum LocalRewriter {
    private static let defaultBaseURL = "http://localhost:11434"
    private static let defaultModel = "qwen3:8b"

    static func rewrite(text: String, localeIdentifier: String) throws -> LocalRewriteResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return LocalRewriteResult(text: "", model: "")
        }

        let env = ProcessInfo.processInfo.environment
        let baseURL = env["VERBATIMFLOW_OLLAMA_BASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? defaultBaseURL
        let model = env["VERBATIMFLOW_LOCAL_REWRITE_MODEL"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? defaultModel

        let systemPrompt = """
            你是 VerbatimFlow 本地校正模式。
            將語音轉錄的口語文字改寫為通順的書面語。
            規則：
            - 保持原意、事實、數字、專有名詞不變。
            - 不添加原文沒有的資訊。
            - 去除口語贅詞（嗯、啊、然後、就是說、對、那個）和明顯重複。
            - 保持與輸入相同的語言（中文維持中文，中英混合維持混合）。
            - 使用台灣繁體中文用語和全形標點符號（，。！？；：）。
            - 僅輸出改寫後的純文字，不要 markdown，不要解釋。 /no_think
            """

        let payload: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": "locale=\(localeIdentifier)\n\n" + trimmed]
            ],
            "stream": false,
            "keep_alive": "5m",
            "options": [
                "temperature": 0.1,
                "num_predict": 2048
            ]
        ]

        let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [])

        guard let endpointURL = URL(string: baseURL)?.appendingPathComponent("api/chat") else {
            throw AppError.localRewriteFailed("Invalid Ollama base URL: \(baseURL)")
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.httpBody = payloadData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (responseData, statusCode) = try performRequest(request, timeout: 30)

        if !(200...299).contains(statusCode) {
            let errorText = String(data: responseData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if statusCode == 0 || errorText.contains("connect") || errorText.contains("Connection refused") {
                throw AppError.localRewriteFailed("Cannot connect to Ollama. Please start Ollama first.")
            }
            if errorText.contains("not found") || errorText.contains("no such model") {
                throw AppError.localRewriteFailed("Model \(model) not found. Run: ollama pull \(model)")
            }
            throw AppError.localRewriteFailed("HTTP \(statusCode): \(errorText)")
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: responseData, options: []) as? [String: Any],
            let message = json["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            let raw = String(data: responseData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw AppError.localRewriteFailed("Unexpected response: \(raw)")
        }

        let rewritten = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if rewritten.isEmpty {
            throw AppError.localRewriteFailed("Ollama returned empty response")
        }

        return LocalRewriteResult(text: rewritten, model: model)
    }

    private static func performRequest(_ request: URLRequest, timeout: TimeInterval) throws -> (Data, Int) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: config)

        let semaphore = DispatchSemaphore(value: 0)
        var responseData: Data?
        var responseCode: Int?
        var responseError: Error?

        let task = session.dataTask(with: request) { data, response, error in
            responseData = data
            responseCode = (response as? HTTPURLResponse)?.statusCode
            responseError = error
            semaphore.signal()
        }
        task.resume()

        let waitResult = semaphore.wait(timeout: .now() + timeout + 1)
        session.invalidateAndCancel()

        if waitResult == .timedOut {
            task.cancel()
            throw AppError.localRewriteFailed("Request timed out after \(Int(timeout))s")
        }

        if let responseError {
            let desc = responseError.localizedDescription
            if desc.contains("Could not connect") || desc.contains("Connection refused") {
                throw AppError.localRewriteFailed("Cannot connect to Ollama at \(request.url?.host ?? "localhost"):11434. Please start Ollama first.")
            }
            throw AppError.localRewriteFailed(desc)
        }

        guard let responseCode else {
            throw AppError.localRewriteFailed("No HTTP response from Ollama")
        }

        return (responseData ?? Data(), responseCode)
    }
}
