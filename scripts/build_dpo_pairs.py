"""
DPO pair-collection harness for v7 — builds (prompt, chosen, rejected) triples
gated by the v2 checklist deterministic checkers.

Two construction paths:

  --mode synthetic
    Offline; takes existing checker-passing SFT examples (task5-9) and
    constructs adversarial rejected variants by deterministic mutations
    (wrong arithmetic, missing subsections, wrong adversity category). No
    GPU required. Volume = same as input task pool.

  --mode rejection-sample
    Online; samples N high-temperature completions from v6 adapter per
    prompt, partitions by checker pass/fail, pairs first-pass with
    first-fail. Requires GPU + trained v6 adapter.

Output schema (HuggingFace DPO trainer compatible):
    {"prompt": str, "chosen": str, "rejected": str, "meta": {...}}

Usage:
    python scripts/build_dpo_pairs.py --mode synthetic
    python scripts/build_dpo_pairs.py --mode rejection-sample \\
        --adapter models/regulatory_llm_v6/lora_adapter
"""
from __future__ import annotations

import argparse
import json
import random
import re
import sys
from pathlib import Path
from typing import Callable

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend" / "lib"))

from galaxy.ai.drug_discovery.adversity_language import (
    CATEGORY_PATTERNS, detect_adversity,
)
from galaxy.ai.drug_discovery.mrsd_verifier import BSA_DIVISOR, verify_mrsd
from galaxy.ai.drug_discovery.phase_gating import required_studies, verify_phase_gating
from galaxy.ai.drug_discovery.structural_validator import (
    REQUIRED_SUBSECTIONS, validate_structure,
)
from galaxy.ai.drug_discovery.tabulated_summary import verify_table

TASKS_DIR = ROOT / "data/regulatory_training/tasks"

# ---------------------------------------------------------------------------
# Synthetic adversarial mutators — produce rejected variants from passing text
# ---------------------------------------------------------------------------


def mutate_mrsd(text: str, rng: random.Random) -> str | None:
    """Inject an arithmetic error: scale HED by random factor."""
    m = re.search(r"HED\s+of\s+(\d+\.\d+)\s*mg/kg", text)
    if not m:
        return None
    correct = float(m.group(1))
    bad = correct * rng.choice([0.3, 0.5, 2.0, 3.0])
    return text.replace(m.group(0), f"HED of {bad:.2f} mg/kg")


def mutate_skeleton(text: str, rng: random.Random) -> str | None:
    """Delete one required subsection heading + its body."""
    paragraphs = text.split("\n\n")
    if len(paragraphs) < 4:
        return None
    drop_idx = rng.randint(1, len(paragraphs) - 2)  # don't drop first/last
    return "\n\n".join(p for i, p in enumerate(paragraphs) if i != drop_idx)


def mutate_phase_gating(text: str, rng: random.Random) -> str | None:
    """Remove 1-2 required study bullets."""
    lines = text.split("\n")
    bullet_indices = [i for i, l in enumerate(lines) if l.lstrip().startswith("-")]
    if len(bullet_indices) < 4:
        return None
    to_drop = set(rng.sample(bullet_indices, rng.randint(1, min(2, len(bullet_indices) - 3))))
    return "\n".join(l for i, l in enumerate(lines) if i not in to_drop)


def mutate_tabulated(text: str, rng: random.Random) -> str | None:
    """Drop one column from the markdown table header + every row."""
    lines = text.split("\n")
    header_idx = next((i for i, l in enumerate(lines)
                       if l.strip().startswith("|") and "|" in l[1:]), None)
    if header_idx is None:
        return None
    cols = [c for c in lines[header_idx].split("|")[1:-1]]
    if len(cols) < 4:
        return None
    drop = rng.randint(1, len(cols) - 2)  # not first, not last
    out = []
    for i, line in enumerate(lines):
        if line.strip().startswith("|") and "|" in line[1:]:
            cells = line.split("|")
            del cells[drop + 1]
            out.append("|".join(cells))
        else:
            out.append(line)
    return "\n".join(out)


def mutate_adversity(text: str, target_category: str, rng: random.Random) -> str | None:
    """Replace the correct adversity phrase with one from a different category."""
    wrong_categories = [c for c in CATEGORY_PATTERNS if c != target_category]
    wrong_cat = rng.choice(wrong_categories)
    wrong_phrases = {
        "no_findings": "no findings were observed",
        "non_adverse_findings": "findings were considered non-adverse",
        "no_test_article_related": "no test-article-related findings",
        "adverse_findings": "adverse findings identified; NOAEL of 100 mg/kg/day",
        "noael_not_established": "the NOAEL was not established",
    }
    return wrong_phrases[wrong_cat]  # whole-output replacement (semantic shift)


TASK_MUTATORS: dict[str, Callable] = {
    "mrsd_computation":   mutate_mrsd,
    "skeleton_completion": mutate_skeleton,
    "phase_gating":       mutate_phase_gating,
    "tabulated_summary":  mutate_tabulated,
    "adversity_language": mutate_adversity,
}


