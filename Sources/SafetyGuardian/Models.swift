//
//  Models.swift
//  SafetyGuardian
//
//  Data models for API requests and responses
//

import Foundation

// MARK: - Cosmos API Models

struct CosmosRequest: Codable {
    let model: String
    let messages: [Message]
    let maxTokens: Int
    let temperature: Float

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxTokens = "max_tokens"
        case temperature
    }

    struct Message: Codable {
        let role: String
        let content: MessageContent
    }

    enum MessageContent: Codable {
        case text(String)
        case multipart([ContentPart])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                self = .text(text)
            } else if let parts = try? container.decode([ContentPart].self) {
                self = .multipart(parts)
            } else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Invalid message content"
                    )
                )
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .text(let text):
                try container.encode(text)
            case .multipart(let parts):
                try container.encode(parts)
            }
        }
    }

    struct ContentPart: Codable {
        let type: String
        let text: String?
        let imageUrl: ImageURL?

        enum CodingKeys: String, CodingKey {
            case type
            case text
            case imageUrl = "image_url"
        }
    }

    struct ImageURL: Codable {
        let url: String
    }
}

struct CosmosResponse: Codable {
    let id: String
    let choices: [Choice]
    let usage: Usage?

    struct Choice: Codable {
        let message: Message
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }

    struct Message: Codable {
        let content: String
    }

    struct Usage: Codable {
        let totalTokens: Int

        enum CodingKeys: String, CodingKey {
            case totalTokens = "total_tokens"
        }
    }
}

// MARK: - ElevenLabs TTS Models

struct TTSRequest: Codable {
    let text: String
    let modelId: String
    let voiceSettings: VoiceSettings

    enum CodingKeys: String, CodingKey {
        case text
        case modelId = "model_id"
        case voiceSettings = "voice_settings"
    }

    struct VoiceSettings: Codable {
        let stability: Float
        let similarityBoost: Float

        enum CodingKeys: String, CodingKey {
            case stability
            case similarityBoost = "similarity_boost"
        }
    }
}

// MARK: - App State Models

enum ProcessingState {
    case idle
    case capturing
    case analyzing
    case generatingSpeech
    case playingAudio
    case error(String)

    var description: String {
        switch self {
        case .idle:
            return "Ready"
        case .capturing:
            return "Capturing frame..."
        case .analyzing:
            return "Analyzing hazards..."
        case .generatingSpeech:
            return "Generating warning..."
        case .playingAudio:
            return "Playing audio"
        case .error(let message):
            return "Error: \(message)"
        }
    }
}

struct WarningHistory: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let warningText: String
    let processingTime: TimeInterval

    init(warningText: String, processingTime: TimeInterval) {
        self.id = UUID()
        self.timestamp = Date()
        self.warningText = warningText
        self.processingTime = processingTime
    }
}

// MARK: - Error Types

enum SafetyGuardianError: Error, LocalizedError {
    case invalidConfiguration
    case networkError(Error)
    case apiError(String)
    case decodingError
    case cameraUnavailable
    case audioPlaybackFailed

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Invalid server configuration. Please check settings."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .apiError(let message):
            return "API error: \(message)"
        case .decodingError:
            return "Failed to parse server response"
        case .cameraUnavailable:
            return "Camera unavailable"
        case .audioPlaybackFailed:
            return "Failed to play audio"
        }
    }
}
