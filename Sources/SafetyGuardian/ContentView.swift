//
//  ContentView.swift
//  SafetyGuardian
//
//  Main user interface for SafetyGuardian app
//

import SwiftUI

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var audioPlayer = AudioPlayer()

    @State private var processingState: ProcessingState = .idle
    @State private var latestWarning: String = "No warnings yet"
    @State private var isActive = false
    @State private var timeUntilNextCheck: TimeInterval = 0
    @State private var warningHistory: [WarningHistory] = []
    @State private var showSettings = false

    private let cosmosAPI = CosmosAPI()
    private let ttsManager = TTSManager()
    private var processingTimer: Timer?

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Camera Preview
                CameraPreviewView(image: cameraManager.currentFrame)
                    .frame(height: 300)
                    .cornerRadius(12)
                    .padding()

                // Status Section
                VStack(spacing: 10) {
                    HStack {
                        Circle()
                            .fill(isActive ? Color.green : Color.gray)
                            .frame(width: 12, height: 12)

                        Text("Status: \(isActive ? "Active" : "Paused")")
                            .font(.headline)

                        Spacer()
                    }
                    .padding(.horizontal)

                    if isActive {
                        HStack {
                            Text("Next check: \(Int(timeUntilNextCheck))s")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal)
                    }

                    HStack {
                        Text("State: \(processingState.description)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal)
                }

                // Latest Warning
                VStack(alignment: .leading, spacing: 8) {
                    Text("Latest Warning:")
                        .font(.headline)

                    Text(latestWarning)
                        .font(.body)
                        .foregroundColor(.primary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }
                .padding(.horizontal)

                Spacer()

                // Control Button
                Button(action: toggleActive) {
                    HStack {
                        Image(systemName: isActive ? "pause.circle.fill" : "play.circle.fill")
                            .font(.title2)
                        Text(isActive ? "Pause Detection" : "Start Detection")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isActive ? Color.orange : Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding(.horizontal)

                // Error Message
                if let errorMessage = cameraManager.errorMessage {
                    Text("Error: \(errorMessage)")
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding()
                }
            }
            .navigationTitle("SafetyGuardian")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .onAppear {
                setupCamera()
                AppConfiguration.loadSettings()
            }
        }
    }

    // MARK: - Actions

    private func setupCamera() {
        cameraManager.setupCamera()
    }

    private func toggleActive() {
        isActive.toggle()

        if isActive {
            startDetection()
        } else {
            stopDetection()
        }
    }

    private func startDetection() {
        cameraManager.startCapture()
        scheduleProcessing()
    }

    private func stopDetection() {
        cameraManager.stopCapture()
        audioPlayer.stopAudio()
    }

    private func scheduleProcessing() {
        guard isActive else { return }

        Task {
            await processFrame()

            // Schedule next processing
            if isActive {
                DispatchQueue.main.asyncAfter(deadline: .now() + AppConfiguration.processingInterval) {
                    scheduleProcessing()
                }

                // Update countdown
                timeUntilNextCheck = AppConfiguration.processingInterval
                startCountdown()
            }
        }
    }

    private func startCountdown() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if !isActive {
                timer.invalidate()
                return
            }

            timeUntilNextCheck -= 1
            if timeUntilNextCheck <= 0 {
                timer.invalidate()
            }
        }
    }

    // MARK: - Processing Pipeline

    private func processFrame() async {
        let startTime = Date()

        do {
            // Step 1: Capture frame
            processingState = .capturing
            guard let base64Image = cameraManager.encodeFrameBase64() else {
                throw SafetyGuardianError.cameraUnavailable
            }

            // Step 2: Analyze with Cosmos-Reason2
            processingState = .analyzing
            let warningText = try await cosmosAPI.analyzeFrame(base64Image)

            // Step 3: Convert to speech
            processingState = .generatingSpeech
            let audioData = try await ttsManager.convertToSpeech(warningText)

            // Step 4: Play audio
            processingState = .playingAudio
            await MainActor.run {
                latestWarning = warningText
                audioPlayer.playAudio(audioData)
            }

            // Record processing time
            let processingTime = Date().timeIntervalSince(startTime)
            let history = WarningHistory(warningText: warningText, processingTime: processingTime)
            await MainActor.run {
                warningHistory.append(history)
                processingState = .idle
            }

            print("Full pipeline completed in \(processingTime)s: \(warningText)")

        } catch {
            await MainActor.run {
                processingState = .error(error.localizedDescription)
                print("Processing error: \(error.localizedDescription)")
            }

            // Reset to idle after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                if case .error = processingState {
                    processingState = .idle
                }
            }
        }
    }
}

// MARK: - Camera Preview View

struct CameraPreviewView: View {
    let image: UIImage?

    var body: some View {
        ZStack {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Color.black
                Text("Camera Preview")
                    .foregroundColor(.white)
            }
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss

    @State private var processingInterval: Double = AppConfiguration.processingInterval
    @State private var audioVolume: Float = AppConfiguration.audioVolume
    @State private var serverURL: String = AppConfiguration.vllmServerURL

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Processing")) {
                    VStack(alignment: .leading) {
                        Text("Interval: \(Int(processingInterval))s")
                            .font(.headline)

                        Slider(value: $processingInterval, in: 5...60, step: 5)

                        HStack {
                            Text("5s")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("30s")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("60s")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section(header: Text("Audio")) {
                    VStack(alignment: .leading) {
                        Text("Volume: \(Int(audioVolume * 100))%")
                            .font(.headline)

                        Slider(value: $audioVolume, in: 0...1, step: 0.1)

                        HStack {
                            Text("Quiet")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("Loud")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section(header: Text("Server Configuration")) {
                    TextField("vLLM Server URL", text: $serverURL)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                        .font(.footnote)

                    Text("Example: http://YOUR_IP:8000/v1")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section {
                    Button("Save Settings") {
                        saveSettings()
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func saveSettings() {
        AppConfiguration.processingInterval = processingInterval
        AppConfiguration.audioVolume = audioVolume
        AppConfiguration.vllmServerURL = serverURL
        AppConfiguration.saveSettings()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