def verify_pair(task: str, chosen: str, rejected: str, meta: dict) -> bool:
    """chosen must pass; rejected must fail. Both must differ."""
    if chosen.strip() == rejected.strip():
        return False
    if task == "mrsd_computation":
        return verify_mrsd(chosen).passed and not verify_mrsd(rejected).passed
    if task == "skeleton_completion":
        sec = meta["section_id"]
        return (validate_structure(chosen, sec).passed
                and not validate_structure(rejected, sec).passed)
    if task == "phase_gating":
        req = required_studies(meta["phase"], meta["trial_duration_days"], meta["population"])
        return (verify_phase_gating(chosen, req).passed
                and not verify_phase_gating(rejected, req).passed)
    if task == "tabulated_summary":
        tid = meta["template_id"]
        return verify_table(chosen, tid).passed and not verify_table(rejected, tid).passed
    if task == "adversity_language":
        cat = meta["adversity_category"]
        return (detect_adversity(chosen).detected == cat
                and detect_adversity(rejected).detected != cat)
    return False


# ---------------------------------------------------------------------------
# Synthetic mode
# ---------------------------------------------------------------------------


def build_synthetic_pairs(rng: random.Random, out_path: Path):
    task_files = {
        "mrsd_computation":    "task5_mrsd_computation.jsonl",
        "skeleton_completion": "task6_skeleton_completion.jsonl",
        "phase_gating":        "task7_phase_gating.jsonl",
        "tabulated_summary":   "task8_tabulated_summary.jsonl",
        "adversity_language":  "task9_adversity_language.jsonl",
    }
    written, skipped = 0, 0
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w") as f:
        for task, fname in task_files.items():
            path = TASKS_DIR / fname
            if not path.exists():
                continue
            for line in path.open():
                row = json.loads(line)
                user_prompt = row["messages"][1]["content"]
                chosen = row["messages"][2]["content"]
                meta = row["meta"]
                mutator = TASK_MUTATORS[task]
                if task == "adversity_language":
                    rejected = mutator(chosen, meta["adversity_category"], rng)
                else:
                    rejected = mutator(chosen, rng)
                if rejected is None or not verify_pair(task, chosen, rejected, meta):
                    skipped += 1
                    continue
                pair = {
                    "prompt": user_prompt,
                    "chosen": chosen,
                    "rejected": rejected,
                    "meta": {"task": task, **meta},
                }
                f.write(json.dumps(pair) + "\n")
                written += 1
    print(f"Synthetic DPO pairs: {written} written, {skipped} skipped")
    print(f"Output: {out_path}")


# ---------------------------------------------------------------------------
# Rejection-sampling mode (requires v6 adapter)
# ---------------------------------------------------------------------------


def build_rejection_sample_pairs(
    rng: random.Random, adapter_path: Path, out_path: Path, n_samples: int = 8,
):
    import torch
    from peft import PeftModel
    from transformers import AutoModelForCausalLM, AutoTokenizer

    print(f"Loading v6 adapter from {adapter_path}...")
    tokenizer = AutoTokenizer.from_pretrained("Qwen/Qwen3-8B")
    base = AutoModelForCausalLM.from_pretrained(
        "Qwen/Qwen3-8B", torch_dtype=torch.bfloat16, device_map="auto",
    )
    model = PeftModel.from_pretrained(base, str(adapter_path))
    model.eval()

    train_path = ROOT / "data/regulatory_training/tasks/splits_v6/train.jsonl"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    written = 0
    with out_path.open("w") as f:
        for line in train_path.open():
            row = json.loads(line)
            task = row["meta"].get("task")
            if task not in TASK_MUTATORS:
                continue

            prompt_msgs = row["messages"][:2]
            text = tokenizer.apply_chat_template(
                prompt_msgs, tokenize=False, add_generation_prompt=True,
            )
            inputs = tokenizer(text, return_tensors="pt").to(model.device)

            passing, failing = [], []
            with torch.no_grad():
                for _ in range(n_samples):
                    out = model.generate(
                        **inputs, max_new_tokens=512,
                        do_sample=True, temperature=0.9, top_p=0.95,
                        pad_token_id=tokenizer.eos_token_id,
                    )
                    gen = tokenizer.decode(
                        out[0][inputs.input_ids.shape[1]:], skip_special_tokens=True,
                    )
                    if verify_pair(task, gen, "DUMMY_FAIL_X", row["meta"]):
                        # gen passes; use as chosen candidate
                        passing.append(gen)
                    else:
                        failing.append(gen)

            if not passing or not failing:
                continue
            chosen = passing[0]
            rejected = failing[0]
            if verify_pair(task, chosen, rejected, row["meta"]):
                f.write(json.dumps({
                    "prompt": row["messages"][1]["content"],
                    "chosen": chosen,
                    "rejected": rejected,
                    "meta": {"task": task, **row["meta"]},
                }) + "\n")
                written += 1
                if written % 25 == 0:
                    print(f"  [{written} pairs]")
    print(f"Rejection-sampled DPO pairs: {written}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=["synthetic", "rejection-sample"], default="synthetic")
    ap.add_argument("--adapter", type=Path, default=None)
    ap.add_argument("--out", type=Path, default=None)
    ap.add_argument("--seed", type=int, default=20260511)
    args = ap.parse_args()

    rng = random.Random(args.seed)
    if args.out is None:
        args.out = ROOT / f"data/regulatory_training/dpo/{args.mode}_pairs.jsonl"

    if args.mode == "synthetic":
        build_synthetic_pairs(rng, args.out)
    else:
        if args.adapter is None:
            sys.exit("--adapter required for rejection-sample mode")
        build_rejection_sample_pairs(rng, args.adapter, args.out)


if __name__ == "__main__":
    main()
