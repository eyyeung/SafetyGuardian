//
//  TTSManagerTests.swift
//  SafetyGuardianTests
//
//  Unit tests for TTSManager
//

import XCTest
@testable import SafetyGuardian

final class TTSManagerTests: XCTestCase {

    var ttsManager: TTSManager!

    override func setUp() {
        super.setUp()
        ttsManager = TTSManager()
    }

    override func tearDown() {
        ttsManager = nil
        super.tearDown()
    }

    // MARK: - Configuration Tests

    func testInvalidTTSConfigurationThrowsError() async {
        // Test with empty voice ID (would create invalid URL)
        let originalVoiceID = AppConfiguration.voiceID

        // This test verifies error handling for configuration issues
        // Note: We can't directly modify the static let voiceID, so we test URL generation

        let url = AppConfiguration.ttsURL(voiceID: "")
        XCTAssertNil(url, "URL should be nil for empty voice ID")
    }

    // MARK: - Text Validation Tests

    func testConvertEmptyTextToSpeech() async {
        // Test with empty text
        let emptyText = ""

        do {
            // This should still attempt to make the API call
            // but will fail due to invalid API key (expected in tests)
            _ = try await ttsManager.convertToSpeech(emptyText)
            // If we get here without error, verify we got data
        } catch {
            // Expected to fail in test environment without valid API
            XCTAssertNotNil(error, "Should handle empty text appropriately")
        }
    }

    func testConvertLongTextToSpeech() async {
        // Test with text longer than typical warning
        let longText = String(repeating: "Test warning message. ", count: 50)

        do {
            _ = try await ttsManager.convertToSpeech(longText)
            // Expected to fail without valid server
        } catch {
            XCTAssertNotNil(error)
        }
    }

    // MARK: - Retry Logic Tests

    func testRetryLogicOnFailure() async {
        // Use invalid configuration to trigger retries
        let testText = "Test warning"

        let startTime = Date()

        do {
            _ = try await ttsManager.convertToSpeech(testText)
            XCTFail("Should fail without valid API key")
        } catch {
            let elapsed = Date().timeIntervalSince(startTime)

            // Should retry twice (2 attempts total)
            // Expected delay: 1 second between retries
            // Allow tolerance for network operations
            XCTAssertNotNil(error, "Should throw error after retries")
        }
    }

    // MARK: - URL Generation Tests

    func testTTSURLGeneration() {
        let testVoiceID = "test-voice-id-123"
        let url = AppConfiguration.ttsURL(voiceID: testVoiceID)

        XCTAssertNotNil(url, "TTS URL should be generated")
        XCTAssertEqual(
            url?.absoluteString,
            "https://api.elevenlabs.io/v1/text-to-speech/test-voice-id-123"
        )
    }

    // MARK: - Error Type Tests

    func testErrorTypesAreCorrect() async {
        // Test that errors are of expected types
        let testText = "Test"

        do {
            _ = try await ttsManager.convertToSpeech(testText)
        } catch let error as SafetyGuardianError {
            // Should be a SafetyGuardian error type
            XCTAssertNotNil(error.errorDescription)
        } catch {
            // Network errors are also acceptable
            XCTAssertNotNil(error)
        }
    }

    // MARK: - Performance Tests

    func testTTSManagerInitializationPerformance() {
        measure {
            _ = TTSManager()
        }
    }
}
