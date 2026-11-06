#!/usr/bin/env python3
"""
run_lane.py — Lane-arbitration accuracy benchmark.

Measures the composer's Instant/Cloud lane arbiter (backend
/api/route/classify → route_classify → UnifiedIntentRouter + catalog
resonance). This is DISTINCT from run_routing.py, which measures which
*workflow* ranks top-k; this measures which *lane* a query is assigned.

Dataset:
  Cloud-labeled : ../datasets/cross_domain_routing/queries.yaml  (200 runnable
                  tasks — every one has a correct_workflow, so it must → Cloud)
  Instant-labeled: ../datasets/lane_arbitration/instant_cases.yaml (questions,
                  ad-hoc compute, adversarial task↔question pairs)

The endpoint needs the warm embedding index + real workflow DB, which only
exist on dev — run against the deployed stack:

    python runners/run_lane.py --base-url https://dev-public.biomate.ai \
        --token biomate-e2e-bypass-token-dev-only

Metrics:
  overall_accuracy      correct-lane / total
  cloud_recall          of Cloud tasks, fraction → Cloud   (miss = under-promise)
  instant_precision     of Instant preds, fraction truly Instant
  instant_recall        of Instant questions, fraction → Instant (miss = OVER-promise)
  adversarial_accuracy  accuracy on the adversarial_question subset (the crux)
  confusion             {cloud->cloud, cloud->instant, instant->instant, instant->cloud}
Every misroute is printed so the failure mode is visible, not just a number.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.request
import urllib.error
from collections import Counter, defaultdict
from pathlib import Path

import yaml

ROOT = Path(__file__).parent.parent
CLOUD_DS = ROOT / "datasets" / "cross_domain_routing" / "queries.yaml"
INSTANT_DS = ROOT / "datasets" / "lane_arbitration" / "instant_cases.yaml"


def classify(base_url: str, text: str, token: str | None, timeout: float = 15.0) -> dict:
    """POST one query to /api/route/classify; return the parsed JSON (or {})."""
    url = base_url.rstrip("/") + "/api/route/classify"
    body = json.dumps({"text": text}).encode()
    req = urllib.request.Request(url, data=body, method="POST")
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("x-e2e-test-token", token)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        return {"success": False, "error": f"HTTP {e.code}", "_status": e.code}
    except Exception as e:  # noqa: BLE001
        return {"success": False, "error": str(e)}


def load_cases(limit_cloud: int | None, limit_instant: int | None):
    cloud_raw = yaml.safe_load(CLOUD_DS.read_text())
    instant_raw = yaml.safe_load(INSTANT_DS.read_text())
    cloud = [
        {"id": x["id"], "query": x["query"], "expected": "cloud",
         "domain": x.get("domain", "unknown"), "category": "task",
         "confusable_with": None}
        for x in cloud_raw
    ]
    instant = [
        {"id": x["id"], "query": x["query"], "expected": "instant",
         "domain": "n/a", "category": x.get("category", "question"),
         "confusable_with": x.get("confusable_with")}
        for x in instant_raw
    ]
    if limit_cloud is not None:
        cloud = cloud[:limit_cloud]
    if limit_instant is not None:
        instant = instant[:limit_instant]
    return cloud + instant


def main():
    ap = argparse.ArgumentParser(description="Lane-arbitration accuracy benchmark")
    ap.add_argument("--base-url", default="https://dev-public.biomate.ai")
    ap.add_argument("--token", default=None, help="x-e2e-test-token value (dev bypass)")
    ap.add_argument("--limit-cloud", type=int, default=None)
    ap.add_argument("--limit-instant", type=int, default=None)
    ap.add_argument("--output", default=None, help="write results JSON here")
    ap.add_argument("--sleep", type=float, default=0.0, help="delay between calls (s)")
    args = ap.parse_args()

    cases = load_cases(args.limit_cloud, args.limit_instant)
    print(f"[lane] {len(cases)} cases → {args.base_url}/api/route/classify", flush=True)

    rows = []
    errors = 0
    for i, c in enumerate(cases, 1):
        r = classify(args.base_url, c["query"], args.token)
        got = r.get("lane") if r.get("success") else None
        if got not in ("instant", "cloud"):
            errors += 1
        rows.append({**c, "got": got, "why": r.get("why"),
                     "resonance": r.get("resonance"), "err": None if r.get("success") else r.get("error")})
        if args.sleep:
            time.sleep(args.sleep)
        if i % 25 == 0:
            print(f"  … {i}/{len(cases)}", flush=True)

    scored = [r for r in rows if r["got"] in ("instant", "cloud")]
    conf = Counter((r["expected"], r["got"]) for r in scored)
    n = len(scored)
    correct = sum(1 for r in scored if r["expected"] == r["got"])

    cloud_cases = [r for r in scored if r["expected"] == "cloud"]
    instant_cases = [r for r in scored if r["expected"] == "instant"]
    cloud_hit = sum(1 for r in cloud_cases if r["got"] == "cloud")
    instant_hit = sum(1 for r in instant_cases if r["got"] == "instant")
    pred_instant = [r for r in scored if r["got"] == "instant"]
    instant_prec_den = len(pred_instant)
    instant_prec_num = sum(1 for r in pred_instant if r["expected"] == "instant")

    adv = [r for r in instant_cases if r["category"] == "adversarial_question"]
    adv_hit = sum(1 for r in adv if r["got"] == "instant")

    def pct(a, b):
        return round(100.0 * a / b, 1) if b else None

    per_domain = defaultdict(lambda: [0, 0])
    for r in cloud_cases:
        per_domain[r["domain"]][1] += 1
        if r["got"] == "cloud":
            per_domain[r["domain"]][0] += 1

    summary = {
        "base_url": args.base_url,
        "total": len(rows),
        "scored": n,
        "errors": errors,
        "overall_accuracy_pct": pct(correct, n),
        "cloud_recall_pct": pct(cloud_hit, len(cloud_cases)),
        "instant_recall_pct": pct(instant_hit, len(instant_cases)),
        "instant_precision_pct": pct(instant_prec_num, instant_prec_den),
        "adversarial_accuracy_pct": pct(adv_hit, len(adv)),
        "confusion": {
            "cloud->cloud": conf[("cloud", "cloud")],
            "cloud->instant (under-promise)": conf[("cloud", "instant")],
            "instant->instant": conf[("instant", "instant")],
            "instant->cloud (OVER-promise)": conf[("instant", "cloud")],
        },
        "per_domain_cloud_recall": {
            d: {"hit": v[0], "n": v[1], "pct": pct(v[0], v[1])}
            for d, v in sorted(per_domain.items())
        },
    }

    print("\n===== LANE ARBITRATION =====")
    print(json.dumps(summary, indent=2))

    misroutes = [r for r in scored if r["expected"] != r["got"]]
    if misroutes:
        print(f"\n----- {len(misroutes)} MISROUTES -----")
        for r in misroutes:
            tag = "OVER-promise" if r["expected"] == "instant" else "under-promise"
            print(f"  [{tag}] {r['id']:14s} exp={r['expected']} got={r['got']}  "
                  f"res={r.get('resonance')}  :: {r['query'][:80]}")
    if errors:
        print(f"\n{errors} endpoint errors (excluded from scoring):")
        for r in rows:
            if r["got"] not in ("instant", "cloud"):
                print(f"  {r['id']}: {r['err']}")

    if args.output:
        outp = Path(args.output)
        outp.parent.mkdir(parents=True, exist_ok=True)
        outp.write_text(json.dumps({"summary": summary, "rows": rows}, indent=2))
        print(f"\nwrote {outp}")

    # Non-zero exit if the OVER-promise regression is material (>10% of instant).
    over = conf[("instant", "cloud")]
    if instant_cases and over / len(instant_cases) > 0.10:
        print(f"\nWARNING: over-promise rate {pct(over, len(instant_cases))}% exceeds 10% guard")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
