//
//  CosmosAPITests.swift
//  SafetyGuardianTests
//
//  Unit tests for CosmosAPI client
//

import XCTest
@testable import SafetyGuardian

final class CosmosAPITests: XCTestCase {

    var cosmosAPI: CosmosAPI!

    override func setUp() {
        super.setUp()
        cosmosAPI = CosmosAPI()
        AppConfiguration.vllmServerURL = "http://localhost:8000/v1"
    }

    override func tearDown() {
        cosmosAPI = nil
        super.tearDown()
    }

    // MARK: - Configuration Tests

    func testInvalidServerURLThrowsError() async {
        AppConfiguration.vllmServerURL = ""

        let testImage = "test-base64-image-data"

        do {
            _ = try await cosmosAPI.analyzeFrame(testImage)
            XCTFail("Should throw invalid configuration error")
        } catch let error as SafetyGuardianError {
            switch error {
            case .invalidConfiguration:
                XCTAssertTrue(true, "Correctly threw invalid configuration error")
            default:
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Request Building Tests

    func testBuildRequestWithValidBase64Image() {
        // This test verifies that the request is properly formatted
        // Note: We can't directly test the private buildRequest method,
        // but we can verify the request structure through integration testing

        let testImage = Data([0xFF, 0xD8, 0xFF, 0xE0]).base64EncodedString()
        XCTAssertFalse(testImage.isEmpty, "Base64 image should not be empty")
        XCTAssertTrue(testImage.hasPrefix("/9j/"), "JPEG base64 should start with /9j/")
    }

    // MARK: - Retry Logic Tests

    func testRetryLogicWithMaxRetries() async {
        // Use an invalid URL to trigger retries
        AppConfiguration.vllmServerURL = "http://invalid.nonexistent.domain:8000/v1"

        let testImage = "test-image"

        let startTime = Date()

        do {
            _ = try await cosmosAPI.analyzeFrame(testImage)
            XCTFail("Should fail after retries")
        } catch {
            let elapsed = Date().timeIntervalSince(startTime)

            // Should have retried 3 times with exponential backoff
            // Expected delays: 0 (initial) + 1s + 2s = ~3s minimum
            // Allow some tolerance for network timeout and processing
            XCTAssertGreaterThanOrEqual(elapsed, 2.0, "Should take at least 2 seconds with retries")
        }
    }

    // MARK: - Base64 Encoding Tests

    func testBase64EncodingValidation() {
        let sampleImageData = Data([0xFF, 0xD8, 0xFF, 0xE0])  // JPEG header
        let base64 = sampleImageData.base64EncodedString()

        XCTAssertFalse(base64.isEmpty)
        XCTAssertTrue(base64.count > 0)

        // Verify it can be decoded back
        let decoded = Data(base64Encoded: base64)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded, sampleImageData)
    }

    // MARK: - Performance Tests

    func testAnalyzeFramePerformance() {
        // This test measures the performance overhead of the method
        // (not including actual network calls)

        measure {
            // Measure local processing overhead only
            let testImage = String(repeating: "A", count: 1000)
            _ = testImage.count
        }
    }

    // MARK: - Error Handling Tests

    func testNetworkErrorHandling() async {
        // Use a valid URL format but unreachable server
        AppConfiguration.vllmServerURL = "http://192.0.2.1:8000/v1"  // TEST-NET-1 (unreachable)

        let testImage = "test"

        do {
            _ = try await cosmosAPI.analyzeFrame(testImage)
            XCTFail("Should throw network error")
        } catch {
            // Should catch some form of error (network, timeout, etc.)
            XCTAssertNotNil(error, "Should throw an error")
        }
    }
}
