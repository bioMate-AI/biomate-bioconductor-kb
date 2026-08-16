#!/usr/bin/env python3
"""
embed_missing_tools.py — INCREMENTAL tool-embedding population.

Run this AFTER tool ingestion/enrichment (the add_*_to_index / *_scientific_context
scripts). It computes a dense vector for every tool that doesn't have one yet and
stores it in the `tools.embedding` BLOB column. Because embeddings live in the DB,
they then propagate to dev with the normal `sync_to_dev.sh` DB layer — no separate
.npz artifact, no fast-box build, no rebuild step.

Only new/changed tools are embedded (WHERE embedding IS NULL), so it's cheap on a
routine enrichment run. Use --all to re-embed everything (e.g. after the text recipe
changes). Encoding uses the shared embed server if up, else in-process
sentence-transformers (same bge-small model as the rest of BioMate).

    python3 backend/scripts/embed_missing_tools.py            # embed tools missing a vector
    python3 backend/scripts/embed_missing_tools.py --all      # re-embed all
    python3 backend/scripts/embed_missing_tools.py --db PATH
"""
import argparse
import logging
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_HERE, "..", "lib"))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--db", default=os.path.join(_HERE, "..", "database", "galaxy_ai_tools.db"),
                    help="path to galaxy_ai_tools.db")
    ap.add_argument("--all", action="store_true",
                    help="re-embed ALL tools (recipe change), not just those missing a vector")
    args = ap.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(message)s")

    from galaxy.ai.vector_search import VectorToolSearch
    # auto_create=False → just wire up the encoder (server or ST), don't build an npz.
    vs = VectorToolSearch(str(args.db), auto_create=False)
    n = vs.embed_missing_tools(reembed_all=bool(args.all))
    print(f"embedded {n} tools into tools.embedding at {args.db}")
    # Non-zero exit if we intended to embed but couldn't (encoder unavailable) — lets
    # a CI/enrichment pipeline notice the failure instead of silently shipping gaps.
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
