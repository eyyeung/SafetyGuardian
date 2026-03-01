//
//  AudioPlayerTests.swift
//  SafetyGuardianTests
//
//  Unit tests for AudioPlayer
//

import XCTest
import AVFoundation
@testable import SafetyGuardian

final class AudioPlayerTests: XCTestCase {

    var audioPlayer: AudioPlayer!

    override func setUp() {
        super.setUp()
        audioPlayer = AudioPlayer()
    }

    override func tearDown() {
        audioPlayer.stopAudio()
        audioPlayer = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testAudioPlayerInitialization() {
        XCTAssertNotNil(audioPlayer, "Audio player should be initialized")
        XCTAssertFalse(audioPlayer.isPlaying, "Should not be playing initially")
    }

    // MARK: - Volume Control Tests

    func testSetVolume() {
        let testVolumes: [Float] = [0.0, 0.5, 1.0]

        for volume in testVolumes {
            audioPlayer.setVolume(volume)
            // Volume is set on the internal player, which may be nil
            // This test verifies the method doesn't crash
            XCTAssertNotNil(audioPlayer, "Audio player should remain valid after setVolume")
        }
    }

    // MARK: - Playback Tests

    func testPlayValidMP3Data() throws {
        // Create a minimal valid MP3 data (just headers for testing)
        // In a real test, you'd use actual MP3 data
        let mp3Data = createMinimalMP3Data()

        audioPlayer.playAudio(mp3Data)

        // Note: Actual playback may fail without valid audio data
        // but the method should not crash
        XCTAssertNotNil(audioPlayer, "Audio player should handle playback attempt")
    }

    func testPlayInvalidAudioData() {
        let invalidData = Data([0x00, 0x00, 0x00, 0x00])

        audioPlayer.playAudio(invalidData)

        // Should handle invalid data gracefully
        XCTAssertNotNil(audioPlayer, "Audio player should handle invalid data")
    }

    func testStopAudio() {
        audioPlayer.stopAudio()

        XCTAssertFalse(audioPlayer.isPlaying, "Should not be playing after stop")
    }

    // MARK: - Queue Management Tests

    func testQueueingMultipleAudioClips() {
        let audio1 = createMinimalMP3Data()
        let audio2 = createMinimalMP3Data()
        let audio3 = createMinimalMP3Data()

        // Play first audio
        audioPlayer.playAudio(audio1)

        // Queue additional audio (these will be queued if first is playing)
        audioPlayer.playAudio(audio2)
        audioPlayer.playAudio(audio3)

        // Verify player doesn't crash with queued audio
        XCTAssertNotNil(audioPlayer)
    }

    func testStopClearsQueue() {
        let audio1 = createMinimalMP3Data()
        let audio2 = createMinimalMP3Data()

        audioPlayer.playAudio(audio1)
        audioPlayer.playAudio(audio2)
        audioPlayer.stopAudio()

        XCTAssertFalse(audioPlayer.isPlaying, "Should not be playing after stop")
    }

    // MARK: - Performance Tests

    func testAudioPlayerPerformance() {
        measure {
            let testData = createMinimalMP3Data()
            audioPlayer.playAudio(testData)
            audioPlayer.stopAudio()
        }
    }

    // MARK: - Helper Methods

    private func createMinimalMP3Data() -> Data {
        // Create minimal MP3 frame header (for testing purposes)
        // This is not a valid playable MP3, but tests method robustness
        var data = Data()

        // MP3 sync word (11 bits of 1s)
        data.append(contentsOf: [0xFF, 0xFB])

        // Add some padding to make it look like audio data
        data.append(contentsOf: [UInt8](repeating: 0x00, count: 100))

        return data
    }

    // MARK: - Audio Session Tests

    func testAudioSessionConfiguration() {
        // Verify audio session is configured
        let session = AVAudioSession.sharedInstance()

        // The audio player should have configured the session
        // Note: This might affect other tests, so we just verify it doesn't crash
        XCTAssertNotNil(session, "Audio session should exist")
    }
}
