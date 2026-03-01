#!/usr/bin/env python3
"""
Runs Cosmos-Reason2-2B on extracted review frames.
Monitors analysis_queue.json and processes new entries.
Results stored per-video in model_analysis.json.
"""

import json
import os
import time
import sys
from pathlib import Path

REVIEW_DIR = Path("/home/user/cosmos-predict2.5/outputs/review")
MANIFEST_PATH = Path("/home/user/cosmos-predict2.5/assets/base/horizontal_videos/training_manifest.json")
QUEUE_FILE = REVIEW_DIR / "analysis_queue.json"
LOG_FILE = REVIEW_DIR / "analyzer.log"

SYSTEM_PROMPT = (
    "You are a safety detection system for wearable glasses worn by elderly users. "
    "Analyze the image and provide brief safety guidance."
)
USER_PROMPT = (
    "Analyze this image for hazards and provide brief navigation guidance in 10 words or less. "
    'Format: "[hazard], [action]" (e.g., "ice patch ahead, slow down"). '
    "Hazards: ice, wet surfaces, puddles, vehicles, obstacles, slopes, uneven terrain. "
    "Keep VERY concise for text-to-speech. If path is clear and safe, say: \"path clear, safe to proceed\""
)

def log(msg):
    ts = time.strftime("%H:%M:%S")
    line = f"[{ts}] {msg}"
    print(line, flush=True)
    with open(LOG_FILE, "a") as f:
        f.write(line + "\n")

def load_manifest():
    try:
        with open(MANIFEST_PATH) as f:
            data = json.load(f)
        return {entry["name"]: entry for entry in data}
    except Exception:
        return {}

def load_queue():
    if not QUEUE_FILE.exists():
        return []
    with open(QUEUE_FILE) as f:
        return json.load(f)

def save_queue(queue):
    with open(QUEUE_FILE, "w") as f:
        json.dump(queue, f, indent=2)

def analyze_frames_for_video(model, processor, video_name, frame_dir, manifest):
    from PIL import Image
    import torch

    frame_dir = Path(frame_dir)
    frames = sorted(frame_dir.glob("frame_*.jpg"))
    if not frames:
        log(f"  No frames found in {frame_dir}")
        return {}

    meta = manifest.get(video_name, {})
    target_label = meta.get("label", "unknown")

    results = {
        "_video": video_name,
        "_target_label": target_label,
        "_hazard_type": meta.get("hazard_type", "?"),
        "_severity": meta.get("severity", "?"),
        "frames": {}
    }

    for frame_path in frames:
        fname = frame_path.name
        log(f"  Analyzing {fname}...")
        try:
            image = Image.open(frame_path).convert("RGB")
            messages = [
                {"role": "system", "content": SYSTEM_PROMPT},
                {
                    "role": "user",
                    "content": [
                        {"type": "image", "image": image},
                        {"type": "text", "text": USER_PROMPT}
                    ]
                }
            ]
            text = processor.apply_chat_template(
                messages, tokenize=False, add_generation_prompt=True
            )
            inputs = processor(
                text=[text],
                images=[image],
                return_tensors="pt"
            ).to(model.device)

            with torch.no_grad():
                output_ids = model.generate(
                    **inputs,
                    max_new_tokens=30,
                    do_sample=False,
                    temperature=None,
                    top_p=None,
                )

            # Decode only the new tokens
            input_len = inputs["input_ids"].shape[1]
            new_tokens = output_ids[0][input_len:]
            model_output = processor.decode(new_tokens, skip_special_tokens=True).strip()

            results["frames"][fname] = {
                "model_output": model_output,
                "target_label": target_label,
                "match": model_output.lower().strip() == target_label.lower().strip()
            }
            log(f"    → \"{model_output}\" (target: \"{target_label}\")")

        except Exception as e:
            log(f"  ERROR on {fname}: {e}")
            results["frames"][fname] = {"error": str(e)}

    return results

def update_review_log(video_name, results):
    """Append model analysis column to the review log."""
    log_path = REVIEW_DIR / "review_log.md"
    if not log_path.exists():
        return

    lines = log_path.read_text().splitlines()
    new_lines = []
    for line in lines:
        if f"| {video_name} |" in line:
            # Grab first model output as summary
            frames = results.get("frames", {})
            outputs = [v.get("model_output", "") for v in frames.values() if isinstance(v, dict)]
            mid_output = outputs[len(outputs)//2] if outputs else "?"
            # Replace trailing empty columns with model output
            parts = line.rstrip().rstrip("|").rstrip().split("|")
            # Ensure we have enough columns: add Model Analysis column
            while len(parts) < 9:
                parts.append("")
            parts[8] = f" {mid_output} "
            line = "|".join(parts) + "|"
        new_lines.append(line)

    # Add Model Analysis header if not present (find actual header line by content)
    header_idx = next((i for i, l in enumerate(new_lines) if l.startswith("| #")), None)
    if header_idx is not None and "Model Analysis" not in new_lines[header_idx]:
        new_lines[header_idx] = new_lines[header_idx].rstrip("|") + " Model Analysis |"
        if header_idx + 1 < len(new_lines):
            new_lines[header_idx + 1] = new_lines[header_idx + 1].rstrip("|") + "----------------|"

    log_path.write_text("\n".join(new_lines) + "\n")

def main():
    log("=== Frame Analyzer Starting ===")
    log("Loading Cosmos-Reason2-2B model...")

    try:
        from transformers import AutoModelForImageTextToText, AutoProcessor
        import torch

        model_id = "nvidia/Cosmos-Reason2-2B"
        processor = AutoProcessor.from_pretrained(model_id, trust_remote_code=True)
        model = AutoModelForImageTextToText.from_pretrained(
            model_id,
            dtype=torch.bfloat16,
            device_map="auto",
            trust_remote_code=True,
        )
        model.eval()
        log(f"Model loaded on {next(model.parameters()).device}")
    except Exception as e:
        log(f"FATAL: Could not load model: {e}")
        sys.exit(1)

    manifest = load_manifest()
    log(f"Manifest loaded: {len(manifest)} entries")
    log("Watching analysis queue...")

    while True:
        queue = load_queue()
        pending = [item for item in queue if not item.get("done")]

        if pending:
            item = pending[0]
            video_name = item["video_name"]
            frame_dir = item["frame_dir"]

            log(f"Processing: {video_name}")
            results = analyze_frames_for_video(model, processor, video_name, frame_dir, manifest)

            # Save model_analysis.json
            out_path = Path(frame_dir) / "model_analysis.json"
            with open(out_path, "w") as f:
                json.dump(results, f, indent=2)
            log(f"  Saved → review/{video_name}/model_analysis.json")

            # Update review log
            update_review_log(video_name, results)

            # Mark done in queue
            for q_item in queue:
                if q_item["video_name"] == video_name:
                    q_item["done"] = True
            save_queue(queue)

        else:
            # Check if all done
            all_done = queue and all(item.get("done") for item in queue)
            if all_done and len(queue) > 10:
                log("All queued items processed.")
            time.sleep(20)

if __name__ == "__main__":
    main()
