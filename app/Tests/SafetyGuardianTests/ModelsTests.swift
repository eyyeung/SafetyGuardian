//
//  ModelsTests.swift
//  SafetyGuardianTests
//
//  Unit tests for data models
//

import XCTest
@testable import SafetyGuardian

final class ModelsTests: XCTestCase {

    // MARK: - CosmosRequest Tests

    func testCosmosRequestEncoding() throws {
        let request = CosmosRequest(
            model: "test-model",
            messages: [
                CosmosRequest.Message(
                    role: "system",
                    content: .text("Test system message")
                ),
                CosmosRequest.Message(
                    role: "user",
                    content: .multipart([
                        CosmosRequest.ContentPart(
                            type: "text",
                            text: "Test user message",
                            imageUrl: nil
                        )
                    ])
                )
            ],
            maxTokens: 30,
            temperature: 0.6
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(request)

        XCTAssertNotNil(data, "Encoded data should not be nil")
        XCTAssertGreaterThan(data.count, 0, "Encoded data should not be empty")

        // Verify JSON structure
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["model"] as? String, "test-model")
        XCTAssertEqual(json?["max_tokens"] as? Int, 30)
        XCTAssertEqual(json?["temperature"] as? Double, 0.6, accuracy: 0.01)
    }

    func testCosmosRequestWithImageURL() throws {
        let imageURL = CosmosRequest.ImageURL(url: "data:image/jpeg;base64,test123")
        let contentPart = CosmosRequest.ContentPart(
            type: "image_url",
            text: nil,
            imageUrl: imageURL
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(contentPart)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["type"] as? String, "image_url")
        XCTAssertNotNil(json?["image_url"])
    }

    // MARK: - CosmosResponse Tests

    func testCosmosResponseDecoding() throws {
        let jsonString = """
        {
            "id": "test-123",
            "choices": [
                {
                    "message": {
                        "content": "Test warning message"
                    },
                    "finish_reason": "stop"
                }
            ],
            "usage": {
                "total_tokens": 2160
            }
        }
        """

        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        let response = try decoder.decode(CosmosResponse.self, from: data)

        XCTAssertEqual(response.id, "test-123")
        XCTAssertEqual(response.choices.count, 1)
        XCTAssertEqual(response.choices.first?.message.content, "Test warning message")
        XCTAssertEqual(response.usage?.totalTokens, 2160)
    }

    func testCosmosResponseWithoutUsage() throws {
        let jsonString = """
        {
            "id": "test-456",
            "choices": [
                {
                    "message": {
                        "content": "Another test"
                    }
                }
            ]
        }
        """

        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        let response = try decoder.decode(CosmosResponse.self, from: data)

        XCTAssertEqual(response.id, "test-456")
        XCTAssertNil(response.usage, "Usage should be nil when not present in JSON")
    }

    // MARK: - TTSRequest Tests

    func testTTSRequestEncoding() throws {
        let request = TTSRequest(
            text: "Test warning",
            modelId: "eleven_turbo_v2_5",
            voiceSettings: TTSRequest.VoiceSettings(
                stability: 0.5,
                similarityBoost: 0.5
            )
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["text"] as? String, "Test warning")
        XCTAssertEqual(json?["model_id"] as? String, "eleven_turbo_v2_5")
        XCTAssertNotNil(json?["voice_settings"])
    }

    // MARK: - ProcessingState Tests

    func testProcessingStateDescriptions() {
        XCTAssertEqual(ProcessingState.idle.description, "Ready")
        XCTAssertEqual(ProcessingState.capturing.description, "Capturing frame...")
        XCTAssertEqual(ProcessingState.analyzing.description, "Analyzing hazards...")
        XCTAssertEqual(ProcessingState.generatingSpeech.description, "Generating warning...")
        XCTAssertEqual(ProcessingState.playingAudio.description, "Playing audio")

        let errorState = ProcessingState.error("Test error")
        XCTAssertTrue(errorState.description.contains("Test error"))
    }

    // MARK: - WarningHistory Tests

    func testWarningHistoryCreation() {
        let warning = WarningHistory(
            warningText: "Puddle ahead, move right",
            processingTime: 1.07
        )

        XCTAssertNotNil(warning.id)
        XCTAssertEqual(warning.warningText, "Puddle ahead, move right")
        XCTAssertEqual(warning.processingTime, 1.07, accuracy: 0.01)
        XCTAssertNotNil(warning.timestamp)
    }

    func testWarningHistoryEncoding() throws {
        let warning = WarningHistory(
            warningText: "Test warning",
            processingTime: 2.5
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(warning)

        XCTAssertNotNil(data)
        XCTAssertGreaterThan(data.count, 0)

        // Decode back to verify
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(WarningHistory.self, from: data)

        XCTAssertEqual(decoded.id, warning.id)
        XCTAssertEqual(decoded.warningText, "Test warning")
        XCTAssertEqual(decoded.processingTime, 2.5, accuracy: 0.01)
    }

    // MARK: - Error Types Tests

    func testSafetyGuardianErrorDescriptions() {
        let errors: [SafetyGuardianError] = [
            .invalidConfiguration,
            .networkError(NSError(domain: "test", code: -1, userInfo: nil)),
            .apiError("Test API error"),
            .decodingError,
            .cameraUnavailable,
            .audioPlaybackFailed
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Error description should not be nil")
            XCTAssertFalse(error.errorDescription!.isEmpty, "Error description should not be empty")
        }
    }

    func testNetworkErrorWrapping() {
        let underlyingError = NSError(domain: "TestDomain", code: 404, userInfo: [
            NSLocalizedDescriptionKey: "Not Found"
        ])
        let error = SafetyGuardianError.networkError(underlyingError)

        XCTAssertTrue(error.errorDescription!.contains("Not Found"))
    }
}
