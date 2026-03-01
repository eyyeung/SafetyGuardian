//
//  CameraManager.swift
//  SafetyGuardian
//
//  Manages camera capture and frame extraction
//

import Foundation
import AVFoundation
import UIKit
import Combine
import ImageIO

class CameraManager: NSObject, ObservableObject {
    @Published var isCapturing = false
    @Published var currentFrame: UIImage?
    @Published var errorMessage: String?

    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private var latestSampleBuffer: CMSampleBuffer?
    private var currentVideoOrientation: AVCaptureVideoOrientation = .portrait
    private var needsLandscapeFlip: Bool = false

    // MARK: - Camera Setup

    func setupCamera() {
        let authorization = AVCaptureDevice.authorizationStatus(for: .video)
        switch authorization {
        case .authorized:
            sessionQueue.async { [weak self] in
                self?.configureCaptureSession()
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.sessionQueue.async {
                        self?.configureCaptureSession()
                    }
                } else {
                    DispatchQueue.main.async {
                        self?.errorMessage = "Camera access was denied"
                    }
                }
            }
        default:
            DispatchQueue.main.async {
                self.errorMessage = "Camera access is not authorized"
            }
        }
    }

    private func configureCaptureSession() {
        let session = AVCaptureSession()
        session.sessionPreset = .hd1920x1080

        // Get camera device (prefer external camera for wearable glasses)
        guard let videoDevice = selectVideoDevice() else {
            DispatchQueue.main.async {
                self.errorMessage = "No camera available"
            }
            return
        }

        do {
            let videoInput = try AVCaptureDeviceInput(device: videoDevice)
            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
            } else {
                DispatchQueue.main.async {
                    self.errorMessage = "Cannot add camera input"
                }
                return
            }

            // Configure video output
            let output = AVCaptureVideoDataOutput()
            output.setSampleBufferDelegate(self, queue: sessionQueue)
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]

            if session.canAddOutput(output) {
                session.addOutput(output)
                self.videoOutput = output
                self.applyVideoOrientation()
            } else {
                DispatchQueue.main.async {
                    self.errorMessage = "Cannot add video output"
                }
                return
            }

            self.captureSession = session
            self.updateOrientation(UIDevice.current.orientation)
            DispatchQueue.main.async {
                self.errorMessage = nil
            }

        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Camera setup failed: \(error.localizedDescription)"
            }
        }
    }

    private func selectVideoDevice() -> AVCaptureDevice? {
        // Priority: External camera (wearable) > Back camera > Front camera

        // Prefer external cameras when available
        if #available(iOS 17.0, *) {
            // Try to find external camera using AVCaptureDevice.externalCamera
            if let externalCamera = AVCaptureDevice.default(.external, for: .video, position: .unspecified) {
                return externalCamera
            }

            // Fallback: Discover all video devices
            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [
                    .external,
                    .builtInWideAngleCamera,
                    .builtInTelephotoCamera,
                    .builtInDualCamera,
                    .builtInDualWideCamera,
                    .builtInTripleCamera,
                    .builtInUltraWideCamera
                ],
                mediaType: .video,
                position: .unspecified
            )

            // Return first external device found
            if let external = discovery.devices.first(where: { $0.deviceType == .external }) {
                return external
            }
        }

        // Fallback to built-in cameras
        if let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            return backCamera
        }

        if let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
            return frontCamera
        }

        return nil
    }

    // MARK: - Capture Control

    func startCapture() {
        sessionQueue.async { [weak self] in
            self?.applyVideoOrientation()
            self?.captureSession?.startRunning()
            DispatchQueue.main.async {
                self?.isCapturing = true
            }
        }
    }

    func stopCapture() {
        sessionQueue.async { [weak self] in
            self?.captureSession?.stopRunning()
            DispatchQueue.main.async {
                self?.isCapturing = false
            }
        }
    }

    // MARK: - Frame Access

    func getCurrentFrame() -> UIImage? {
        guard let sampleBuffer = latestSampleBuffer else {
            return nil
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }

        var ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        if needsLandscapeFlip {
            ciImage = ciImage.oriented(.down) // 180° correction for landscape
        }
        let context = CIContext()

        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    // MARK: - Frame Encoding

    func encodeFrameBase64() -> String? {
        guard let frame = getCurrentFrame() else {
            return nil
        }

        // Compress to JPEG
        guard let jpegData = frame.jpegData(compressionQuality: AppConfiguration.jpegQuality) else {
            return nil
        }

        return jpegData.base64EncodedString()
    }

    func encodeBestFrameBase64(duration: TimeInterval, samples: Int) async -> String? {
        let sampleCount = max(samples, 1)
        let interval = duration / Double(sampleCount)
        var bestData: Data?

        for _ in 0..<sampleCount {
            if Task.isCancelled {
                return nil
            }

            if let frame = getCurrentFrame(),
               let jpegData = frame.jpegData(compressionQuality: AppConfiguration.jpegQuality) {
                if bestData == nil || jpegData.count > bestData!.count {
                    bestData = jpegData
                }
            }

            do {
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            } catch {
                return nil
            }
        }

        return bestData?.base64EncodedString()
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        latestSampleBuffer = sampleBuffer

        // Update preview frame occasionally
        if Int.random(in: 0..<30) == 0 {  // Update preview ~1 FPS
            if let image = imageFromSampleBuffer(sampleBuffer) {
                DispatchQueue.main.async {
                    self.currentFrame = image
                }
            }
        }
    }

    private func imageFromSampleBuffer(_ sampleBuffer: CMSampleBuffer) -> UIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }

        var ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        if needsLandscapeFlip {
            ciImage = ciImage.oriented(.down) // 180° correction for landscape
        }
        let context = CIContext()

        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Orientation Handling

extension CameraManager {
    func updateOrientation(_ deviceOrientation: UIDeviceOrientation) {
        guard let videoOrientation = videoOrientation(for: deviceOrientation) else {
            return
        }

        currentVideoOrientation = videoOrientation
        needsLandscapeFlip = videoOrientation == .landscapeLeft || videoOrientation == .landscapeRight

        sessionQueue.async { [weak self] in
            self?.applyVideoOrientation()
        }
    }

    private func applyVideoOrientation() {
        guard let connection = videoOutput?.connection(with: .video) else {
            return
        }

        if connection.isVideoOrientationSupported {
            connection.videoOrientation = currentVideoOrientation
        }
    }

    private func videoOrientation(for deviceOrientation: UIDeviceOrientation) -> AVCaptureVideoOrientation? {
        switch deviceOrientation {
        case .portrait:
            return .portrait
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .landscapeLeft:
            return .landscapeRight
        case .landscapeRight:
            return .landscapeLeft
        default:
            return nil
        }
    }

}

extension CameraManager {
    func updateOrientation(_ interfaceOrientation: UIInterfaceOrientation) {
        guard let videoOrientation = videoOrientation(for: interfaceOrientation) else {
            return
        }

        currentVideoOrientation = videoOrientation
        needsLandscapeFlip = videoOrientation == .landscapeLeft || videoOrientation == .landscapeRight

        sessionQueue.async { [weak self] in
            self?.applyVideoOrientation()
        }
    }

    private func videoOrientation(for interfaceOrientation: UIInterfaceOrientation) -> AVCaptureVideoOrientation? {
        switch interfaceOrientation {
        case .portrait:
            return .portrait
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .landscapeLeft:
            return .landscapeRight
        case .landscapeRight:
            return .landscapeLeft
        default:
            return nil
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    // Delegate method is already implemented above
}
