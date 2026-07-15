#!/usr/bin/env python3
"""Paper-to-Workflow tool-locator benchmark (offline, real retrieval).

Feeds each curated paper's methods-style query through BioMate's production
chain_composer BM25 retrieval over the workflow catalog and measures whether
the known-correct pipeline is returned in top-k. No LLM, no network — this
isolates the *tool-locator* stage of the paper->workflow pipeline.

Metrics: Hit@1, Hit@3, Hit@5, MRR (mean reciprocal rank of first correct hit).

Run from repo root:
    cd backend && PYTHONPATH=lib python3 \
      ../research_repos/biomate_paper2workflow_paper/benchmark/run_tool_locator_bench.py
"""
import json
import os
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
BACKEND = REPO / "backend"
sys.path.insert(0, str(BACKEND / "lib"))
sys.path.insert(0, str(BACKEND))

import sqlite3  # noqa: E402
import json as _json  # noqa: E402

from lib.galaxy.ai.chain_composer import retrieval  # noqa: E402
from lib.galaxy.ai.chain_composer.retrieval import (  # noqa: E402
    _BM25Index, _tokenize_bm25, _expand,
)

DB = BACKEND / "database" / "galaxy_ai_tools.db"
PAIRS = Path(__file__).with_name("pairs.json")
TOP_K = 5

# NOTE ON FAITHFULNESS: the local catalog snapshot lacks the `annotation_v2`
# column present on the dev/prod catalog, so production's
# retrieval.retrieve_workflows() query errors here. We therefore rebuild the
# BM25 index using production's OWN scoring primitives (_BM25Index,
# _tokenize_bm25, _expand) over the columns that exist locally
# (name+domain+description+tools_used+annotation). Same algorithm, same
# tokenizer — only the doc corpus source differs. Re-run against the prod
# catalog (2,455 wf, with annotation_v2) via retrieve_workflows() directly.

_INDEX = None
_BY_NAME = None


def _load_index():
    global _INDEX, _BY_NAME
    if _INDEX is not None:
        return _INDEX, _BY_NAME
    con = sqlite3.connect(str(DB))
    rows = con.execute(
        "SELECT name, COALESCE(domain,''), COALESCE(description,''), "
        "COALESCE(tools_used,''), COALESCE(annotation,'') "
        "FROM workflows WHERE executable=1 AND name IS NOT NULL"
    ).fetchall()
    con.close()
    docs = []
    by_name = {}
    for name, domain, description, tools_used, annotation in rows:
        try:
            tools = _json.loads(tools_used or "[]")
            tools_text = " ".join(t for t in tools if isinstance(t, str))
        except Exception:
            tools_text = ""
        annotation = (annotation or "")[:400]
        doc_text = " ".join(filter(None, [name, domain, description, tools_text, annotation]))
        docs.append((name, doc_text))
        by_name[name] = domain
    _INDEX = _BM25Index.build(docs)
    _BY_NAME = by_name
    return _INDEX, _BY_NAME


def retrieve(query, top_k=TOP_K):
    index, _ = _load_index()
    q_terms = list(_expand(_tokenize_bm25(query)))
    scored = index.score_all(q_terms)
    scored = [(nm, s) for nm, s in scored if s > 0]
    scored.sort(key=lambda x: x[1], reverse=True)
    return [nm for nm, _ in scored[:top_k]]


def matches(name: str, patterns) -> bool:
    n = name.lower()
    return any(p.lower() in n for p in patterns)


def target_exists(patterns) -> bool:
    _, by_name = _load_index()
    return any(matches(nm, patterns) for nm in by_name)


def main():
    data = json.loads(PAIRS.read_text())["pairs"]
    rows = []
    dropped = []
    for pair in data:
        if not target_exists(pair["target_patterns"]):
            dropped.append(pair["id"])
            continue
        ranked = retrieve(pair["query"], top_k=TOP_K)
        hit_rank = None
        for i, nm in enumerate(ranked, start=1):
            if matches(nm, pair["target_patterns"]):
                hit_rank = i
                break
        rows.append({
            "id": pair["id"],
            "paper": pair["paper"],
            "hit_rank": hit_rank,
            "top1": ranked[0] if ranked else None,
            "retrieved": ranked,
        })

    n = len(rows)
    hit1 = sum(1 for r in rows if r["hit_rank"] == 1)
    hit3 = sum(1 for r in rows if r["hit_rank"] and r["hit_rank"] <= 3)
    hit5 = sum(1 for r in rows if r["hit_rank"] and r["hit_rank"] <= 5)
    mrr = sum(1.0 / r["hit_rank"] for r in rows if r["hit_rank"]) / n if n else 0.0

    summary = {
        "db": str(DB),
        "top_k": TOP_K,
        "n_pairs_scored": n,
        "n_dropped_no_target_in_db": len(dropped),
        "dropped_ids": dropped,
        "Hit@1": round(hit1 / n, 3) if n else None,
        "Hit@3": round(hit3 / n, 3) if n else None,
        "Hit@5": round(hit5 / n, 3) if n else None,
        "MRR": round(mrr, 3),
        "per_pair": rows,
    }
    out = Path(__file__).resolve().parents[1] / "results" / "tool_locator_results.json"
    out.write_text(json.dumps(summary, indent=2))
    print(json.dumps({k: v for k, v in summary.items() if k != "per_pair"}, indent=2))
    print(f"\nwrote {out}")
    print("\nper-pair (hit_rank / top1):")
    for r in rows:
        print(f"  {r['id']:26s} rank={r['hit_rank']}  top1={r['top1']!r}")


if __name__ == "__main__":
    main()
