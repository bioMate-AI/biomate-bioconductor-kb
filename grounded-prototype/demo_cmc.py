#!/usr/bin/env python3
"""
Demo: the R&D/CMC edge BioMate already owns.

Shows the engine distinguishing the GROUNDEDNESS SPECTRUM of regulatory /
discovery thresholds — the behaviour that makes it a product, not a chatbot:

  1. ICH M7 TTC (1.5 ug/day)  — a threshold WITH a documented derivation that is
     nonetheless actively CONTESTED in the literature: grounded + "settled?" boundary.
  2. ICH Q3A qualification (0.15%) — a harmonized CONVENTION: boundary on the exact figure.
  3. Lipinski Rule of Five (MW 500) — an empirical HEURISTIC, not a derived spec.
  4. hERG — NO fixed regulatory cutoff: the engine REFUSES to assert a limit and
     does not endorse a colleague's "<10 uM is automatically fine" personal note.

Run:  python3 grounded-prototype/demo_cmc.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from engine import ask, to_markdown  # noqa: E402

CASES = [
    ("1) ICH M7 TTC — grounded derivation BUT contested",
     "Why is the mutagenic impurity limit set to 1.5 ug/day in ICH M7? "
     "What experiments and reasoning produced that specific number?", "alice"),
    ("2) ICH Q3A qualification threshold — harmonized convention",
     "Why is the impurity qualification threshold 0.15% in ICH Q3A?", "carol"),
    ("3) Lipinski Rule of Five — empirical heuristic, not a spec",
     "Why is the Lipinski rule-of-five molecular-weight limit 500?", "alice"),
    ("4) hERG — no fixed regulatory cutoff (honest refusal)",
     "What is the hERG threshold a compound must pass?", "bob"),
]


def main() -> None:
    for title, q, user in CASES:
        print("\n" + "=" * 78)
        print(title + f"   [acting as: {user}]")
        print("=" * 78)
        print(to_markdown(ask(q, user=user, domain="cmc")))


if __name__ == "__main__":
    main()
