#!/usr/bin/env python3
"""
Generate REAL engine output for the Grounded Standards Assistant demo video.

Runs the actual engine.ask() over the CMC domain pack for three manufacturing/CMC
scenarios and writes demo_data.json (via engine.to_dict). The demo HTML renders
exactly this output — nothing is hand-authored, so the video shows genuine
behaviour (tiered provenance, honest boundary, tenant isolation).

Run:  python3 grounded-prototype/demo/gen_demo_data.py
"""

import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

from engine.engine import ask, to_dict  # noqa: E402

# Three beats, each a real question answered over the real CMC pack.
SCENARIOS = [
    {
        "beat": "Defend the number",
        "user": "alice",
        "caption": "A CMC scientist asks WHY a regulatory limit is the number it is — "
                   "and what work produced it.",
        "question": "Why is the mutagenic-impurity acceptable intake set at 1.5 µg/day, "
                    "and what work produced that number?",
    },
    {
        "beat": "Honest boundary",
        "user": "alice",
        "caption": "When the record sets no number, the assistant says so — it does not invent one.",
        "question": "What hERG limit must a compound pass before it can progress?",
    },
    {
        "beat": "Provenance isolation",
        "user": "carol",
        "caption": "Carol asks the same thing. A colleague's unverified personal note exists — "
                   "it must never leak across users or be cited as authority.",
        "question": "Is anything under 10 µM hERG automatically fine to progress?",
    },
]


def main():
    out = []
    for s in SCENARIOS:
        ans = ask(s["question"], user=s["user"], domain="cmc")
        out.append({
            "beat": s["beat"],
            "user": s["user"],
            "caption": s["caption"],
            "answer": to_dict(ans),
        })
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "demo_data.json")
    with open(path, "w") as f:
        json.dump(out, f, indent=2)
    print("wrote", path)
    # quick sanity echo
    for b in out:
        a = b["answer"]
        iso = a["isolation"] or {}
        print(f"\n[{b['beat']}] user={b['user']} grade={a['grade']} "
              f"claims={len(a['claims'])} boundaries={len(a['boundaries'])} "
              f"blocked={iso.get('other_tenant_personal_blocked')}")


if __name__ == "__main__":
    main()
