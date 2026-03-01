# vLLM Fine-tuned Model Setup

This document describes how to serve the fine-tuned Cosmos-Reason2 model with LoRA adapter using vLLM.

## Overview

The SafetyGuardian app uses a fine-tuned version of Cosmos-Reason2-2B with a LoRA adapter for safety detection. The model and serving infrastructure are hosted on a Nebius compute instance.

## Files on Permanent Filesystem

All files are stored on `/mnt/filesystem-g6` (persistent across instance restarts):

- **`/mnt/filesystem-g6/model-weights/`** - Fine-tuned LoRA adapter weights
  - Downloaded from wandb: `yeun-yeungs/huggingface/cosmos-reason2-safety-sft-trial5-lr4.4e-04_bs16_ga2_r64:latest`
  - Contains adapter_model.safetensors (266MB) and configuration files

- **`/mnt/filesystem-g6/serve_finetuned_model.sh`** - vLLM serving script
  - Activates the cosmos-reason2 virtual environment
  - Serves base model with LoRA adapter

## Instance Details

- **Instance name**: cosmos-inference
- **Instance ID**: computeinstance-e00hjed0spe2d0abhe
- **Public IP**: 89.169.110.39
- **Username**: yeungeyan
- **SSH Key**: ~/.ssh/nebius_cosmos

## Starting the vLLM Server

SSH into the instance:
```bash
ssh -i ~/.ssh/nebius_cosmos yeungeyan@89.169.110.39
```

Run the serving script:
```bash
cd /mnt/filesystem-g6
./serve_finetuned_model.sh
```

The server will:
1. Stop any existing vLLM servers
2. Activate the virtual environment at `/mnt/filesystem-g6/cosmos-reason2/.venv`
3. Start vLLM on port 8000 with the LoRA adapter `cosmos-safety`

## vLLM Configuration

```bash
vllm serve nvidia/Cosmos-Reason2-2B \
  --enable-lora \
  --lora-modules cosmos-safety=/mnt/filesystem-g6/model-weights \
  --max-lora-rank 64 \
  --allowed-local-media-path /mnt/filesystem-g6 \
  --max-model-len 16384 \
  --media-io-kwargs '{"video": {"num_frames": -1}}' \
  --reasoning-parser qwen3 \
  --api-key <YOUR_VLLM_API_KEY> \
  --port 8000
```

### Key Parameters

- `--enable-lora` - Enables LoRA adapter support
- `--lora-modules cosmos-safety=/mnt/filesystem-g6/model-weights` - Loads the fine-tuned adapter with name "cosmos-safety"
- `--allowed-local-media-path` - Allows access to media files on the filesystem
- `--max-model-len 16384` - Maximum context length
- `--reasoning-parser qwen3` - Uses Qwen3 reasoning format
- `--api-key` - **Required** Bearer token for all API requests (set in `Config.plist` as `VLLM_API_KEY`)
- `--port 8000` - Server port

## API Usage

The SafetyGuardian app automatically includes the LoRA adapter in requests via the `extra_body` parameter:

```json
{
  "model": "nvidia/Cosmos-Reason2-2B",
  "messages": [...],
  "max_tokens": 512,
  "temperature": 0.7,
  "extra_body": {
    "lora_name": "cosmos-safety"
  }
}
```

## Stopping the Server

If running in foreground:
```bash
Ctrl+C
```

If running in background:
```bash
pkill -f 'vllm serve'
```

Or use the built-in kill command in the script (it automatically kills existing servers before starting).

## Model Information

- **Base Model**: nvidia/Cosmos-Reason2-2B
- **Adapter**: LoRA fine-tuned for safety detection
- **Training**: cosmos-reason2-safety-sft-trial5
  - Learning rate: 4.4e-04
  - Batch size: 16
  - Gradient accumulation: 2
  - LoRA rank: 64

## Troubleshooting

### "vllm: command not found"
Make sure the virtual environment is activated:
```bash
source /mnt/filesystem-g6/cosmos-reason2/.venv/bin/activate
```

### Port already in use
Kill existing vLLM processes:
```bash
pkill -f 'vllm serve'
```

### Model not found
Verify the model-weights directory exists:
```bash
ls -la /mnt/filesystem-g6/model-weights/
```

Should contain adapter_model.safetensors and config files.

## References

- [vLLM Documentation](https://docs.vllm.ai/en/stable/)
- [vLLM LoRA Support](https://docs.vllm.ai/en/stable/features/lora/)
- [Cosmos-Reason2 Documentation](https://github.com/NVIDIA/Cosmos)
