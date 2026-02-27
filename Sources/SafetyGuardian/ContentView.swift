//
//  ContentView.swift
//  SafetyGuardian
//
//  Main user interface for SafetyGuardian app
//

import SwiftUI

private enum ServerHealthStatus: Equatable {
    case unknown
    case checking
    case healthy
    case unhealthy(String)

    var label: String {
        switch self {
        case .unknown:
            return "Unknown"
        case .checking:
            return "Checking..."
        case .healthy:
            return "Online"
        case .unhealthy:
            return "Offline"
        }
    }

    var systemImage: String {
        switch self {
        case .unknown:
            return "questionmark.circle"
        case .checking:
            return "arrow.triangle.2.circlepath"
        case .healthy:
            return "checkmark.circle.fill"
        case .unhealthy:
            return "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .unknown:
            return AppTheme.Colors.inactive
        case .checking:
            return AppTheme.Colors.accent
        case .healthy:
            return AppTheme.Colors.success
        case .unhealthy:
            return AppTheme.Colors.danger
        }
    }
}

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var audioPlayer = AudioPlayer()
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @State private var processingState: ProcessingState = .idle
    @State private var latestWarning: String = "No warnings yet"
    @State private var isActive = false
    @State private var timeUntilNextCheck: TimeInterval = 0
    @State private var warningHistory: [WarningHistory] = []
    @State private var showSettings = false
    @State private var processingTask: Task<Void, Never>?
    @State private var countdownTimer: Timer?
    @State private var serverHealthStatus: ServerHealthStatus = .unknown

    private let cosmosAPI = CosmosAPI()
    private let ttsManager = TTSManager()

    @State private var isPulsing = false
    @State private var warningOpacity: Double = 1.0

    var body: some View {
        NavigationView {
            GeometryReader { proxy in
                let isLandscape = proxy.size.width > proxy.size.height
                let isCompact = verticalSizeClass == .compact || isLandscape
                let previewHeight = min(isCompact ? 200 : 350, proxy.size.height * (isCompact ? 0.55 : 0.4))

                ZStack {
                    // Background Gradient
                    LinearGradient(
                        gradient: AppTheme.Colors.backgroundGradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()

                    Group {
                        content(previewHeight: previewHeight, isCompact: isCompact, availableSize: proxy.size)
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
                SettingsView(onSave: {
                    refreshServerHealth()
                })
            }
            .onAppear {
                AppConfiguration.loadSettings()
                setupCamera()
                UIDevice.current.beginGeneratingDeviceOrientationNotifications()
                updateCameraOrientation()
                refreshServerHealth()
            }
            .onDisappear {
                UIDevice.current.endGeneratingDeviceOrientationNotifications()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                updateCameraOrientation()
            }
            .preferredColorScheme(.dark)
        }
    }

    private func updateCameraOrientation() {
        let interfaceOrientation: UIInterfaceOrientation? = UIApplication.shared
            .connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .interfaceOrientation

        if let orientation = interfaceOrientation {
            cameraManager.updateOrientation(orientation)
        } else {
            cameraManager.updateOrientation(UIDevice.current.orientation)
        }
    }

    @ViewBuilder
    private func content(previewHeight: CGFloat, isCompact: Bool, availableSize: CGSize) -> some View {
        Group {
            if isCompact {
                ZStack {
                    CameraPreviewView(image: cameraManager.currentFrame)
                        .frame(width: availableSize.width, height: availableSize.height)
                        .clipped()
                        .ignoresSafeArea()

                    VStack {
                        overlayStatus()
                        Spacer()
                        overlayLatestInsight()
                        controlBlock(isCompact: true)
                            .padding(.bottom, 16)
                    }
                }
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        previewBlock(previewHeight: previewHeight)
                        statusBlock()
                        warningBlock()
                        Spacer(minLength: 0)
                        controlBlock(isCompact: false)
                        errorBlock()
                    }
                    .padding(.top, 12)
                }
            }
        }
    }

    private func previewBlock(previewHeight: CGFloat) -> some View {
        ZStack {
            CameraPreviewView(image: cameraManager.currentFrame)
                .frame(height: previewHeight)
                .cornerRadius(AppTheme.Layout.cornerRadius)
                .shadow(color: isActive ? AppTheme.Colors.accent.opacity(0.3) : .clear, radius: 20)

            VStack {
                overlayStatus()
                Spacer()
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }

    private func statusBlock() -> some View {
        VStack(alignment: .leading, spacing: 10) {
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

                VStack(alignment: .trailing, spacing: 4) {
                    Text("SERVER")
                        .font(AppTheme.Typography.caption())
                        .foregroundColor(.white.opacity(0.6))
                    HStack(spacing: 6) {
                        Image(systemName: serverHealthStatus.systemImage)
                            .foregroundColor(serverHealthStatus.color)
                        Text(serverHealthStatus.label)
                            .font(AppTheme.Typography.headline())
                            .foregroundColor(serverHealthStatus.color)
                    }
                }

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

            if case .unhealthy(let message) = serverHealthStatus {
                Text(message)
                    .font(AppTheme.Typography.caption())
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(2)
            }
        }
        .glassStyle()
        .padding(.horizontal)
    }

    private func warningBlock() -> some View {
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
    }

    private func controlBlock(isCompact: Bool) -> some View {
        Button(action: toggleActive) {
            HStack(spacing: 12) {
                Image(systemName: isActive ? "pause.fill" : "play.fill")
                    .font(.title3)
                Text(isActive ? "STOP MONITORING" : "START MONITORING")
                    .font(AppTheme.Typography.headline())
                    .tracking(1.2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, isCompact ? 12 : 18)
            .background(isActive ? AppTheme.Colors.danger : AppTheme.Colors.success)
            .foregroundColor(.white)
            .cornerRadius(AppTheme.Layout.cornerRadius)
            .shadow(color: (isActive ? AppTheme.Colors.danger : AppTheme.Colors.success).opacity(0.4), radius: 15, y: 5)
        }
        .padding(.horizontal)
        .padding(.bottom, isCompact ? 12 : 30)
    }

    private func errorBlock() -> some View {
        Group {
            if let errorMessage = cameraManager.errorMessage {
                Text(errorMessage)
                    .font(AppTheme.Typography.caption())
                    .foregroundColor(AppTheme.Colors.danger)
                    .padding(.bottom, 10)
            }
        }
    }

    private func overlayStatus() -> some View {
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
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func overlayLatestInsight() -> some View {
        Text(latestWarning)
            .font(AppTheme.Typography.caption())
            .foregroundColor(.white)
            .lineLimit(2)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
            .padding(.horizontal, 16)
            .padding(.top, 12)
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
        refreshServerHealth()
        startProcessingLoop()
    }

    private func stopDetection() {
        processingTask?.cancel()
        processingTask = nil
        countdownTimer?.invalidate()
        countdownTimer = nil
        timeUntilNextCheck = 0
        cameraManager.stopCapture()
        audioPlayer.stopAudio()
        processingState = .idle
    }

    private func refreshServerHealth() {
        serverHealthStatus = .checking
        Task {
            do {
                try await cosmosAPI.checkHealth()
                await MainActor.run {
                    serverHealthStatus = .healthy
                }
            } catch {
                await MainActor.run {
                    serverHealthStatus = .unhealthy(error.localizedDescription)
                }
            }
        }
    }

    private func startProcessingLoop() {
        processingTask?.cancel()
        processingTask = Task {
            while !Task.isCancelled && isActive {
                await processFrame()

                if Task.isCancelled || !isActive {
                    break
                }

                await MainActor.run {
                    timeUntilNextCheck = AppConfiguration.processingInterval
                    startCountdown()
                }

                do {
                    try await Task.sleep(nanoseconds: UInt64(AppConfiguration.processingInterval * 1_000_000_000))
                } catch {
                    break
                }
            }
        }
    }

    @MainActor
    private func startCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
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
            await MainActor.run {
                processingState = .capturing
            }
            let base64Image = await cameraManager.encodeBestFrameBase64(
                duration: AppConfiguration.videoSampleDuration,
                samples: AppConfiguration.videoSampleCount
            )
            guard let base64Image = base64Image else {
                throw SafetyGuardianError.cameraUnavailable
            }

            try Task.checkCancellation()

            // Step 2: Analyze with Cosmos-Reason2
            await MainActor.run {
                processingState = .analyzing
            }
            let warningText = try await cosmosAPI.analyzeFrame(base64Image)

            try Task.checkCancellation()

            // Step 3: Convert to speech
            await MainActor.run {
                processingState = .generatingSpeech
            }
            let audioData = try await ttsManager.convertToSpeech(warningText)

            try Task.checkCancellation()

            // Step 4: Play audio
            let stillActive = await MainActor.run { isActive }
            guard stillActive else { return }
            await MainActor.run {
                processingState = .playingAudio
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
            if error is CancellationError {
                await MainActor.run {
                    processingState = .idle
                }
                return
            }
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
    @State private var videoSampleDuration: Double = AppConfiguration.videoSampleDuration
    @State private var serverURLError: String?
    @State private var hasSavedServerURL: Bool = AppConfiguration.hasSavedVLLMServerURL()

    let onSave: (() -> Void)?

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

                Section(header: Text("Video Sampling")) {
                    VStack(alignment: .leading) {
                        Text("Duration: \(String(format: "%.1f", videoSampleDuration))s")
                            .font(.headline)

                        Slider(value: $videoSampleDuration, in: 0.5...3.0, step: 0.5)

                        HStack {
                            Text("0.5s")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("1.5s")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("3s")
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

                    if let error = serverURLError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(AppTheme.Colors.danger)
                    } else {
                        Text("Example: http://YOUR_IP:8000/v1")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text(hasSavedServerURL ? "Using saved override" : "Using Config.plist default")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section {
                    Button("Save Settings") {
                        if saveSettings() {
                            dismiss()
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                Section {
                    Button("Reset to Config Defaults") {
                        AppConfiguration.resetSettingsToDefaults()
                        processingInterval = AppConfiguration.processingInterval
                        audioVolume = AppConfiguration.audioVolume
                        videoSampleDuration = AppConfiguration.videoSampleDuration
                        serverURL = AppConfiguration.vllmServerURL
                        serverURLError = nil
                        hasSavedServerURL = false
                        onSave?()
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

    @discardableResult
    private func saveSettings() -> Bool {
        if let normalized = AppConfiguration.normalizeVLLMServerURL(serverURL) {
            serverURL = normalized
            serverURLError = nil
        } else {
            serverURLError = "Enter a valid URL (e.g., http://HOST:8000/v1)"
            return false
        }

        AppConfiguration.processingInterval = processingInterval
        AppConfiguration.audioVolume = audioVolume
        AppConfiguration.videoSampleDuration = videoSampleDuration
        AppConfiguration.vllmServerURL = serverURL
        AppConfiguration.saveSettings()
        hasSavedServerURL = true
        onSave?()
        return true
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
