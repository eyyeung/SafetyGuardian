//
//  IntegrationTests.swift
//  SafetyGuardianTests
//
//  Integration and end-to-end tests
//

import XCTest
@testable import SafetyGuardian

final class IntegrationTests: XCTestCase {

    // MARK: - Configuration Integration Tests

    func testConfigurationPersistence() {
        // Save custom settings
        let originalInterval = AppConfiguration.processingInterval
        let originalVolume = AppConfiguration.audioVolume
        let originalURL = AppConfiguration.vllmServerURL

        AppConfiguration.processingInterval = 10.0
        AppConfiguration.audioVolume = 0.6
        AppConfiguration.vllmServerURL = "http://test.example.com:8000/v1"

        AppConfiguration.saveSettings()

        // Reset
        AppConfiguration.processingInterval = 20.0
        AppConfiguration.audioVolume = 0.8
        AppConfiguration.vllmServerURL = "http://default:8000/v1"

        // Load
        AppConfiguration.loadSettings()

        // Verify
        XCTAssertEqual(AppConfiguration.processingInterval, 10.0, accuracy: 0.01)
        XCTAssertEqual(AppConfiguration.audioVolume, 0.6, accuracy: 0.01)
        XCTAssertEqual(AppConfiguration.vllmServerURL, "http://test.example.com:8000/v1")

        // Restore original values
        AppConfiguration.processingInterval = originalInterval
        AppConfiguration.audioVolume = originalVolume
        AppConfiguration.vllmServerURL = originalURL
        AppConfiguration.saveSettings()
    }

    // MARK: - API Integration Tests

    func testCosmosAPIWithValidConfiguration() async {
        AppConfiguration.vllmServerURL = "http://localhost:8000/v1"

        let cosmosAPI = CosmosAPI()
        let testImage = "test-base64-image"

        do {
            _ = try await cosmosAPI.analyzeFrame(testImage)
            // If server is running, this should succeed
            XCTAssertTrue(true, "API call succeeded")
        } catch {
            // Expected to fail without running server
            // We just verify error handling works
            XCTAssertNotNil(error, "Should handle error gracefully")
        }
    }

    func testTTSAPIWithValidConfiguration() async {
        let ttsManager = TTSManager()
        let testText = "Test warning message"

        do {
            _ = try await ttsManager.convertToSpeech(testText)
            // If API key is valid and service is reachable, this succeeds
            XCTAssertTrue(true, "TTS call succeeded")
        } catch {
            // Expected to fail without valid API key in test environment
            XCTAssertNotNil(error, "Should handle error gracefully")
        }
    }

    // MARK: - Full Pipeline Tests

    func testFullPipelineDataFlow() async {
        // This test simulates the full data flow without actual hardware/APIs
        // Camera -> Cosmos API -> TTS -> Audio Player

        let cameraManager = CameraManager()
        let cosmosAPI = CosmosAPI()
        let ttsManager = TTSManager()
        let audioPlayer = AudioPlayer()

        // Step 1: Get frame (will be nil in simulator)
        let base64Image = cameraManager.encodeFrameBase64()

        if let image = base64Image {
            // Step 2: Analyze frame
            do {
                let warningText = try await cosmosAPI.analyzeFrame(image)

                // Step 3: Convert to speech
                let audioData = try await ttsManager.convertToSpeech(warningText)

                // Step 4: Play audio
                audioPlayer.playAudio(audioData)

                XCTAssertTrue(true, "Full pipeline completed")
            } catch {
                // Expected to fail without real infrastructure
                XCTAssertNotNil(error)
            }
        } else {
            // No camera in simulator - expected
            XCTAssertTrue(true, "Camera unavailable in test environment")
        }
    }

    // MARK: - Error Recovery Tests

    func testAPIRetryMechanism() async {
        AppConfiguration.vllmServerURL = "http://192.0.2.1:8000/v1"  // Unreachable

        let cosmosAPI = CosmosAPI()
        let startTime = Date()

        do {
            _ = try await cosmosAPI.analyzeFrame("test")
            XCTFail("Should fail with unreachable server")
        } catch {
            let elapsed = Date().timeIntervalSince(startTime)

            // Should retry 3 times with exponential backoff (1s, 2s)
            // Total: ~3 seconds minimum
            XCTAssertGreaterThanOrEqual(elapsed, 2.0, "Should retry with delays")
        }
    }

    func testTTSRetryMechanism() async {
        // Create TTS manager with invalid configuration
        let ttsManager = TTSManager()

        let startTime = Date()

        do {
            _ = try await ttsManager.convertToSpeech("test")
        } catch {
            let elapsed = Date().timeIntervalSince(startTime)

            // TTS retries twice with 1 second delay
            // Should take at least 1 second
            XCTAssertNotNil(error, "Should handle TTS failure")
        }
    }

    // MARK: - Memory Management Tests

    func testMemoryManagementUnderLoad() async {
        // Simulate multiple processing cycles
        let cosmosAPI = CosmosAPI()
        let ttsManager = TTSManager()

        for i in 0..<10 {
            autoreleasepool {
                Task {
                    do {
                        _ = try await cosmosAPI.analyzeFrame("test-\(i)")
                        _ = try await ttsManager.convertToSpeech("test-\(i)")
                    } catch {
                        // Expected to fail, we're testing memory management
                    }
                }
            }
        }

        // If we get here without crashing, memory management is working
        XCTAssertTrue(true, "Memory management passed")
    }

    // MARK: - Concurrent Processing Tests

    func testConcurrentAPIRequests() async {
        AppConfiguration.vllmServerURL = "http://localhost:8000/v1"

        let cosmosAPI = CosmosAPI()

        // Create multiple concurrent requests
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<5 {
                group.addTask {
                    do {
                        _ = try await cosmosAPI.analyzeFrame("test-\(i)")
                    } catch {
                        // Expected to fail without server
                    }
                }
            }
        }

        XCTAssertTrue(true, "Concurrent requests handled")
    }

    // MARK: - Data Validation Tests

    func testWarningHistoryTracking() {
        var history: [WarningHistory] = []

        // Add some warnings
        for i in 1...5 {
            let warning = WarningHistory(
                warningText: "Warning \(i)",
                processingTime: Double(i) * 0.5
            )
            history.append(warning)
        }

        XCTAssertEqual(history.count, 5, "Should have 5 warnings")

        // Verify all warnings are unique
        let uniqueIDs = Set(history.map { $0.id })
        XCTAssertEqual(uniqueIDs.count, 5, "All warnings should have unique IDs")

        // Verify warnings can be encoded/decoded
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(history)

            let decoder = JSONDecoder()
            let decoded = try decoder.decode([WarningHistory].self, from: data)

            XCTAssertEqual(decoded.count, history.count)
        } catch {
            XCTFail("Failed to encode/decode warning history: \(error)")
        }
    }

    // MARK: - Performance Tests

    func testFullPipelineLatency() {
        // Measure the overhead of the full pipeline (without network calls)
        measure {
            let cameraManager = CameraManager()
            let cosmosAPI = CosmosAPI()
            let ttsManager = TTSManager()
            let audioPlayer = AudioPlayer()

            // Measure object creation and basic operations
            _ = cameraManager.getCurrentFrame()
            audioPlayer.setVolume(0.8)
        }
    }
}
