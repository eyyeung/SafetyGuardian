//
//  Configuration.swift
//  SafetyGuardian
//
//  Centralized configuration for the SafetyGuardian app
//

import Foundation
import CoreGraphics

struct AppConfiguration {
    // MARK: - API Endpoints

    // Load configuration from Config.plist
    private static let config: [String: Any] = {
        guard let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: Any] else {
            print("Warning: Config.plist not found. Using default values.")
            return [:]
        }
        return dict
    }()

    // vLLM Server - Nebius L40S GPU instance
    private static let defaultVLLMServerURL: String = config["VLLM_SERVER_URL"] as? String ?? "http://localhost:8000/v1"
    static var vllmServerURL: String = defaultVLLMServerURL

    // ElevenLabs TTS API
    static let elevenlabsAPIKey: String = config["ELEVENLABS_API_KEY"] as? String ?? ""
    static let elevenlabsBaseURL: String = config["ELEVENLABS_BASE_URL"] as? String ?? "https://api.elevenlabs.io/v1"

    // MARK: - Processing Settings

    // How often to process frames (in seconds)
    static let defaultProcessingInterval: TimeInterval = 20.0
    static var processingInterval: TimeInterval = defaultProcessingInterval

    // Video sampling for best frame selection (in seconds)
    static let defaultVideoSampleDuration: TimeInterval = 1.5
    static var videoSampleDuration: TimeInterval = defaultVideoSampleDuration
    static let videoSampleCount: Int = 6

    // Cosmos-Reason2 model parameters
    static let maxTokens: Int = 30
    static let temperature: Float = 0.6
    static let modelName: String = "nvidia/Cosmos-Reason2-2B"

    // MARK: - Camera Settings

    static let captureResolution: CGSize = CGSize(width: 1920, height: 1080)
    static let jpegQuality: CGFloat = 0.8

    // MARK: - Audio Settings

    static let defaultAudioVolume: Float = 0.8  // 0.0 to 1.0
    static var audioVolume: Float = defaultAudioVolume
    static let voiceID: String = config["VOICE_ID"] as? String ?? "21m00Tcm4TlvDq8ikWAM"  // Rachel voice
    static let ttsModel: String = "eleven_turbo_v2_5"

    // MARK: - Error Handling

    static let maxRetries: Int = 3
    static let networkTimeout: TimeInterval = 30.0
    static let retryDelayBase: TimeInterval = 1.0  // Exponential backoff: 1s, 2s, 4s

    // MARK: - System Prompts

    static let systemPrompt: String = """
    You are a safety hazard detection assistant for elderly wearable glasses. Analyze the image and respond in exactly this format:
    HAZARD: <type> | SEVERITY: <level> | ACTION: <instruction>
    Where <type> is the hazard (e.g. clear, vehicle, pedestrian, ice, puddle, obstacle, wet surface, animal, narrow path, uneven terrain, flood), <level> is none/low/medium/high/critical, and <instruction> is a brief action.
    """

    static let userPrompt: String = """
    Analyze this image for hazards and provide brief navigation guidance in 10 words or less.
    """

    // MARK: - Helper Methods

    static func chatCompletionsURL() -> URL? {
        return URL(string: "\(vllmServerURL)/chat/completions")
    }

    static func modelsURL() -> URL? {
        return URL(string: "\(vllmServerURL)/models")
    }

    static var defaultVLLMServerURLValue: String {
        return defaultVLLMServerURL
    }

    static func ttsURL(voiceID: String) -> URL? {
        return URL(string: "\(elevenlabsBaseURL)/text-to-speech/\(voiceID)")
    }

    static func retryDelay(attempt: Int) -> TimeInterval {
        return retryDelayBase * pow(2.0, Double(attempt))
    }

    // MARK: - URL Validation / Normalization

    static func normalizeVLLMServerURL(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        guard var components = URLComponents(string: normalized) else { return nil }
        guard let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        guard let host = components.host, !host.isEmpty else { return nil }

        let path = components.path
        if path.isEmpty {
            components.path = "/v1"
        } else if path.contains("/v1") {
            components.path = "/v1"
        } else {
            components.path = path + (path.hasSuffix("/") ? "v1" : "/v1")
        }

        return components.url?.absoluteString
    }
}

// MARK: - User Defaults Extensions

extension AppConfiguration {
    private static let defaults = UserDefaults.standard

    private enum Keys {
        static let processingInterval = "processingInterval"
        static let audioVolume = "audioVolume"
        static let vllmServerURL = "vllmServerURL"
        static let videoSampleDuration = "videoSampleDuration"
    }

    static func loadSettings() {
        if defaults.object(forKey: Keys.processingInterval) != nil {
            processingInterval = defaults.double(forKey: Keys.processingInterval)
        }
        if defaults.object(forKey: Keys.audioVolume) != nil {
            audioVolume = defaults.float(forKey: Keys.audioVolume)
        }
        if defaults.object(forKey: Keys.videoSampleDuration) != nil {
            videoSampleDuration = defaults.double(forKey: Keys.videoSampleDuration)
        }
        if let serverURL = defaults.string(forKey: Keys.vllmServerURL), !serverURL.isEmpty {
            vllmServerURL = serverURL
        } else {
            vllmServerURL = defaultVLLMServerURL
        }
    }

    static func saveSettings() {
        defaults.set(processingInterval, forKey: Keys.processingInterval)
        defaults.set(audioVolume, forKey: Keys.audioVolume)
        defaults.set(videoSampleDuration, forKey: Keys.videoSampleDuration)
        defaults.set(vllmServerURL, forKey: Keys.vllmServerURL)
    }

    static func resetSettingsToDefaults() {
        defaults.removeObject(forKey: Keys.processingInterval)
        defaults.removeObject(forKey: Keys.audioVolume)
        defaults.removeObject(forKey: Keys.vllmServerURL)
        defaults.removeObject(forKey: Keys.videoSampleDuration)

        processingInterval = defaultProcessingInterval
        audioVolume = defaultAudioVolume
        videoSampleDuration = defaultVideoSampleDuration
        vllmServerURL = defaultVLLMServerURL
    }

    static func hasSavedVLLMServerURL() -> Bool {
        if let serverURL = defaults.string(forKey: Keys.vllmServerURL) {
            return !serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return false
    }
}
