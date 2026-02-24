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

    @State private var isPulsing = false
    @State private var warningOpacity: Double = 1.0

    var body: some View {
        NavigationView {
            ZStack {
                // Background Gradient
                LinearGradient(
                    gradient: AppTheme.Colors.backgroundGradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 24) {
                    // Camera Preview
                    ZStack {
                        CameraPreviewView(image: cameraManager.currentFrame)
                            .frame(height: 350)
                            .cornerRadius(AppTheme.Layout.cornerRadius)
                            .shadow(color: isActive ? AppTheme.Colors.accent.opacity(0.3) : .clear, radius: 20)
                        
                        // Glassy readout for state
                        VStack {
                            Spacer()
                            HStack {
                                Text(processingState.description)
                                    .font(AppTheme.Typography.caption())
                                    .foregroundColor(.white.opacity(0.8))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(.ultraThinMaterial)
                                    .cornerRadius(12)
                                Spacer()
                                
                                if isActive {
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(AppTheme.Colors.success)
                                            .frame(width: 8, height: 8)
                                            .scaleEffect(isPulsing ? 1.2 : 0.8)
                                            .opacity(isPulsing ? 1.0 : 0.5)
                                        
                                        Text("LIVE")
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .foregroundColor(.white)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.red.opacity(0.8))
                                    .cornerRadius(8)
                                }
                            }
                            .padding(16)
                        }
                    }
                    .padding(.horizontal)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                            isPulsing = true
                        }
                    }

                    // Status & Countdown Card
                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("STATUS")
                                .font(AppTheme.Typography.caption())
                                .foregroundColor(.white.opacity(0.6))
                            Text(isActive ? "Monitoring" : "Paused")
                                .font(AppTheme.Typography.headline())
                                .foregroundColor(isActive ? AppTheme.Colors.success : AppTheme.Colors.inactive)
                        }
                        
                        Spacer()
                        
                        if isActive {
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("NEXT CHECK")
                                    .font(AppTheme.Typography.caption())
                                    .foregroundColor(.white.opacity(0.6))
                                Text("\(Int(timeUntilNextCheck))s")
                                    .font(AppTheme.Typography.headline())
                                    .foregroundColor(AppTheme.Colors.accent)
                                    .monospacedDigit()
                            }
                        }
                    }
                    .glassStyle()
                    .padding(.horizontal)

                    // Latest Warning Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(AppTheme.Colors.warning)
                            Text("LATEST AI INSIGHT")
                                .font(AppTheme.Typography.caption())
                                .foregroundColor(.white.opacity(0.6))
                        }

                        Text(latestWarning)
                            .font(AppTheme.Typography.body())
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .opacity(warningOpacity)
                    }
                    .glassStyle()
                    .padding(.horizontal)
                    .onChange(of: latestWarning) { _ in
                        withAnimation(.easeInOut(duration: 0.3)) {
                            warningOpacity = 0.3
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation(.easeInOut(duration: 0.5)) {
                                warningOpacity = 1.0
                            }
                        }
                    }

                    Spacer()

                    // Control Button
                    Button(action: toggleActive) {
                        HStack(spacing: 12) {
                            Image(systemName: isActive ? "pause.fill" : "play.fill")
                                .font(.title3)
                            Text(isActive ? "STOP MONITORING" : "START MONITORING")
                                .font(AppTheme.Typography.headline())
                                .tracking(1.2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(isActive ? AppTheme.Colors.danger : AppTheme.Colors.success)
                        .foregroundColor(.white)
                        .cornerRadius(AppTheme.Layout.cornerRadius)
                        .shadow(color: (isActive ? AppTheme.Colors.danger : AppTheme.Colors.success).opacity(0.4), radius: 15, y: 5)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 30)

                    // Error Message
                    if let errorMessage = cameraManager.errorMessage {
                        Text(errorMessage)
                            .font(AppTheme.Typography.caption())
                            .foregroundColor(AppTheme.Colors.danger)
                            .padding(.bottom, 10)
                    }
                }
            }
            .navigationTitle("SafetyGuardian")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.title3)
                            .foregroundColor(.white)
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
            .preferredColorScheme(.dark)
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

// MARK: - App Theme & Design System

struct AppTheme {
    enum Colors {
        static let backgroundGradient = Gradient(colors: [
            Color(hex: "0F172A"), // Slate 900
            Color(hex: "1E293B")  // Slate 800
        ])
        
        static let glassBackground = Color.white.opacity(0.1)
        static let glassBorder = Color.white.opacity(0.2)
        
        static let accent = Color(hex: "38BDF8") // Sky 400
        static let success = Color(hex: "4ADE80") // Green 400
        static let warning = Color(hex: "FBBF24") // Amber 400
        static let danger = Color(hex: "F87171") // Red 400
        static let inactive = Color(hex: "94A3B8") // Slate 400
    }
    
    enum Typography {
        static func title() -> Font {
            .system(.title, design: .rounded).bold()
        }
        
        static func headline() -> Font {
            .system(.headline, design: .rounded)
        }
        
        static func subheadline() -> Font {
            .system(.subheadline, design: .rounded)
        }
        
        static func body() -> Font {
            .system(.body, design: .rounded)
        }
        
        static func caption() -> Font {
            .system(.caption, design: .rounded)
        }
    }
    
    enum Layout {
        static let cornerRadius: CGFloat = 24
        static let padding: CGFloat = 20
        static let glassBlur: CGFloat = 10
    }
}

// MARK: - Hex Color Helper

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - View Modifiers

struct GlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(AppTheme.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Layout.cornerRadius)
                    .stroke(AppTheme.Colors.glassBorder, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
    }
}

extension View {
    func glassStyle() -> some View {
        self.modifier(GlassModifier())
    }
}
