"""
build_data.py — the labeled-set builder.

Materialises the synthetic labeled set (positives / negatives / hard-negatives with
ground-truth labels) into ``data.jsonl``, the RealBio task's ground-truth file. The set
is fully deterministic, so re-running reproduces the committed file byte-for-byte.

    python3.9 build_data.py [--n 20] [--out data.jsonl]
"""
from __future__ import annotations

import argparse
import json
import os
from typing import Any, Dict, List

try:
    from .injectors import generate_items, ARCHETYPES
except ImportError:  # bare script
    from injectors import generate_items, ARCHETYPES  # type: ignore

_HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_OUT = os.path.join(_HERE, "data.jsonl")


def build(n_per_class: int = 20) -> List[Dict[str, Any]]:
    return generate_items(n_per_class=n_per_class)


def write_jsonl(items: List[Dict[str, Any]], path: str) -> None:
    with open(path, "w") as fh:
        for it in items:
            fh.write(json.dumps(it) + "\n")


def summarize(items: List[Dict[str, Any]]) -> str:
    lines = [f"{len(items)} items across {len(ARCHETYPES)} archetypes:"]
    by: Dict[str, Dict[str, int]] = {}
    for it in items:
        by.setdefault(it["archetype"], {}).setdefault(it["label"], 0)
        by[it["archetype"]][it["label"]] += 1
    for arch, d in by.items():
        parts = ", ".join(f"{k}={v}" for k, v in sorted(d.items()))
        lines.append(f"  {arch:<24} {parts}")
    return "\n".join(lines)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=20, help="items per (archetype, label) class")
    ap.add_argument("--out", default=DEFAULT_OUT)
    args = ap.parse_args()
    items = build(args.n)
    write_jsonl(items, args.out)
    print(summarize(items))
    print(f"wrote {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
