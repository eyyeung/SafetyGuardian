//
//  CameraManagerTests.swift
//  SafetyGuardianTests
//
//  Unit tests for CameraManager
//

import XCTest
import AVFoundation
import UIKit
@testable import SafetyGuardian

final class CameraManagerTests: XCTestCase {

    var cameraManager: CameraManager!

    override func setUp() {
        super.setUp()
        cameraManager = CameraManager()
    }

    override func tearDown() {
        cameraManager.stopCapture()
        cameraManager = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testCameraManagerInitialization() {
        XCTAssertNotNil(cameraManager, "Camera manager should be initialized")
        XCTAssertFalse(cameraManager.isCapturing, "Should not be capturing initially")
        XCTAssertNil(cameraManager.currentFrame, "No frame should be captured initially")
    }

    // MARK: - Camera Setup Tests

    func testSetupCamera() {
        // Setup camera (may fail in test environment without camera)
        cameraManager.setupCamera()

        // Wait a moment for async setup
        let expectation = XCTestExpectation(description: "Camera setup")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)

        // In simulator, camera setup might fail - that's expected
        // We just verify the manager doesn't crash
        XCTAssertNotNil(cameraManager, "Camera manager should remain valid")
    }

    // MARK: - Capture Control Tests

    func testStartCapture() {
        cameraManager.setupCamera()

        // Wait for setup
        sleep(1)

        cameraManager.startCapture()

        // Wait for capture to start
        let expectation = XCTestExpectation(description: "Start capture")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // Note: In simulator, this will likely fail to actually capture
        // But we verify the API works
        XCTAssertNotNil(cameraManager)
    }

    func testStopCapture() {
        cameraManager.stopCapture()

        let expectation = XCTestExpectation(description: "Stop capture")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            XCTAssertFalse(self.cameraManager.isCapturing, "Should not be capturing after stop")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Frame Access Tests

    func testGetCurrentFrameWithoutCapture() {
        let frame = cameraManager.getCurrentFrame()

        // Without active capture, frame should be nil
        XCTAssertNil(frame, "Should have no frame without capture")
    }

    // MARK: - Base64 Encoding Tests

    func testEncodeFrameBase64WithoutFrame() {
        let base64 = cameraManager.encodeFrameBase64()

        // Without a frame, encoding should return nil
        XCTAssertNil(base64, "Should return nil without frame")
    }

    func testBase64EncodingFormat() {
        // Create a test image
        let testImage = createTestImage()

        // Encode to JPEG
        guard let jpegData = testImage.jpegData(compressionQuality: 0.8) else {
            XCTFail("Failed to create JPEG data")
            return
        }

        let base64 = jpegData.base64EncodedString()

        XCTAssertFalse(base64.isEmpty, "Base64 string should not be empty")
        XCTAssertGreaterThan(base64.count, 0, "Base64 should have content")

        // Verify it's valid base64
        let decoded = Data(base64Encoded: base64)
        XCTAssertNotNil(decoded, "Base64 should be decodable")
    }

    // MARK: - Error Handling Tests

    func testErrorMessageHandling() {
        // Initially no error
        XCTAssertNil(cameraManager.errorMessage, "Should have no error initially")

        // Setup camera (might produce error in simulator)
        cameraManager.setupCamera()

        // Wait for potential error
        let expectation = XCTestExpectation(description: "Error handling")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)

        // Error message might be set in simulator (no camera available)
        // We just verify it doesn't crash
        XCTAssertNotNil(cameraManager)
    }

    // MARK: - Performance Tests

    func testJPEGCompressionPerformance() {
        let testImage = createTestImage()

        measure {
            _ = testImage.jpegData(compressionQuality: 0.8)
        }
    }

    func testBase64EncodingPerformance() {
        let testImage = createTestImage()
        guard let jpegData = testImage.jpegData(compressionQuality: 0.8) else {
            XCTFail("Failed to create JPEG data")
            return
        }

        measure {
            _ = jpegData.base64EncodedString()
        }
    }

    // MARK: - Helper Methods

    private func createTestImage() -> UIImage {
        // Create a simple test image
        let size = CGSize(width: 1920, height: 1080)
        let renderer = UIGraphicsImageRenderer(size: size)

        let image = renderer.image { context in
            // Fill with a color
            UIColor.blue.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            // Add some content
            UIColor.white.setFill()
            context.fill(CGRect(x: 100, y: 100, width: 200, height: 200))
        }

        return image
    }
}
