# SafetyGuardian

<img src="logo.png" alt="SafetyGuardian logo" width="100" height="100" />

AI-powered hazard detection iOS app for elderly safety using camera vision and audio warnings.

**Team:** The Yeungs — Winnie Yeung & Eyan Yeung
**Competition:** [NVIDIA Cosmos Cookoff](https://github.com/orgs/nvidia-cosmos/discussions/4)

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
- `VLLM_SERVER_URL`: Your vLLM server endpoint (e.g. `http://89.169.110.39:8000/v1`)
- `VLLM_API_KEY`: Your vLLM Bearer token (must match `VLLM_API_KEY` in server `.env`)
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

### 3. Inference Server Setup

The app connects to a vLLM server hosting the fine-tuned Cosmos-Reason2-2B model with a LoRA adapter. To run the inference server on a GPU instance (e.g. Nebius L40S):

**Prerequisites:**
- Python 3.10+
- [uv](https://docs.astral.sh/uv/getting-started/installation/) installed
- CUDA 12.8 compatible GPU

**Install dependencies:**
```bash
uv sync
```

**Configure your API key:**
```bash
cp .env.example .env   # then set VLLM_API_KEY to a secret value
```

**Start the server:**
```bash
./serve_finetuned_model.sh
```

This will:
1. Kill any existing vLLM processes
2. Load `.env` for the API key
3. Run `uv sync` to install dependencies
4. Start vLLM on port 8000 with the `cosmos-safety` LoRA adapter

**Update `Config.plist`** with your server's address and API key:
```xml
<key>VLLM_SERVER_URL</key>
<string>http://YOUR_SERVER_IP:8000/v1</string>
<key>VLLM_API_KEY</key>
<string>your_api_key_here</string>
```

See `VLLM_SETUP.md` for full details on model weights and server configuration.

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
├── app/                            # iOS app
│   ├── SafetyGuardian.xcodeproj
│   ├── Sources/SafetyGuardian/     # Swift source code
│   │   ├── SafetyGuardianApp.swift
│   │   ├── ContentView.swift
│   │   ├── Configuration.swift
│   │   ├── Models.swift
│   │   ├── CameraManager.swift
│   │   ├── CosmosAPI.swift
│   │   ├── TTSManager.swift
│   │   └── AudioPlayer.swift
│   ├── Tests/                      # Unit and integration tests
│   ├── Config.plist.template       # Configuration template (copy to Config.plist)
│   └── Info.plist
├── inference/                      # vLLM inference server
│   ├── serve_finetuned_model.sh    # Server startup script
│   ├── pyproject.toml              # Python dependencies
│   ├── VLLM_SETUP.md              # Detailed server setup guide
│   └── .env.example                # Environment variable template
├── README.md
└── logo.png
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
