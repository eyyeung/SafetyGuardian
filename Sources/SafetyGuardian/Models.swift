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
    let extraBody: ExtraBody?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxTokens = "max_tokens"
        case temperature
        case extraBody = "extra_body"
    }

    struct ExtraBody: Codable {
        let loraName: String

        enum CodingKeys: String, CodingKey {
            case loraName = "lora_name"
        }
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

// MARK: - Structured Hazard Detection

struct HazardDetection {
    let hazardType: String
    let severity: SeverityLevel
    let action: String
    let rawText: String
    
    enum SeverityLevel: String, CaseIterable {
        case none = "none"
        case low = "low"
        case medium = "medium"
        case high = "high"
        case critical = "critical"
        
        var color: (red: Double, green: Double, blue: Double) {
            switch self {
            case .none:
                return (0.2, 0.8, 0.2) // Green
            case .low:
                return (0.4, 0.8, 1.0) // Light Blue
            case .medium:
                return (1.0, 0.8, 0.0) // Yellow
            case .high:
                return (1.0, 0.5, 0.0) // Orange
            case .critical:
                return (1.0, 0.2, 0.2) // Red
            }
        }
        
        var displayName: String {
            return rawValue.uppercased()
        }
    }
    
    static func parse(_ text: String) -> HazardDetection {
        // Parse format: "HAZARD: <type> | SEVERITY: <level> | ACTION: <instruction>"
        let components = text.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        
        var hazardType = "unknown"
        var severity = SeverityLevel.none
        var action = "No action needed"
        
        for component in components {
            if component.uppercased().starts(with: "HAZARD:") {
                hazardType = component.dropFirst(7).trimmingCharacters(in: .whitespaces)
            } else if component.uppercased().starts(with: "SEVERITY:") {
                let severityStr = component.dropFirst(9).trimmingCharacters(in: .whitespaces).lowercased()
                severity = SeverityLevel(rawValue: severityStr) ?? .none
            } else if component.uppercased().starts(with: "ACTION:") {
                action = component.dropFirst(7).trimmingCharacters(in: .whitespaces)
            }
        }
        
        return HazardDetection(hazardType: hazardType, severity: severity, action: action, rawText: text)
    }
    
    /// Convert structured hazard detection to natural speech text
    func toSpeechText() -> String {
        // Handle "clear" or "none" cases - keep it positive and brief
        if hazardType.lowercased() == "clear" || severity == .none {
            return "All clear, proceed safely"
        }
        
        // For hazards, compose natural speech based on severity
        var speechParts: [String] = []
        
        // Add severity indicator for medium/high/critical
        switch severity {
        case .critical:
            speechParts.append("Danger!")
        case .high:
            speechParts.append("Caution!")
        case .medium:
            speechParts.append("Watch out.")
        case .low, .none:
            break // No prefix for low severity
        }
        
        // Add hazard type (capitalize first letter for proper speech)
        let hazardName = hazardType.prefix(1).uppercased() + hazardType.dropFirst()
        speechParts.append(hazardName)
        
        // Add severity level as description (only for medium+)
        if severity == .high || severity == .critical {
            speechParts.append("ahead.")
        } else if severity == .medium {
            speechParts.append("detected.")
        }
        
        // Add action
        speechParts.append(action)
        
        return speechParts.joined(separator: " ")
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
