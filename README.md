# SafetyGuardian

AI-powered hazard detection iOS app for elderly safety using camera vision and audio warnings.

**Platform:** iOS 16.0+
**AI Model:** NVIDIA Cosmos-Reason2-2B
**TTS:** ElevenLabs Turbo v2.5

---

## Overview

SafetyGuardian analyzes camera feed in real-time to detect hazards (ice, puddles, obstacles) and provides spoken navigation warnings for elderly users.

## Features

- Real-time camera capture and hazard detection
- AI-powered vision analysis using Cosmos-Reason2-2B
- Natural voice warnings via ElevenLabs TTS
- Configurable processing intervals (5-60s)
- Support for external USB cameras (wearable glasses)
- Background audio playback

## Quick Start

### 1. Setup Configuration

Copy the template and add your credentials:

```bash
cp Config.plist.template Config.plist
```

Edit `Config.plist`:
- `VLLM_SERVER_URL`: Your vLLM server endpoint
- `ELEVENLABS_API_KEY`: Your ElevenLabs API key

### 2. Build and Run

```bash
# Open in Xcode
open SafetyGuardian.xcodeproj

# Build and run on iPhone (⌘R)
# Or build from command line:
xcodebuild -scheme SafetyGuardian \
  -destination 'platform=iOS,name=YOUR_IPHONE' \
  -allowProvisioningUpdates build
```

### 3. Backend Requirements

- vLLM server running Cosmos-Reason2-2B model
- ElevenLabs API account for TTS

See `docs/QUICK_START.md` for detailed setup instructions.

## Architecture

- **SwiftUI** for iOS interface
- **AVFoundation** for camera capture
- **Cosmos-Reason2-2B** via vLLM for hazard detection
- **ElevenLabs API** for text-to-speech

## Documentation

- `docs/QUICK_START.md` - Detailed setup guide
- `docs/CAMERA_SETUP.md` - Physical iPhone camera setup
- `docs/TESTING_GUIDE.md` - Test suite documentation
- `docs/SETUP_ICON.md` - App icon installation

## Project Structure

```
SafetyGuardian/
├── Sources/SafetyGuardian/    # Swift source code
│   ├── SafetyGuardianApp.swift
│   ├── ContentView.swift
│   ├── Configuration.swift
│   ├── Models.swift
│   ├── CameraManager.swift
│   ├── CosmosAPI.swift
│   ├── TTSManager.swift
│   └── AudioPlayer.swift
├── Tests/                     # Unit and integration tests
├── Config.plist.template      # Configuration template
├── Info.plist                 # iOS app metadata
└── docs/                      # Documentation

```

## Security

**All API keys and secrets are in `Config.plist` which is gitignored.**

Never commit:
- `Config.plist` (contains real API keys)
- Build artifacts
- Derived data

## License

NVIDIA Cosmos Cookoff 2026 project

---

Made with ❤️ for elderly safety
