"""CLI entry: python -m galaxy.ai.chain_composer "<query>"

Prints a JSON ComposedChain plus a short human summary. Useful for
iterating on retrieval / signals without spinning up the full backend.
"""

from __future__ import annotations

import argparse
import json
import sys

from .composer import compose_chain


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(prog="chain_composer", description=__doc__)
    parser.add_argument("query", help="user query, free text")
    parser.add_argument("--profile-bias", type=float, default=0.0,
                        help="-0.2..0.2 user-profile bias (beginner negative, PI positive)")
    parser.add_argument("--top-patterns", type=int, default=3)
    parser.add_argument("--top-chains", type=int, default=3)
    parser.add_argument("--json", action="store_true", help="print JSON only, no summary")
    args = parser.parse_args(argv)

    result = compose_chain(
        args.query,
        user_profile_bias=args.profile_bias,
        top_k_patterns=args.top_patterns,
        top_k_chains=args.top_chains,
    )

    if args.json:
        print(json.dumps(result.to_dict(), indent=2))
        return 0

    print(f"=== Compose: {args.query!r} ===")
    print(f"surfacing_mode = {result.surfacing_mode}    confidence = {result.confidence:.2f}    source = {result.source}")
    print()
    print("Patterns used (retrieval scaffolding):")
    for n in result.patterns_used:
        print(f"  - {n}")
    print()
    print("Curated exemplars:")
    for n in result.exemplars_used:
        print(f"  - {n}")
    print()
    print("Signals (breakdown):")
    for k, v in result.signals.items():
        print(f"  {k:30s} {v:+.3f}")
    print()
    print(f"Rationale: {result.rationale or '(none)'}")
    print()
    if result.steps:
        print("Composed chain:")
        for s in result.steps:
            print(f"  {s.order}. {s.workflow_name:35s} [{s.role}]   {s.rationale}")
        for e in result.edges:
            print(f"     edge {e.from_step} → {e.to_step}   via={e.via or '(unspecified)'}")
    else:
        print("(no steps emitted — see rationale above)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
