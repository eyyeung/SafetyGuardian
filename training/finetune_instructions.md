# SafetyGuardian — Cosmos-Reason2-2B Fine-tuning Test

## Goal
Fine-tune **Cosmos-Reason2-2B** (a Qwen2.5-VL-based vision-language model) to output
short safety warnings (≤10 words) from wearable chest-camera frames.

The app sends a JPEG frame every 20 seconds and expects a response like:
`"icy path ahead, stop walking"`

---

## Sample Data Provided

| File | Description |
|------|-------------|
| `gemini_ice_avoided.mp4` | Source generated video (icy park path, person approaches and stops) |
| `frames/frame_001.jpg` | Frame at ~0s — starting view, path with light snow |
| `frames/frame_002.jpg` | Frame at ~0.8s — walking forward on icy surface |
| `frames/frame_003.jpg` | Frame at ~2.1s — icy path more prominent |
| `frames/frame_004.jpg` | Frame at ~3.3s — feet visible, approaching hazard |

**Scenario:** `gemini_ice_avoided` — icy snow-covered park path, person slows and stops.
**Hazard type:** ice
**Severity:** high

---

## Training Data Format

Cosmos-Reason2-2B is built on **Qwen2.5-VL**. Fine-tuning uses its standard
instruction-following format with a vision input.

### Single-turn format (for each frame):

```json
{
  "messages": [
    {
      "role": "system",
      "content": "You are a safety detection system for wearable glasses worn by elderly users. Analyze the image and provide brief safety guidance."
    },
    {
      "role": "user",
      "content": [
        {
          "type": "image",
          "image": "<path_or_base64_of_frame>"
        },
        {
          "type": "text",
          "text": "Analyze this image for hazards and provide brief navigation guidance in 10 words or less. Format: \"[hazard], [action]\" (e.g., \"ice patch ahead, slow down\"). Hazards: ice, wet surfaces, puddles, vehicles, obstacles, slopes, uneven terrain. Keep VERY concise for text-to-speech."
        }
      ]
    },
    {
      "role": "assistant",
      "content": "icy path ahead, stop walking"
    }
  ]
}
```

### Per-frame labels for this sample:

| Frame | Label (assistant response) |
|-------|---------------------------|
| `frame_001.jpg` | `"snowy path ahead, slow down"` |
| `frame_002.jpg` | `"icy surface, slow your pace"` |
| `frame_003.jpg` | `"icy path ahead, stop walking"` |
| `frame_004.jpg` | `"icy path ahead, do not proceed"` |

---

## Training Script Approach (LLaMA-Factory / ms-swift)

Cosmos-Reason2-2B is Qwen2.5-VL-2B under the hood. Use either:

### Option A: ms-swift (recommended for Qwen2.5-VL)

```bash
pip install ms-swift

swift sft \
  --model_type qwen2_5_vl \
  --model_id_or_path nvidia/Cosmos-Reason2-2B \
  --dataset /path/to/train_data.json \
  --output_dir ./output \
  --num_train_epochs 3 \
  --per_device_train_batch_size 1 \
  --gradient_accumulation_steps 8 \
  --learning_rate 1e-5 \
  --lora_rank 8 \
  --lora_alpha 32 \
  --freeze_vit True \
  --max_length 512
```

### Option B: LLaMA-Factory

```bash
llamafactory-cli train \
  --model_name_or_path nvidia/Cosmos-Reason2-2B \
  --template qwen2_vl \
  --finetuning_type lora \
  --dataset safety_frames \
  --output_dir ./lora_output \
  --num_train_epochs 3 \
  --lora_rank 8
```

---

## Dataset JSON File (`train_data.json`)

Create a JSONL file with one entry per frame:

```jsonl
{"messages": [{"role": "system", "content": "You are a safety detection system for wearable glasses worn by elderly users. Analyze the image and provide brief safety guidance."}, {"role": "user", "content": [{"type": "image", "image": "frames/frame_001.jpg"}, {"type": "text", "text": "Analyze this image for hazards and provide brief navigation guidance in 10 words or less. Format: \"[hazard], [action]\". Keep VERY concise for text-to-speech."}]}, {"role": "assistant", "content": "snowy path ahead, slow down"}]}
{"messages": [{"role": "system", "content": "You are a safety detection system for wearable glasses worn by elderly users. Analyze the image and provide brief safety guidance."}, {"role": "user", "content": [{"type": "image", "image": "frames/frame_002.jpg"}, {"type": "text", "text": "Analyze this image for hazards and provide brief navigation guidance in 10 words or less. Format: \"[hazard], [action]\". Keep VERY concise for text-to-speech."}]}, {"role": "assistant", "content": "icy surface, slow your pace"}]}
{"messages": [{"role": "system", "content": "You are a safety detection system for wearable glasses worn by elderly users. Analyze the image and provide brief safety guidance."}, {"role": "user", "content": [{"type": "image", "image": "frames/frame_003.jpg"}, {"type": "text", "text": "Analyze this image for hazards and provide brief navigation guidance in 10 words or less. Format: \"[hazard], [action]\". Keep VERY concise for text-to-speech."}]}, {"role": "assistant", "content": "icy path ahead, stop walking"}]}
{"messages": [{"role": "system", "content": "You are a safety detection system for wearable glasses worn by elderly users. Analyze the image and provide brief safety guidance."}, {"role": "user", "content": [{"type": "image", "image": "frames/frame_004.jpg"}, {"type": "text", "text": "Analyze this image for hazards and provide brief navigation guidance in 10 words or less. Format: \"[hazard], [action]\". Keep VERY concise for text-to-speech."}]}, {"role": "assistant", "content": "icy path ahead, do not proceed"}]}
```

---

## Validation Test

After fine-tuning, test with a held-out frame:

```python
from transformers import Qwen2VLForConditionalGeneration, AutoProcessor
from PIL import Image

model = Qwen2VLForConditionalGeneration.from_pretrained("./lora_output")
processor = AutoProcessor.from_pretrained("nvidia/Cosmos-Reason2-2B")

image = Image.open("frames/frame_003.jpg")
messages = [
    {"role": "system", "content": "You are a safety detection system for wearable glasses worn by elderly users."},
    {"role": "user", "content": [
        {"type": "image", "image": image},
        {"type": "text", "text": "Analyze this image for hazards in 10 words or less. Format: \"[hazard], [action]\""}
    ]}
]

text = processor.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)
inputs = processor(text=[text], images=[image], return_tensors="pt")
output = model.generate(**inputs, max_new_tokens=30)
print(processor.decode(output[0], skip_special_tokens=True))
```

**Expected output:** `"icy path ahead, stop walking"` (or similar)

---

## Key Parameters to Note

| Parameter | Value | Reason |
|-----------|-------|--------|
| Base model | `nvidia/Cosmos-Reason2-2B` | Qwen2.5-VL-2B fine-tune |
| LoRA rank | 8 | Lightweight, preserves base capabilities |
| Freeze ViT | Yes | Only fine-tune language head on new labels |
| Max tokens | 30 | Labels are ≤10 words |
| Batch size | 1 + grad accum 8 | Memory constraint on single GPU |

---

## Full Pipeline (once all 96 videos are generated)

1. Extract 4 frames per video × 96 videos = **~384 training samples**
2. Assign labels from `training_manifest.json` (already created)
3. Build JSONL with frame path + label per entry
4. Fine-tune with LoRA for 3 epochs
5. Evaluate on held-out frames from unseen base videos
