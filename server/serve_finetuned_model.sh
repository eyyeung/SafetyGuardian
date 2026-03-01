#!/bin/bash

# Stop any running vLLM servers
pkill -f 'vllm serve' || true

# Wait a moment for processes to stop
sleep 5

# Load environment variables
set -a && source "$(dirname "$0")/.env" && set +a

# Sync dependencies
uv sync

# Serve the base model with LoRA adapter
uv run vllm serve nvidia/Cosmos-Reason2-2B \
  --enable-lora \
  --lora-modules cosmos-safety=/mnt/filesystem-g6/model-weights \
  --max-lora-rank 64 \
  --allowed-local-media-path /mnt/filesystem-g6 \
  --max-model-len 16384 \
  --media-io-kwargs '{"video": {"num_frames": -1}}' \
  --reasoning-parser qwen3 \
  --api-key "${VLLM_API_KEY}" \
  --port 8000
