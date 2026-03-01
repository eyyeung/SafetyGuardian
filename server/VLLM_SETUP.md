# vLLM Inference Server Setup

How to serve the fine-tuned Cosmos-Reason2-2B model with a LoRA adapter using vLLM.

## Requirements

- Python 3.10+
- [uv](https://docs.astral.sh/uv/getting-started/installation/)
- NVIDIA GPU with CUDA 12.8+ (tested on L40S)
- LoRA adapter weights (adapter_model.safetensors + config files)

## Setup

**1. Install dependencies:**
```bash
cd server/
uv sync
```

**2. Configure environment:**
```bash
cp .env.example .env
```

Edit `.env`:
```bash
VLLM_API_KEY=your_secret_key_here        # Bearer token for API auth
MODEL_WEIGHTS_PATH=/path/to/lora/weights  # Directory with adapter_model.safetensors
MEDIA_PATH=/path/to/media                 # Path vLLM is allowed to read media from
```

**3. Start the server:**
```bash
./serve_finetuned_model.sh
```

This will kill any existing vLLM process, load your `.env`, sync deps, and start vLLM on port 8000.

## vLLM Command

```bash
vllm serve nvidia/Cosmos-Reason2-2B \
  --enable-lora \
  --lora-modules cosmos-safety=$MODEL_WEIGHTS_PATH \
  --max-lora-rank 64 \
  --allowed-local-media-path $MEDIA_PATH \
  --max-model-len 16384 \
  --media-io-kwargs '{"video": {"num_frames": -1}}' \
  --reasoning-parser qwen3 \
  --api-key $VLLM_API_KEY \
  --port 8000
```

## Stopping the Server

```bash
pkill -f 'vllm serve'
```

## iOS App Configuration

In `app/Config.plist`, set:
```xml
<key>VLLM_SERVER_URL</key>
<string>http://YOUR_SERVER_IP:8000/v1</string>
<key>VLLM_API_KEY</key>
<string>your_secret_key_here</string>
```

The key must match `VLLM_API_KEY` in your server `.env`.

## Model Information

- **Base model**: `nvidia/Cosmos-Reason2-2B` (Qwen3-VL architecture)
- **Adapter**: LoRA fine-tuned for structured hazard detection
- **Adapter name**: `cosmos-safety`
- **Training details**: see `training/TRAINING_PIPELINE.md`

## References

- [vLLM Documentation](https://docs.vllm.ai/en/stable/)
- [vLLM LoRA Support](https://docs.vllm.ai/en/stable/features/lora/)
- [Cosmos-Reason2](https://github.com/NVIDIA/Cosmos)
