#!/bin/bash

# Stop any running vLLM servers
pkill -f 'vllm serve' || true
sleep 5

# Load environment variables
set -a && source "$(dirname "$0")/.env" && set +a

# Validate required env vars
if [ -z "$VLLM_API_KEY" ] || [ -z "$MODEL_WEIGHTS_PATH" ] || [ -z "$MEDIA_PATH" ]; then
  echo "Error: VLLM_API_KEY, MODEL_WEIGHTS_PATH, and MEDIA_PATH must be set in .env"
  exit 1
fi

# Sync dependencies
uv sync

# Start vLLM server
uv run vllm serve nvidia/Cosmos-Reason2-2B \
  --enable-lora \
  --lora-modules cosmos-safety="${MODEL_WEIGHTS_PATH}" \
  --max-lora-rank 64 \
  --allowed-local-media-path "${MEDIA_PATH}" \
  --max-model-len 16384 \
  --media-io-kwargs '{"video": {"num_frames": -1}}' \
  --reasoning-parser qwen3 \
  --api-key "${VLLM_API_KEY}" \
  --port 8000
