#!/usr/bin/env python3
"""Run BioMate on the held-out evidence-review set end-to-end and score the two axes that
don't need MCQ options: citation confabulation_rate (objective) + must-cite recall (only
where a verified expert key exists). Neutral set — no system is tuned on it."""
import json
import os
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from citation_veracity import score_citations  # noqa: E402


def ask(base, q, timeout=240, retries=3):
    """Deep evidence-review queries take ~70s and dev has no ALB/retry layer, so transient
    500s / blips happen — retry with backoff (E2E discipline: generous timeout + retries)."""
    body = json.dumps({"query": q, "include_citations": True,
                       "include_benchmark_evidence": False, "max_citations": 25}).encode()
    last = None
    for i in range(retries):
        try:
            req = urllib.request.Request(f"{base}/api/ai_assistant/research_query",
                                         data=body, headers={"Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return json.load(r)
        except Exception as e:  # HTTPError 500 / timeout / network blip
            last = e
            if i < retries - 1:
                time.sleep(8 * (i + 1))
    raise last


def main():
    base = sys.argv[1] if len(sys.argv) > 1 else "https://dev-public.biomate.ai"
    rows = [json.loads(l) for l in open(os.path.join(HERE, "held_out", "data.jsonl"))]
    tot_id = tot_bad = 0
    for r in rows:
        try:
            d = ask(base, r["question"])
        except Exception as e:
            print(f"### {r['id']}: ERR {e}")
            continue
        cites = [{"title": c.get("title"), "pmid": c.get("pmid"), "doi": c.get("doi")}
                 for c in (d.get("citations") or [])]
        sc = score_citations(cites)
        got = {str(c.get("pmid")) for c in cites if c.get("pmid")}
        must = r.get("must_cite_pmids") or []
        hit = [p for p in must if p in got]
        tot_id += sc["n_identified"]
        tot_bad += sc["n_unresolvable"] + sc["n_mismatched"]
        print(f"\n### {r['id']}")
        print(f"  citations={sc['n_citations']} identified={sc['n_identified']} "
              f"ok={sc['n_ok']} mismatched={sc['n_mismatched']} unresolvable={sc['n_unresolvable']}")
        line = f"  confabulation_rate={sc['confabulation_rate']}"
        if must:
            line += f"   must-cite recall={len(hit)}/{len(must)} ({round(len(hit)/len(must), 2)})"
        print(line)
    print(f"\n=== OVERALL confabulation_rate = "
          f"{round(tot_bad / tot_id, 4) if tot_id else 0.0} over {tot_id} identified citations ===")


if __name__ == "__main__":
    main()
