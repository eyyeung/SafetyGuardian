# ---
# jupyter:
#   jupytext:
#     cell_metadata_filter: tags,-all
#     formats: ipynb,py:percent
#     text_representation:
#       extension: .py
#       format_name: percent
#       format_version: '1.3'
#       jupytext_version: 1.18.1
# ---

# %%
# SPDX-FileCopyrightText: Copyright (c) 2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

# %% [markdown]
# # SafetyGuardian SFT — Cosmos-Reason2 QLoRA Fine-Tuning
#
# Fine-tunes `nvidia/Cosmos-Reason2-2B` for elderly hazard detection via wearable
# camera glasses. Targets the SafetyGuardian iOS app which expects responses in the
# form `"[hazard], [direction]"` (≤10 words) suitable for text-to-speech playback.
#
# **Key differences from `trl_sft.py`:**
# - Custom dataset from annotated hazard images (`annotations.json`)
# - System + user prompts match the SafetyGuardian app spec exactly
# - Output capped at 30 tokens (`max_new_tokens=30`) matching `AppConfiguration.maxTokens`

# %% [markdown]
# ## Prompts
#
# Taken verbatim from the `CosmosAPI` request body in `app.md`.

# %%
SYSTEM_PROMPT = (
    "You are a safety detection system for wearable glasses. "
    "Analyze the image and provide brief navigation guidance."
)

USER_PROMPT = (
    'Analyze this image for hazards and provide brief navigation guidance '
    'in 10 words or less. Format: "[hazard], [direction]" '
    '(e.g., "ice patch ahead, move rightward"). '
    'Hazards include: ice, wet surfaces, puddles, vehicles, obstacles, '
    'steep slopes, uneven terrain. Keep it VERY concise for text-to-speech output.'
)

# %% [markdown]
# ## Dataset
#
# ### Annotation format (`annotations.json`)
#
# Create a JSON file where each entry is:
# ```json
# [
#   {
#     "image_path": "/abs/path/to/image.jpg",
#     "label": "ice patch ahead, move rightward."
#   },
#   {
#     "image_path": "/abs/path/to/image2.jpg",
#     "label": "puddle on path, move leftward."
#   }
# ]
# ```
#
# **Label guidelines:**
# - Must be ≤10 words
# - Format: `"[hazard description], [direction verb]."` (trailing period)
# - Directions: `move leftward`, `move rightward`, `stop immediately`,
#   `step around it`, `slow down`, `proceed cautiously`, `safe to proceed`
# - Hazard categories: ice, wet surfaces, puddles, vehicles, obstacles,
#   steep slopes, uneven terrain, clear path
#
# **Recommended image sources:**
# - [Hazard Detection Dataset (Roboflow)](https://universe.roboflow.com) — search "hazard detection"
# - [COCO](https://cocodataset.org) — filter for outdoor scenes
# - [ADE20K](https://groups.csail.mit.edu/vision/datasets/ADE20K/) — indoor/outdoor hazards
# - Real footage from wearable glasses (highest quality for this use case)

# %%
import json
from pathlib import Path

from datasets import Dataset
from PIL import Image


def _make_record(image: Image.Image, label: str) -> dict:
    """Convert a single annotated image into TRL-compatible dataset record.

    Uses `prompt` + `completion` + `images` columns (same structure as
    `trl-lib/llava-instruct-mix`) to avoid PyArrow schema conflicts that
    arise when `content` mixes strings and lists in a `messages` column.
    The Qwen3VL processor injects image tokens automatically from the
    `images` column when applying the chat template during training.
    """
    return {
        # `images` column: PIL images — processor injects image tokens into prompt
        "images": [image],
        # `prompt`: conversation up to (not including) the assistant turn
        "prompt": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user",   "content": USER_PROMPT},
        ],
        # `completion`: the target assistant response
        "completion": [
            {"role": "assistant", "content": label},
        ],
    }


def load_annotations(annotation_file: str) -> Dataset:
    """Load hazard annotations from `annotations.json`."""
    with open(annotation_file) as f:
        annotations = json.load(f)

    records = []
    for ann in annotations:
        image = Image.open(ann["image_path"]).convert("RGB")
        records.append(_make_record(image, ann["label"]))

    print(f"Loaded {len(records)} annotated examples")
    return Dataset.from_list(records)


def create_demo_dataset() -> Dataset:
    """
    Synthetic demo dataset using the repo sample image.

    Replace with `load_annotations("annotations.json")` for real training.
    All 8 hazard categories are represented so the model sees every class.
    """
    sample_img_path = Path(__file__).parent.parent.parent / "assets" / "sample.png"
    image = Image.open(sample_img_path).convert("RGB")

    # One example per hazard category — replace images with real per-category photos
    labels = [
        "ice patch ahead, move rightward.",
        "wet floor ahead, proceed cautiously.",
        "puddle on path ahead, move leftward.",
        "vehicle approaching, stop immediately.",
        "obstacle on path, step around it.",
        "steep slope ahead, slow down now.",
        "uneven pavement ahead, watch footing.",
        "clear path ahead, safe to proceed.",
    ]
    print(f"No annotations.json found — using demo dataset ({len(labels)} examples)")
    return Dataset.from_list([_make_record(image, lbl) for lbl in labels])


