//
//  AudioPlayer.swift
//  SafetyGuardian
//
//  Manages audio playback for safety warnings
//

import Foundation
import AVFoundation

class AudioPlayer: NSObject, ObservableObject {
    @Published var isPlaying = false

    private var player: AVAudioPlayer?
    private var audioQueue: [Data] = []

    override init() {
        super.init()
        configureAudioSession()
    }

    // MARK: - Audio Session Configuration

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            print("Failed to configure audio session: \(error.localizedDescription)")
        }
    }

    // MARK: - Playback Control

    func playAudio(_ audioData: Data) {
        // If currently playing, queue the audio
        if isPlaying {
            audioQueue.append(audioData)
            return
        }

        // Play immediately
        performPlayback(audioData)
    }

    private func performPlayback(_ audioData: Data) {
        do {
            player = try AVAudioPlayer(data: audioData)
            player?.delegate = self
            player?.volume = AppConfiguration.audioVolume

            if player?.play() == true {
                DispatchQueue.main.async {
                    self.isPlaying = true
                }
            } else {
                print("Failed to start audio playback")
            }
        } catch {
            print("Audio playback error: \(error.localizedDescription)")
        }
    }

    func stopAudio() {
        player?.stop()
        player = nil
        audioQueue.removeAll()
        DispatchQueue.main.async {
            self.isPlaying = false
        }
    }

    func setVolume(_ volume: Float) {
        player?.volume = volume
    }

    // MARK: - Queue Management

    private func playNextInQueue() {
        guard !audioQueue.isEmpty else {
            DispatchQueue.main.async {
                self.isPlaying = false
            }
            return
        }

        let nextAudio = audioQueue.removeFirst()
        performPlayback(nextAudio)
    }
}

// MARK: - AVAudioPlayerDelegate

extension AudioPlayer: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        playNextInQueue()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        print("Audio decode error: \(error?.localizedDescription ?? "Unknown")")
        DispatchQueue.main.async {
            self.isPlaying = false
        }
        playNextInQueue()
    }
}
