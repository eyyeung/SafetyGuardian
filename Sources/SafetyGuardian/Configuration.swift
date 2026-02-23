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
    static var vllmServerURL: String = config["VLLM_SERVER_URL"] as? String ?? "http://localhost:8000/v1"

    // ElevenLabs TTS API
    static let elevenlabsAPIKey: String = config["ELEVENLABS_API_KEY"] as? String ?? ""
    static let elevenlabsBaseURL: String = config["ELEVENLABS_BASE_URL"] as? String ?? "https://api.elevenlabs.io/v1"

    // MARK: - Processing Settings

    // How often to process frames (in seconds)
    static var processingInterval: TimeInterval = 20.0

    // Cosmos-Reason2 model parameters
    static let maxTokens: Int = 30
    static let temperature: Float = 0.6
    static let modelName: String = "nvidia/Cosmos-Reason2-2B"

    // MARK: - Camera Settings

    static let captureResolution: CGSize = CGSize(width: 1920, height: 1080)
    static let jpegQuality: CGFloat = 0.8

    // MARK: - Audio Settings

    static var audioVolume: Float = 0.8  // 0.0 to 1.0
    static let voiceID: String = config["VOICE_ID"] as? String ?? "21m00Tcm4TlvDq8ikWAM"  // Rachel voice
    static let ttsModel: String = "eleven_turbo_v2_5"

    // MARK: - Error Handling

    static let maxRetries: Int = 3
    static let networkTimeout: TimeInterval = 30.0
    static let retryDelayBase: TimeInterval = 1.0  // Exponential backoff: 1s, 2s, 4s

    // MARK: - System Prompts

    static let systemPrompt: String = """
    You are a safety detection system for wearable glasses.
    Analyze the image and provide brief navigation guidance.
    """

    static let userPrompt: String = """
    Analyze this image for hazards and provide brief navigation guidance in 10 words or less.
    Format: "[hazard], [direction]" (e.g., "ice patch ahead, move rightward").

    Hazards include: ice, wet surfaces, puddles, vehicles, obstacles, steep slopes, uneven terrain.

    Keep it VERY concise for text-to-speech output.
    """

    // MARK: - Helper Methods

    static func chatCompletionsURL() -> URL? {
        return URL(string: "\(vllmServerURL)/chat/completions")
    }

    static func ttsURL(voiceID: String) -> URL? {
        return URL(string: "\(elevenlabsBaseURL)/text-to-speech/\(voiceID)")
    }

    static func retryDelay(attempt: Int) -> TimeInterval {
        return retryDelayBase * pow(2.0, Double(attempt))
    }
}

// MARK: - User Defaults Extensions

extension AppConfiguration {
    private static let defaults = UserDefaults.standard

    private enum Keys {
        static let processingInterval = "processingInterval"
        static let audioVolume = "audioVolume"
        static let vllmServerURL = "vllmServerURL"
    }

    static func loadSettings() {
        if defaults.object(forKey: Keys.processingInterval) != nil {
            processingInterval = defaults.double(forKey: Keys.processingInterval)
        }
        if defaults.object(forKey: Keys.audioVolume) != nil {
            audioVolume = defaults.float(forKey: Keys.audioVolume)
        }
        if let serverURL = defaults.string(forKey: Keys.vllmServerURL), !serverURL.isEmpty {
            vllmServerURL = serverURL
        }
    }

    static func saveSettings() {
        defaults.set(processingInterval, forKey: Keys.processingInterval)
        defaults.set(audioVolume, forKey: Keys.audioVolume)
        defaults.set(vllmServerURL, forKey: Keys.vllmServerURL)
    }
}
