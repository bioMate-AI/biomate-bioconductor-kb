#!/usr/bin/env python3
"""
Demo: the EN 285 steam-dryness example the video is about.

Run:
    python3 grounded-prototype/demo.py

It shows three things:
  1. The RATIONALE question — "why is the dryness threshold 0.95, what work
     produced it" — answered with a provenance chain AND an explicit boundary
     routing to the standards committee / PDA / ISPE. This is the behaviour the
     blogger found missing in a generic AI.
  2. Tenant isolation — the same engine, queried by "alice", never surfaces
     "bob"'s private note (and vice-versa).
  3. A plain NORMATIVE question for contrast (fully grounded, grade HIGH).
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from engine import ask, to_markdown  # noqa: E402


def banner(title: str) -> None:
    print("\n" + "=" * 78)
    print(title)
    print("=" * 78)


def main() -> None:
    banner("1) RATIONALE — 'why is the dryness value set to 0.95? what work produced it?'")
    ans = ask(
        "Why is the steam dryness value threshold set to 0.95 in EN 285? "
        "What experiments and committee work produced that specific number?",
        user="alice",
    )
    print(to_markdown(ans))

    banner("2) ISOLATION — 'bob' asks the same thing; alice's private note must NOT appear")
    ans_bob = ask(
        "Why is the dryness value 0.95? Is there really a study behind it?",
        user="bob",
    )
    print(to_markdown(ans_bob))

    banner("3) NORMATIVE — 'what dryness value does EN 285 require?' (contrast: fully grounded)")
    ans_norm = ask(
        "What dryness value does EN 285 require for the steam supplied to the sterilizer?",
        user="alice",
    )
    print(to_markdown(ans_norm))


if __name__ == "__main__":
    main()
