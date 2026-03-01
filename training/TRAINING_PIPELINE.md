# Safety Hazard Detection SFT Pipeline

End-to-end documentation of the data preparation and model fine-tuning pipeline for the Cosmos-Reason2-2B safety hazard detection system for elderly wearable glasses.

## 1. Video Collection and Frame Extraction

### Source Videos
Raw video clips were recorded from first-person perspective wearable glasses across multiple outdoor locations (parks, paths, intersections, bridges, riversides). Each video captures a specific hazard scenario encountered during walking — e.g. a cyclist approaching, an icy patch on the path, a puddle spanning the walkway, or a clear safe path.

Videos were named with a location prefix and hazard descriptor (e.g. `08DC_jogger_ahead`, `00B8_ice_patch`, `E900_child_running`), covering 106 unique scenarios across 11 hazard categories: clear, pedestrian, wet surface, vehicle, obstacle, ice, puddle, narrow path, animal, uneven terrain, and flood.

### Frame Extraction
From each video, **5 representative frames** were extracted at regular intervals (`frame_01.jpg` through `frame_05.jpg`). These frames capture the progression of the scene — from the initial approach to the moment the hazard is fully visible.

Each video directory also includes a `model_analysis.json` containing the base Cosmos-Reason2-2B model's zero-shot analysis of the scene, used as a baseline during the review process.

## 2. Human Review and Frame Filtering

### Review Process
A human reviewer assessed all 106 video scenarios using a structured review log (`review_log.md`). Each video was evaluated on:

- **Hazard type and severity** — confirming or correcting the initial labels
- **Usability rating** (1-5 scale) — assessing video quality, camera angle, and realism
- **Frame selection notes** — specifying which frames to include/exclude
- **Model analysis comparison** — noting where the base model's output diverged from ground truth

### Filtering Criteria
Videos and frames were excluded based on several criteria:

| Reason | Examples | Count |
|--------|----------|-------|
| Low rating (1-2) | Unrealistic scenes, bad camera angles | ~35 videos |
| Sudden camera shifts | `03B1_flood_severe` — non-continuous footage | Excluded |
| Wrong perspective | `00B8_dog_crosses` — dog not visible from FPV angle | Excluded |
| Obstructed view | `320A_dog_leash` — leash blocking camera | Excluded |
| Unusable hazard | `9FA8_*` terrain cracks — too subtle to detect | 5 videos excluded |

### Reviewer Notes Applied
The reviewer provided specific instructions that were applied during dataset construction:

- **"Use frames from where X appears"** — Early frames before the hazard is visible were excluded for many scenarios (e.g. puddles, ice, fallen branches)
- **"Don't use"** — Entire videos rejected for quality issues
- **Label corrections** — Some videos had ambiguous initial labels (marked `?`) that the reviewer clarified through notes (e.g. `gemini_ice_avoided` → ice hazard, `00B8_cyclist_avoided` → vehicle hazard)

After filtering, **66 usable video scenarios** remained, yielding frames for the training dataset.

## 3. Dataset Construction and Formatting

### Initial JSONL Format
The filtered frames were assembled into a JSONL dataset (`training_data.jsonl`) with the chat-template message format expected by the Qwen3-VL architecture:

```json
{
  "messages": [
    {"role": "system", "content": "<system prompt>"},
    {"role": "user", "content": [
      {"type": "image", "image": "/path/to/frame.jpg"},
      {"type": "text", "text": "What do you see in this image?"}
    ]},
    {"role": "assistant", "content": "<response>"}
  ],
  "_meta": {"video": "...", "frame": "frame_03.jpg", "hazard": "ice", "severity": "high"}
}
```

### Response Standardization
The initial assistant responses were free-form and inconsistent (e.g. "path clear, safe to proceed", "icy path ahead, proceed with caution"). These were reformatted into a **structured three-field format**:

```
HAZARD: <type> | SEVERITY: <level> | ACTION: <instruction>
```

Examples:
- `HAZARD: clear | SEVERITY: none | ACTION: proceed safely`
- `HAZARD: ice | SEVERITY: high | ACTION: slow down`
- `HAZARD: vehicle | SEVERITY: critical | ACTION: stop immediately`
- `HAZARD: puddle | SEVERITY: high | ACTION: move right`

### Data Enrichment from Review Log
26 samples with ambiguous or missing labels were enriched using the reviewer's notes:

- **Unknown hazard types** mapped using reviewer context: `gemini_ice_avoided` → ice, `00B8_cyclist_avoided` → vehicle, `3A7A_ice_avoided` → ice
- **Non-actionable descriptions** replaced with proper actions: "extremely slippery" → "stop, do not proceed"; "slippery area" → "slow down, use caution"
- **Severity-action alignment** verified across all 264 samples — no contradictions found

