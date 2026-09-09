from __future__ import annotations
"""
reconstruct_lane_after.py — Offline (no-deploy) projection of the catalog-
resonance lane arbiter, against dev's LIVE workflow index.

Faithfulness:
  * keyword lane          — EXACT: dev currently runs the pre-resonance code, so
                            the baseline /api/route/classify response IS the
                            keyword verdict. Read from the baseline JSON.
  * question-guard        — EXACT: the same _QUESTION_LEAD_RE / trailing-? logic
                            shipped in ai_assistant.py, reimplemented here.
  * resonance             — PROXY: my gate is raw BGE cosine >= 0.60 from
                            _dense_workflow_prefilter, which no public endpoint
                            exposes. We proxy it with the top-1 composite score
                            from /api/ai_assistant/search_ranked and sweep a
                            threshold, so the projection is reported as a curve,
                            not a single fabricated number.

Arbiter reconstructed:
  lane = cloud IF keyword_lane == cloud
         ELSE instant IF looks_like_question(text)
         ELSE cloud IF top1_search_score >= T     (resonance proxy)
         ELSE instant
"""
import argparse
import json
import re
import sys
import time
import urllib.request
import urllib.error
from pathlib import Path

import yaml

ROOT = Path(__file__).parent.parent
CLOUD_DS = ROOT / "datasets" / "cross_domain_routing" / "queries.yaml"
INSTANT_DS = ROOT / "datasets" / "lane_arbitration" / "instant_cases.yaml"

# EXACT copy of the shipped guard (ai_assistant.py _QUESTION_LEAD_RE).
_QUESTION_LEAD_RE = re.compile(
    r"^\s*(what|why|how|when|where|which|who|whom|is|are|was|were|does|do|did|can|could|"
    r"should|would|will|explain|describe|define|summari[sz]e|tell me|give me an overview|"
    r"compare|difference between|pros and cons)\b",
    re.IGNORECASE,
)


def looks_like_question(text: str) -> bool:
    t = (text or "").strip()
    return bool(_QUESTION_LEAD_RE.match(t)) or t.endswith("?")


def search_top1(base_url: str, query: str, timeout: float = 25.0):
    url = base_url.rstrip("/") + "/api/ai_assistant/search_ranked"
    body = json.dumps({"query": query, "limit": 1}).encode()
    req = urllib.request.Request(url, data=body, method="POST")
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            d = json.loads(resp.read().decode())
        results = d.get("results") or []
        if results:
            r0 = results[0]
            return float(r0.get("score") or 0.0), r0.get("name")
        return 0.0, None
    except Exception as e:  # noqa: BLE001
        return None, f"err:{e}"


def load_cases():
    cloud = [{"id": x["id"], "query": x["query"], "expected": "cloud",
              "domain": x.get("domain", "?"), "category": "task"}
             for x in yaml.safe_load(CLOUD_DS.read_text())]
    instant = [{"id": x["id"], "query": x["query"], "expected": "instant",
                "domain": "n/a", "category": x.get("category", "question")}
               for x in yaml.safe_load(INSTANT_DS.read_text())]
    return cloud + instant


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-url", default="https://dev-public.biomate.ai")
    ap.add_argument("--baseline", required=True, help="baseline lane JSON (keyword verdicts)")
    ap.add_argument("--output", default=None)
    args = ap.parse_args()

    # keyword lane per query id, from the baseline run (dev = pre-resonance code).
    base = json.loads(Path(args.baseline).read_text())
    kw_lane = {r["id"]: r.get("got") for r in base["rows"]}

    cases = load_cases()
    print(f"[recon] {len(cases)} cases → {args.base_url}/api/ai_assistant/search_ranked", flush=True)
    for i, c in enumerate(cases, 1):
        score, name = search_top1(args.base_url, c["query"])
        c["top1_score"] = score
        c["top1_name"] = name
        c["kw_lane"] = kw_lane.get(c["id"])
        c["is_question"] = looks_like_question(c["query"])
        if i % 25 == 0:
            print(f"  … {i}/{len(cases)}", flush=True)

    usable = [c for c in cases if isinstance(c.get("top1_score"), float) and c.get("kw_lane") in ("instant", "cloud")]

    def decide(c, T):
        if c["kw_lane"] == "cloud":
            return "cloud"
        if c["is_question"]:
            return "instant"
        return "cloud" if c["top1_score"] >= T else "instant"

    cloud_cases = [c for c in usable if c["expected"] == "cloud"]
    instant_cases = [c for c in usable if c["expected"] == "instant"]

    # Score distributions (task vs question vs ad-hoc) — shows the separation the
    # question-guard + threshold rely on.
    def dist(rows):
        s = sorted(r["top1_score"] for r in rows)
        n = len(s)
        if not n:
            return {}
        return {"n": n, "min": round(s[0], 1), "p25": round(s[n // 4], 1),
                "median": round(s[n // 2], 1), "p75": round(s[3 * n // 4], 1), "max": round(s[-1], 1)}

    adhoc = [c for c in instant_cases if c["category"] == "adhoc_compute"]
    adv = [c for c in instant_cases if c["category"] == "adversarial_question"]

    sweep = {}
    for T in (35, 40, 45, 50, 55):
        preds = [(c, decide(c, T)) for c in usable]
        correct = sum(1 for c, p in preds if c["expected"] == p)
        cr = sum(1 for c in cloud_cases if decide(c, T) == "cloud")
        ir = sum(1 for c in instant_cases if decide(c, T) == "instant")
        over = sum(1 for c in instant_cases if decide(c, T) == "cloud")
        sweep[T] = {
            "overall_accuracy_pct": round(100 * correct / len(usable), 1),
            "cloud_recall_pct": round(100 * cr / len(cloud_cases), 1),
            "instant_recall_pct": round(100 * ir / len(instant_cases), 1),
            "over_promise": over,
        }

    # Baseline (keyword-only) for the same usable set, for a clean A/B.
    b_cr = sum(1 for c in cloud_cases if c["kw_lane"] == "cloud")
    b_ir = sum(1 for c in instant_cases if c["kw_lane"] == "instant")
    b_correct = sum(1 for c in usable if c["expected"] == c["kw_lane"])

    out = {
        "base_url": args.base_url,
        "usable_cases": len(usable),
        "resonance_proxy": "top-1 search_ranked composite score (NOT raw cosine — projection, not exact)",
        "score_distribution": {
            "cloud_tasks": dist(cloud_cases),
            "instant_questions": dist([c for c in instant_cases if c["category"] != "adhoc_compute"]),
            "instant_adhoc_compute": dist(adhoc),
        },
        "baseline_keyword_only": {
            "overall_accuracy_pct": round(100 * b_correct / len(usable), 1),
            "cloud_recall_pct": round(100 * b_cr / len(cloud_cases), 1),
            "instant_recall_pct": round(100 * b_ir / len(instant_cases), 1),
        },
        "projected_with_resonance_by_threshold": sweep,
        "question_guard_exact": {
            "adversarial_cases": len(adv),
            "caught_by_guard": sum(1 for c in adv if c["is_question"]),
        },
    }
    print("\n===== LANE RECONSTRUCTION (offline projection) =====")
    print(json.dumps(out, indent=2))
    if args.output:
        Path(args.output).parent.mkdir(parents=True, exist_ok=True)
        Path(args.output).write_text(json.dumps({"summary": out, "cases": cases}, indent=2))
        print(f"\nwrote {args.output}")


if __name__ == "__main__":
    sys.exit(main())
