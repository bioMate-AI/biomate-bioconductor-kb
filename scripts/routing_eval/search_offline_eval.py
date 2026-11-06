#!/usr/bin/env python3
"""Offline, search-only routing check of UnifiedWorkflowSearch (no chat, no LLM Pass-0, no Batch).

Scores the scorer itself on three gold sets against the local workflow DB:
  routing  — evaluation/datasets/cross_domain_routing/queries.yaml (200; correct_workflow / acceptable_alts /
             disqualified, scored 1 / 0.5 / 0 as evaluation/runners/run_routing.py)
  bioc     — evaluation/datasets/bioc_method_selection/data.jsonl (24; correct_method + acceptable_alts;
             invalid_picks counted separately)
  retag    — evaluation/routing_eval/domain_retag/payloads.json (20; mod regex, strict regex where set)
Production adds Pass-0 (LLM) and dense bonuses on dev, so absolute numbers differ from dev; the A/B of a
scorer change on identical inputs is what this measures.
Usage: [SEARCH_DB=<db copy>] PYTHONPATH=backend/lib python3 scripts/routing_eval/search_offline_eval.py <out.json>
"""
import json, os, re, sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "backend" / "lib"))
from galaxy.ai.unified_workflow_search import UnifiedWorkflowSearch  # noqa: E402

norm = lambda s: re.sub(r"[^a-z0-9]", "", (s or "").lower())


def top1(s, q):
    r = s.search(q, limit=5)
    return r[0].name if r else None


def main():
    db = os.environ.get("SEARCH_DB")  # a candidate DB copy to compare against the default local DB
    s = UnifiedWorkflowSearch(db_path=Path(db)) if db else UnifiedWorkflowSearch()
    out = {"db": os.environ.get("SEARCH_DB", "(default)"), "rows": []}
    tot = {}
    for q in yaml.safe_load(open(ROOT / "evaluation/datasets/cross_domain_routing/queries.yaml")):
        p = top1(s, q["query"])
        sc = 0.0 if norm(p) in {norm(x) for x in q.get("disqualified") or []} else (
            1.0 if norm(p) == norm(q["correct_workflow"]) else 0.5 if norm(p) in {norm(x) for x in q.get("acceptable_alts") or []} else 0.0)
        out["rows"].append({"set": "routing", "id": q["id"], "domain": q.get("domain"), "pred": p, "score": sc})
    for l in open(ROOT / "evaluation/datasets/bioc_method_selection/data.jsonl"):
        q = json.loads(l)
        p = top1(s, q["query"])
        ok = norm(p) in {norm(x) for x in [q["correct_method"]] + (q.get("acceptable_alts") or [])}
        bad = norm(p) in {norm(x) for x in q.get("invalid_picks") or []}
        out["rows"].append({"set": "bioc", "id": q["id"], "pred": p, "score": 1.0 if ok else 0.0, "invalid": bad})
    for q in json.load(open(ROOT / "evaluation/routing_eval/domain_retag/payloads.json")):
        p = top1(s, q["prompt"])
        r = {"set": "retag", "id": q["idx"], "track": q["track"], "pred": p,
             "score": 1.0 if p and re.search(q["mod"], p, re.I) else 0.0}
        if q.get("strict"):
            r["strict"] = 1.0 if p and re.search(q["strict"], p.strip(), re.I) else 0.0
        out["rows"].append(r)
    for st in ("routing", "bioc", "retag"):
        rs = [r for r in out["rows"] if r["set"] == st]
        tot[st] = round(sum(r["score"] for r in rs) / len(rs), 3)
    tot["bioc_invalid"] = sum(1 for r in out["rows"] if r.get("invalid"))
    st = [r["strict"] for r in out["rows"] if "strict" in r]
    tot["retag_strict"] = f"{int(sum(st))}/{len(st)}"
    out["summary"] = tot
    json.dump(out, open(sys.argv[1], "w"), indent=1)
    print(json.dumps(tot))


if __name__ == "__main__":
    main()