### Early Frame Removal
For **dynamic hazard videos** (where the hazard object appears partway through), early frames (`frame_01`, `frame_02`) were removed because they show a safe scene but carry the hazard label — creating contradictory training signal. This affected 13 video scenarios:

- Cyclists: `00B8_cyclist_avoided`, `4D74_cyclist_fast`, `C77A_cyclist_curve`, `E900_cyclist_approaching`
- Dogs: `08DC_dog_off_leash`, `AC8E_dog_walker`, `E900_dog_running`
- Pedestrians: `08DC_jogger_ahead`, `320A_jogger_group`, `4D74_pedestrian_crossing`, `E900_child_running`
- Vehicles: `320A_child_bike`, `4D74_vehicle_pullout`

**25 misleading samples removed**, reducing the dataset from 289 to 264 samples.

Environmental hazards (ice, wet surface, puddle, obstacle) were kept for all frames since these are visible throughout the video.

## 4. Prompt Engineering

### System Prompt
A format-instructing system prompt was designed to guide the model toward the structured output:

> You are a safety hazard detection assistant for elderly wearable glasses. Analyze the image and respond in exactly this format:
> HAZARD: \<type\> | SEVERITY: \<level\> | ACTION: \<instruction\>
> Where \<type\> is the hazard (e.g. clear, vehicle, pedestrian, ice, puddle, obstacle, wet surface, animal, narrow path, uneven terrain, flood), \<level\> is none/low/medium/high/critical, and \<instruction\> is a brief action.

This replaced the original generic system prompt, explicitly listing the expected hazard types and severity levels to reduce ambiguity.

### Image Resolution Optimization
The original images (1280x720) produced ~890 image tokens per sample, resulting in only **1.8% target token ratio** (17 target tokens out of 957 total). This was identified as a key reason the model was not learning the output format.

Images were resized to **400x400** and the processor configured with `max_pixels=160000`, reducing total tokens to ~300 per sample and improving the target token ratio to **5.6%** — a 3x improvement in training signal density.

## 5. Model Training

### Architecture
- **Base model**: `nvidia/Cosmos-Reason2-2B` (Qwen3-VL architecture)
- **Method**: LoRA fine-tuning via TRL SFTTrainer
- **Precision**: bf16 with gradient checkpointing
- **Hardware**: Single NVIDIA H100 80GB GPU

### LoRA Configuration
```python
LoraConfig(
    r=<rank>,           # searched over [32, 64, 128]
    lora_alpha=<rank>,  # equal to rank
    target_modules=["down_proj", "o_proj", "k_proj", "q_proj",
                     "gate_proj", "up_proj", "v_proj"],
)
```

### Dataset Split
- **Train**: 237 samples (90%)
- **Validation**: 27 samples (10%)
- Shuffled with `random.seed(42)` for reproducibility

### Hyperparameter Search
10-trial Optuna search over:

| Parameter | Search Space |
|-----------|-------------|
| Learning rate | 1e-5 to 5e-4 (log scale) |
| Batch size | 8, 16, 32 |
| Gradient accumulation | 1, 2, 4 |
| LoRA rank | 32, 64, 128 |

Each trial runs for **5 epochs** with cosine LR schedule and 10% warmup. OOM configurations are automatically pruned.

### Final Training
The best hyperparameters from the search are used for a **20-epoch** final training run with:
- `adamw_8bit` optimizer (memory-efficient for the longer run)
- Best 3 checkpoints saved based on eval loss
- Generation samples logged to wandb every 2 epochs

### Monitoring
All training is tracked via Weights & Biases:
- Train/eval loss curves
- Token accuracy metrics
- **Generation tables**: model outputs on 8 validation samples logged at pre-training baseline, every 2 epochs, and at the final epoch — enabling visual comparison of how the model's output format evolves during training

## 6. Final Dataset Statistics

| Metric | Value |
|--------|-------|
| Total samples | 264 |
| Unique video scenarios | 66 |
| Frames per video | 3-5 |
| Avg tokens per sample | ~300 (after resize) |
| Target token ratio | 5.6% |

### Hazard Distribution
| Hazard | Count | Severity Spread |
|--------|-------|----------------|
| clear | 50 | all none |
| wet surface | 43 | low to critical |
| pedestrian | 37 | low to critical |
| obstacle | 32 | medium to high |
| vehicle | 23 | medium to critical |
| ice | 23 | medium to critical |
| puddle | 21 | medium to critical |
| narrow path | 18 | low to high |
| animal | 9 | low to high |
| uneven terrain | 5 | medium to high |
| flood | 3 | high to critical |

### Severity Distribution
| Severity | Count |
|----------|-------|
| none | 50 |
| low | 27 |
| medium | 80 |
| high | 75 |
| critical | 32 |
