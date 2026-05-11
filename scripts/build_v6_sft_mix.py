"""
Build the v6 SFT mix: combine existing prose corpus (task1+3) with new
checker-grounded tasks (task5-9), stratify train/dev/test by task.

Stratified splits ensure every task is represented in dev/test for separate
per-task evaluation.

Usage:
    python scripts/build_v6_sft_mix.py
"""
from __future__ import annotations

import json
import random
import sys
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TASKS_DIR = ROOT / "data" / "regulatory_training" / "tasks"
OUT_DIR = TASKS_DIR / "splits_v6"

# Input task files and their relative mixing weight (= proportion of train pool).
# Weighting boosts checker-grounded tasks so the model sees them often enough
# to learn the skill, without overwhelming the prose corpus.
TASK_WEIGHTS: dict[str, float] = {
    "task1_section_generation.jsonl":   1.0,  # 532 — existing prose
    "task3_region_adaptation.jsonl":    1.0,  # 1280 — existing prose
    "task5_mrsd_computation.jsonl":     2.0,  # 500 — boost (high-impact)
    "task6_skeleton_completion.jsonl":  1.5,  # 1288 — moderate boost
    "task7_phase_gating.jsonl":         2.0,  # 300 — boost
    "task8_tabulated_summary.jsonl":    2.0,  # 300 — boost
    "task9_adversity_language.jsonl":   2.0,  # 300 — boost
}

DEV_FRAC = 0.05
TEST_FRAC = 0.05
SEED = 20260511


def load_jsonl(path: Path) -> list[dict]:
    return [json.loads(l) for l in path.open()]


def task_label_of(row: dict, source_file: str) -> str:
    """Stable per-row task label (for stratification)."""
    meta_task = row.get("meta", {}).get("task")
    if meta_task:
        return meta_task
    return source_file.replace(".jsonl", "")


def main():
    rng = random.Random(SEED)
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    # Per-task pools (stratify on the task label)
    pools: dict[str, list[dict]] = defaultdict(list)

    for fname, weight in TASK_WEIGHTS.items():
        path = TASKS_DIR / fname
        if not path.exists():
            print(f"  WARN: {fname} not found, skipping")
            continue
        rows = load_jsonl(path)
        rng.shuffle(rows)
        # Apply weight by duplication
        n_keep = int(len(rows) * weight)
        if weight >= 1.0:
            sampled = rows * int(weight)
            sampled = sampled + rng.sample(rows, n_keep - len(sampled)) if n_keep > len(sampled) else sampled[:n_keep]
        else:
            sampled = rng.sample(rows, n_keep)
        for r in sampled:
            label = task_label_of(r, fname)
            pools[label].append(r)
        print(f"  {fname}: {len(rows)} rows × weight {weight} → {len(sampled)} contributed")

    train, dev, test = [], [], []
    for task, rows in pools.items():
        rng.shuffle(rows)
        n = len(rows)
        n_dev = max(1, int(n * DEV_FRAC))
        n_test = max(1, int(n * TEST_FRAC))
        dev.extend(rows[:n_dev])
        test.extend(rows[n_dev:n_dev + n_test])
        train.extend(rows[n_dev + n_test:])

    rng.shuffle(train)
    rng.shuffle(dev)
    rng.shuffle(test)

    for name, split in [("train", train), ("dev", dev), ("test", test)]:
        out = OUT_DIR / f"{name}.jsonl"
        with out.open("w") as f:
            for r in split:
                f.write(json.dumps(r) + "\n")
        print(f"{name}: {len(split)} rows → {out}")

    print("\nPer-task counts in dev:")
    for task, count in Counter(task_label_of(r, "") for r in dev).most_common():
        print(f"  {task}: {count}")

    print("\nPer-task counts in test:")
    for task, count in Counter(task_label_of(r, "") for r in test).most_common():
        print(f"  {task}: {count}")


if __name__ == "__main__":
    main()
