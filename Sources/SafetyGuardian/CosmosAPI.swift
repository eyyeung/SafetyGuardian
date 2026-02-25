//
//  CosmosAPI.swift
//  SafetyGuardian
//
//  API client for vLLM server (Cosmos-Reason2 inference)
//

import Foundation

class CosmosAPI {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = AppConfiguration.networkTimeout
        config.timeoutIntervalForResource = AppConfiguration.networkTimeout
        self.session = URLSession(configuration: config)
    }

    // MARK: - Main API Method

    func analyzeFrame(_ base64Image: String) async throws -> String {
        var lastError: Error?

        // Retry logic with exponential backoff
        for attempt in 0..<AppConfiguration.maxRetries {
            try Task.checkCancellation()
            do {
                let result = try await performAnalysis(base64Image)
                return result
            } catch {
                if error is CancellationError {
                    throw error
                }
                lastError = error
                print("Cosmos API attempt \(attempt + 1) failed: \(error.localizedDescription)")

                // Don't retry on last attempt
                if attempt < AppConfiguration.maxRetries - 1 {
                    let delay = AppConfiguration.retryDelay(attempt: attempt)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        // All retries failed
        throw lastError ?? SafetyGuardianError.apiError("Unknown error after retries")
    }

    // MARK: - Network Request

    private func performAnalysis(_ base64Image: String) async throws -> String {
        guard let url = AppConfiguration.chatCompletionsURL() else {
            throw SafetyGuardianError.invalidConfiguration
        }

        // Build request
        let request = buildRequest(url: url, base64Image: base64Image)

        // Perform request
        let (data, response) = try await session.data(for: request)

        // Check HTTP status
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SafetyGuardianError.networkError(NSError(domain: "Invalid response", code: -1))
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SafetyGuardianError.apiError("HTTP \(httpResponse.statusCode): \(errorMessage)")
        }

        // Parse response
        let cosmosResponse = try JSONDecoder().decode(CosmosResponse.self, from: data)

        guard let content = cosmosResponse.choices.first?.message.content else {
            throw SafetyGuardianError.decodingError
        }

        return content
    }

    // MARK: - Request Builder

    private func buildRequest(url: URL, base64Image: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let cosmosRequest = CosmosRequest(
            model: AppConfiguration.modelName,
            messages: [
                CosmosRequest.Message(
                    role: "system",
                    content: .text(AppConfiguration.systemPrompt)
                ),
                CosmosRequest.Message(
                    role: "user",
                    content: .multipart([
                        CosmosRequest.ContentPart(
                            type: "image_url",
                            text: nil,
                            imageUrl: CosmosRequest.ImageURL(
                                url: "data:image/jpeg;base64,\(base64Image)"
                            )
                        ),
                        CosmosRequest.ContentPart(
                            type: "text",
                            text: AppConfiguration.userPrompt,
                            imageUrl: nil
                        )
                    ])
                )
            ],
            maxTokens: AppConfiguration.maxTokens,
            temperature: AppConfiguration.temperature,
            extraBody: CosmosRequest.ExtraBody(loraName: "cosmos-safety")
        )

        request.httpBody = try? JSONEncoder().encode(cosmosRequest)

        return request
    }

    // MARK: - Health Check

    func checkHealth() async throws {
        guard let url = AppConfiguration.modelsURL() else {
            throw SafetyGuardianError.invalidConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SafetyGuardianError.networkError(NSError(domain: "Invalid response", code: -1))
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw SafetyGuardianError.apiError("HTTP \(httpResponse.statusCode)")
        }
    }
}