# %%
annotation_file = "annotations.json"
train_dataset = (
    load_annotations(annotation_file)
    if Path(annotation_file).exists()
    else create_demo_dataset()
)

# Verify format
train_dataset[0]

# %% [markdown]
# ## Load model and configure QLoRA
#
# Same QLoRA config as `trl_sft.py`: 4-bit base model + LoRA adapter.

# %%
import torch
from transformers import BitsAndBytesConfig, Qwen3VLForConditionalGeneration

model_name = "nvidia/Cosmos-Reason2-2B"

model = Qwen3VLForConditionalGeneration.from_pretrained(
    model_name,
    dtype="auto",
    device_map="auto",
    quantization_config=BitsAndBytesConfig(
        load_in_4bit=True,
        bnb_4bit_compute_dtype=torch.float16,
        bnb_4bit_use_double_quant=True,
        bnb_4bit_quant_type="nf4",
    ),
)

# %%
from peft import LoraConfig

peft_config = LoraConfig(
    r=32,
    lora_alpha=32,
    target_modules=["down_proj", "o_proj", "k_proj", "q_proj", "gate_proj", "up_proj", "v_proj"],
)

# %% [markdown]
# ## Train
#
# For a real training run on a collected hazard dataset, switch `max_steps` to
# `num_train_epochs=3` and remove the `max_steps` override.

# %%
from trl import SFTConfig

output_dir = "outputs/Cosmos-Reason2-2B-safety-guardian-sft"

training_args = SFTConfig(
    # Training schedule
    max_steps=10,                       # demo: use num_train_epochs=3 for real training
    per_device_train_batch_size=2,
    gradient_accumulation_steps=8,      # effective batch = 2 * 8 = 16
    warmup_steps=5,
    learning_rate=2e-4,
    optim="adamw_8bit",
    max_length=None,                    # don't truncate — avoids cutting image tokens
    # Output
    output_dir=output_dir,
    logging_steps=1,
    report_to="tensorboard",
)

# %%
from trl import SFTTrainer

trainer = SFTTrainer(
    model=model,
    args=training_args,
    train_dataset=train_dataset,
    peft_config=peft_config,
)

# %%
gpu_stats = torch.cuda.get_device_properties(0)
start_gpu_memory = round(torch.cuda.max_memory_reserved() / 1024 / 1024 / 1024, 3)
max_memory = round(gpu_stats.total_memory / 1024 / 1024 / 1024, 3)
print(f"GPU = {gpu_stats.name}. Max memory = {max_memory} GB.")
print(f"{start_gpu_memory} GB of memory reserved.")

# %%
trainer_stats = trainer.train()

# %%
used_memory = round(torch.cuda.max_memory_reserved() / 1024 / 1024 / 1024, 3)
used_memory_for_lora = round(used_memory - start_gpu_memory, 3)
used_percentage = round(used_memory / max_memory * 100, 3)
lora_percentage = round(used_memory_for_lora / max_memory * 100, 3)

print(f"{trainer_stats.metrics['train_runtime']} seconds used for training.")
print(f"{round(trainer_stats.metrics['train_runtime'] / 60, 2)} minutes used for training.")
print(f"Peak reserved memory = {used_memory} GB.")
print(f"Peak reserved memory for training = {used_memory_for_lora} GB.")
print(f"Peak reserved memory % of max memory = {used_percentage} %.")
print(f"Peak reserved memory for training % of max memory = {lora_percentage} %.")

# %%
trainer.save_model(output_dir)

# %% [markdown]
# ## Load fine-tuned model and run inference
#
# Inference uses `max_new_tokens=30`, matching `AppConfiguration.maxTokens = 30`
# in the SafetyGuardian app. The system + user prompts exactly mirror the
# `CosmosAPI` request body sent by the iPhone app.

# %%
from peft import PeftModel
from transformers import AutoProcessor, Qwen3VLForConditionalGeneration

base_model = model_name
adapter_model = output_dir

model = Qwen3VLForConditionalGeneration.from_pretrained(
    base_model, dtype="auto", device_map="auto"
)
model = PeftModel.from_pretrained(model, adapter_model)
processor = AutoProcessor.from_pretrained(base_model)

# %%
# Use first training image as test — replace with a real hazard frame in production
test_image = train_dataset[0]["images"][0]

messages = [
    {
        "role": "system",
        "content": [{"type": "text", "text": SYSTEM_PROMPT}],
    },
    {
        "role": "user",
        "content": [
            {"type": "image", "image": test_image},
            {"type": "text", "text": USER_PROMPT},
        ],
    },
]

# %%
inputs = processor.apply_chat_template(
    messages,
    tokenize=True,
    add_generation_prompt=True,
    return_dict=True,
    return_tensors="pt",
).to(model.device)

# max_new_tokens=30 matches AppConfiguration.maxTokens in the iOS app
generated_ids = model.generate(**inputs, max_new_tokens=30)
generated_ids_trimmed = [
    out_ids[len(in_ids):] for in_ids, out_ids in zip(inputs.input_ids, generated_ids)
]
output_text = processor.batch_decode(
    generated_ids_trimmed, skip_special_tokens=True, clean_up_tokenization_spaces=False
)
print(output_text)
