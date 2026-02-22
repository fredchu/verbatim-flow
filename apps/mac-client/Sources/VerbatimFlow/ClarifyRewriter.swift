import Foundation

struct ClarifyRewriteResult: Sendable {
    let text: String
    let model: String
    let provider: String
}

enum ClarifyRewriter {
    private struct ClarifyTransportConfig: Sendable {
        let provider: String
        let model: String
        let endpoint: String
        let apiKey: String
        let extraHeaders: [String]
        let openRouterProviderSort: String?
    }

    static func rewrite(text: String, localeIdentifier: String) throws -> ClarifyRewriteResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ClarifyRewriteResult(text: "", model: "", provider: "")
        }

        let env = ProcessInfo.processInfo.environment
        let fileValues = OpenAISettings.loadValues()
        let transport = try resolvedClarifyTransport(environment: env, fileValues: fileValues)

        let systemPrompt = """
You are VerbatimFlow Clarify mode.
Rewrite spoken dictation into clear written text.
Rules:
- Keep original meaning, facts, numbers, proper nouns, and intent.
- Do not add new information.
- Remove filler words and obvious repetition.
- Keep the same language as the input (Chinese stays Chinese; mixed-language stays mixed).
- If Chinese or Chinese-dominant, use full-width Chinese punctuation (，。！？；：).
- Output plain text only. No markdown. No explanation.
"""

        var payload: [String: Any] = [
            "model": transport.model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": "locale=\(localeIdentifier)\n\n" + trimmed]
            ]
        ]
        if modelSupportsTemperature(transport.model) {
            payload["temperature"] = 0.1
        }
        if transport.provider == "openrouter", let providerSort = transport.openRouterProviderSort {
            payload["provider"] = ["sort": providerSort]
        }
        let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [])
        guard let endpointURL = URL(string: transport.endpoint) else {
            throw AppError.openAIClarifyFailed("Invalid clarify endpoint: \(transport.endpoint)")
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.httpBody = payloadData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(transport.apiKey)", forHTTPHeaderField: "Authorization")
        for header in transport.extraHeaders {
            let parts = header.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let name = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty, !value.isEmpty {
                request.setValue(value, forHTTPHeaderField: name)
            }
        }

        let (outputData, statusCode) = try performRequest(request, timeout: 60)
        if !(200...299).contains(statusCode) {
            let details = parseErrorMessage(from: outputData)
            throw AppError.openAIClarifyFailed(
                details.isEmpty ? "HTTP \(statusCode)" : details
            )
        }

        guard
            let payload = try? JSONSerialization.jsonObject(with: outputData, options: []) as? [String: Any]
        else {
            let raw = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw AppError.openAIClarifyFailed("Unexpected response: \(raw)")
        }

        if let errorPayload = payload["error"] as? [String: Any],
           let message = errorPayload["message"] as? String,
           !message.isEmpty {
            throw AppError.openAIClarifyFailed(message)
        }

        guard
            let choices = payload["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw AppError.openAIClarifyFailed("Response has no choices.message.content field")
        }

        let rewritten = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if rewritten.isEmpty {
            throw AppError.openAIClarifyFailed("Clarify response is empty")
        }

        return ClarifyRewriteResult(
            text: rewritten,
            model: transport.model,
            provider: transport.provider
        )
    }

    private static func resolvedClarifyTransport(
        environment: [String: String],
        fileValues: [String: String]
    ) throws -> ClarifyTransportConfig {
        let providerRaw = (resolvedSetting(
            key: "VERBATIMFLOW_CLARIFY_PROVIDER",
            environment: environment,
            fileValues: fileValues
        ) ?? "openai").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let configuredModel = resolvedSetting(
            key: "VERBATIMFLOW_OPENAI_CLARIFY_MODEL",
            environment: environment,
            fileValues: fileValues
        )

        let allowInsecure = parseBooleanSetting(resolvedSetting(
            key: "VERBATIMFLOW_ALLOW_INSECURE_OPENAI_BASE_URL",
            environment: environment,
            fileValues: fileValues
        ))

        switch providerRaw {
        case "openai":
            let apiKey = resolvedSetting(
                key: "VERBATIMFLOW_CLARIFY_API_KEY",
                environment: environment,
                fileValues: fileValues
            ) ?? resolvedSetting(
                key: "OPENAI_API_KEY",
                environment: environment,
                fileValues: fileValues
            )
            guard let apiKey, !apiKey.isEmpty else {
                throw AppError.openAIAPIKeyMissing
            }

            let rawBaseURL = resolvedSetting(
                key: "VERBATIMFLOW_CLARIFY_BASE_URL",
                environment: environment,
                fileValues: fileValues
            ) ?? resolvedSetting(
                key: "VERBATIMFLOW_OPENAI_BASE_URL",
                environment: environment,
                fileValues: fileValues
            ) ?? "https://api.openai.com/v1"

            return ClarifyTransportConfig(
                provider: "openai",
                model: configuredModel ?? "gpt-4o-mini",
                endpoint: try resolvedChatCompletionsEndpoint(rawBaseURL: rawBaseURL, allowInsecure: allowInsecure),
                apiKey: apiKey,
                extraHeaders: [],
                openRouterProviderSort: nil
            )

        case "openrouter":
            let apiKey = resolvedSetting(
                key: "VERBATIMFLOW_CLARIFY_API_KEY",
                environment: environment,
                fileValues: fileValues
            ) ?? resolvedSetting(
                key: "OPENROUTER_API_KEY",
                environment: environment,
                fileValues: fileValues
            )
            guard let apiKey, !apiKey.isEmpty else {
                throw AppError.openAIClarifyFailed(
                    "OPENROUTER_API_KEY is missing. Set OPENROUTER_API_KEY or VERBATIMFLOW_CLARIFY_API_KEY."
                )
            }

            let rawBaseURL = resolvedSetting(
                key: "VERBATIMFLOW_CLARIFY_BASE_URL",
                environment: environment,
                fileValues: fileValues
            ) ?? "https://openrouter.ai/api/v1"

            var extraHeaders: [String] = []
            if let siteURL = resolvedSetting(
                key: "VERBATIMFLOW_OPENROUTER_SITE_URL",
                environment: environment,
                fileValues: fileValues
            ), !siteURL.isEmpty {
                extraHeaders.append("HTTP-Referer: \(siteURL)")
            }
            if let appName = resolvedSetting(
                key: "VERBATIMFLOW_OPENROUTER_APP_NAME",
                environment: environment,
                fileValues: fileValues
            ), !appName.isEmpty {
                extraHeaders.append("X-Title: \(appName)")
            } else {
                extraHeaders.append("X-Title: VerbatimFlow")
            }

            let providerSortRaw = resolvedSetting(
                key: "VERBATIMFLOW_OPENROUTER_PROVIDER_SORT",
                environment: environment,
                fileValues: fileValues
            )?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let providerSort: String?
            switch providerSortRaw {
            case "latency", "throughput", "price":
                providerSort = providerSortRaw
            case .none, .some(""):
                providerSort = nil
            case .some(let value):
                throw AppError.openAIClarifyFailed(
                    "Invalid VERBATIMFLOW_OPENROUTER_PROVIDER_SORT=\(value). Use price, latency, or throughput."
                )
            }

            return ClarifyTransportConfig(
                provider: "openrouter",
                model: configuredModel ?? "openai/gpt-4o-mini",
                endpoint: try resolvedChatCompletionsEndpoint(rawBaseURL: rawBaseURL, allowInsecure: allowInsecure),
                apiKey: apiKey,
                extraHeaders: extraHeaders,
                openRouterProviderSort: providerSort
            )

        default:
            throw AppError.openAIClarifyFailed(
                "Unsupported VERBATIMFLOW_CLARIFY_PROVIDER=\(providerRaw). Use openai or openrouter."
            )
        }
    }

    private static func resolvedSetting(
        key: String,
        environment: [String: String],
        fileValues: [String: String]
    ) -> String? {
        if let envValue = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !envValue.isEmpty {
            return envValue
        }
        if let fileValue = fileValues[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !fileValue.isEmpty {
            return fileValue
        }
        return nil
    }

    private static func parseBooleanSetting(_ rawValue: String?) -> Bool {
        guard let rawValue else {
            return false
        }

        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
        }
    }

    private static func modelSupportsTemperature(_ model: String) -> Bool {
        let lowered = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalized = String(lowered.split(separator: "/").last ?? Substring(lowered))
        if normalized == "gpt-5" || normalized.hasPrefix("gpt-5-") {
            return false
        }
        return true
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
            throw AppError.openAIClarifyFailed("Request timed out after \(Int(timeout))s")
        }

        if let responseError {
            throw AppError.openAIClarifyFailed(responseError.localizedDescription)
        }

        guard let responseCode else {
            throw AppError.openAIClarifyFailed("No HTTP response")
        }

        return (responseData ?? Data(), responseCode)
    }

    private static func parseErrorMessage(from payload: Data) -> String {
        if let parsed = try? JSONSerialization.jsonObject(with: payload, options: []) as? [String: Any],
           let errorPayload = parsed["error"] as? [String: Any],
           let message = errorPayload["message"] as? String {
            return message.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return String(data: payload, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func resolvedChatCompletionsEndpoint(rawBaseURL: String, allowInsecure: Bool) throws -> String {
        guard let baseURL = URL(string: rawBaseURL), let scheme = baseURL.scheme?.lowercased(), !scheme.isEmpty else {
            throw AppError.openAIClarifyFailed("Invalid clarify base URL: \(rawBaseURL)")
        }

        if scheme != "https" {
            guard allowInsecure else {
                throw AppError.openAIClarifyFailed(
                    "Clarify base URL must use https:// (set VERBATIMFLOW_ALLOW_INSECURE_OPENAI_BASE_URL=1 only for local dev)."
                )
            }
            RuntimeLogger.log("[clarify] insecure base url enabled via VERBATIMFLOW_ALLOW_INSECURE_OPENAI_BASE_URL")
        }

        return baseURL
            .appendingPathComponent("chat")
            .appendingPathComponent("completions")
            .absoluteString
    }
}
