//
//  ConfigurationTests.swift
//  SafetyGuardianTests
//
//  Unit tests for AppConfiguration
//

import XCTest
@testable import SafetyGuardian

final class ConfigurationTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Clear UserDefaults before each test
        UserDefaults.standard.removeObject(forKey: "processingInterval")
        UserDefaults.standard.removeObject(forKey: "audioVolume")
        UserDefaults.standard.removeObject(forKey: "vllmServerURL")
    }

    // MARK: - URL Generation Tests

    func testChatCompletionsURL() {
        AppConfiguration.vllmServerURL = "http://example.com:8000/v1"
        let url = AppConfiguration.chatCompletionsURL()

        XCTAssertNotNil(url, "Chat completions URL should not be nil")
        XCTAssertEqual(url?.absoluteString, "http://example.com:8000/v1/chat/completions")
    }

    func testTTSURL() {
        let testVoiceID = "test-voice-123"
        let url = AppConfiguration.ttsURL(voiceID: testVoiceID)

        XCTAssertNotNil(url, "TTS URL should not be nil")
        XCTAssertEqual(url?.absoluteString, "https://api.elevenlabs.io/v1/text-to-speech/test-voice-123")
    }

    func testInvalidServerURL() {
        AppConfiguration.vllmServerURL = ""
        let url = AppConfiguration.chatCompletionsURL()

        XCTAssertNil(url, "URL should be nil for empty server URL")
    }

    // MARK: - Retry Delay Tests

    func testRetryDelayExponentialBackoff() {
        let delay0 = AppConfiguration.retryDelay(attempt: 0)
        let delay1 = AppConfiguration.retryDelay(attempt: 1)
        let delay2 = AppConfiguration.retryDelay(attempt: 2)

        XCTAssertEqual(delay0, 1.0, accuracy: 0.01, "First retry delay should be 1 second")
        XCTAssertEqual(delay1, 2.0, accuracy: 0.01, "Second retry delay should be 2 seconds")
        XCTAssertEqual(delay2, 4.0, accuracy: 0.01, "Third retry delay should be 4 seconds")
    }

    // MARK: - Settings Persistence Tests

    func testSaveAndLoadSettings() {
        // Set custom values
        AppConfiguration.processingInterval = 15.0
        AppConfiguration.audioVolume = 0.7
        AppConfiguration.vllmServerURL = "http://test.server:8000/v1"

        // Save settings
        AppConfiguration.saveSettings()

        // Reset to defaults
        AppConfiguration.processingInterval = 20.0
        AppConfiguration.audioVolume = 0.8
        AppConfiguration.vllmServerURL = "http://default:8000/v1"

        // Load settings
        AppConfiguration.loadSettings()

        // Verify loaded values match saved values
        XCTAssertEqual(AppConfiguration.processingInterval, 15.0, accuracy: 0.01)
        XCTAssertEqual(AppConfiguration.audioVolume, 0.7, accuracy: 0.01)
        XCTAssertEqual(AppConfiguration.vllmServerURL, "http://test.server:8000/v1")
    }

    func testLoadSettingsWithNoSavedData() {
        // Ensure no saved data exists
        UserDefaults.standard.removeObject(forKey: "processingInterval")

        // Set a custom value
        AppConfiguration.processingInterval = 25.0

        // Load settings (should not change value since no saved data exists)
        AppConfiguration.loadSettings()

        // Value should remain unchanged
        XCTAssertEqual(AppConfiguration.processingInterval, 25.0, accuracy: 0.01)
    }

    // MARK: - Default Values Tests

    func testDefaultValues() {
        XCTAssertEqual(AppConfiguration.maxTokens, 30, "Default max tokens should be 30")
        XCTAssertEqual(AppConfiguration.temperature, 0.6, accuracy: 0.01, "Default temperature should be 0.6")
        XCTAssertEqual(AppConfiguration.maxRetries, 3, "Default max retries should be 3")
        XCTAssertEqual(AppConfiguration.networkTimeout, 30.0, accuracy: 0.01, "Default timeout should be 30 seconds")
        XCTAssertEqual(AppConfiguration.jpegQuality, 0.8, accuracy: 0.01, "Default JPEG quality should be 0.8")
    }

    // MARK: - Prompt Tests

    func testSystemPromptIsNotEmpty() {
        XCTAssertFalse(AppConfiguration.systemPrompt.isEmpty, "System prompt should not be empty")
        XCTAssertTrue(AppConfiguration.systemPrompt.contains("safety"), "System prompt should mention safety")
    }

    func testUserPromptIsNotEmpty() {
        XCTAssertFalse(AppConfiguration.userPrompt.isEmpty, "User prompt should not be empty")
        XCTAssertTrue(AppConfiguration.userPrompt.contains("hazard"), "User prompt should mention hazards")
    }
}
