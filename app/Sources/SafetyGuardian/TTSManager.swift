//
//  TTSManager.swift
//  SafetyGuardian
//
//  Text-to-Speech manager using ElevenLabs API
//

import Foundation

class TTSManager {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15.0  // TTS is fast, shorter timeout
        self.session = URLSession(configuration: config)
    }

    // MARK: - Main TTS Method

    func convertToSpeech(_ text: String) async throws -> Data {
        var lastError: Error?

        // Retry logic (2 attempts for TTS)
        for attempt in 0..<2 {
            do {
                let audioData = try await performTTS(text)
                return audioData
            } catch {
                lastError = error
                print("TTS attempt \(attempt + 1) failed: \(error.localizedDescription)")

                if attempt < 1 {
                    try await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second delay
                }
            }
        }

        throw lastError ?? SafetyGuardianError.apiError("TTS failed after retries")
    }

    // MARK: - Network Request

    private func performTTS(_ text: String) async throws -> Data {
        guard let url = AppConfiguration.ttsURL(voiceID: AppConfiguration.voiceID) else {
            throw SafetyGuardianError.invalidConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppConfiguration.elevenlabsAPIKey, forHTTPHeaderField: "xi-api-key")

        let ttsRequest = TTSRequest(
            text: text,
            modelId: AppConfiguration.ttsModel,
            voiceSettings: TTSRequest.VoiceSettings(
                stability: 0.5,
                similarityBoost: 0.5
            )
        )

        request.httpBody = try JSONEncoder().encode(ttsRequest)

        // Perform request
        let (data, response) = try await session.data(for: request)

        // Check HTTP status
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SafetyGuardianError.networkError(NSError(domain: "Invalid response", code: -1))
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SafetyGuardianError.apiError("TTS HTTP \(httpResponse.statusCode): \(errorMessage)")
        }

        return data
    }
}
