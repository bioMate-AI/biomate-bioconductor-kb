#!/usr/bin/env python3
"""BioMate runner for LitQA2 — the full retrieval pipeline via research_query on dev.
Writes results/biomate/litqa2.jsonl in the shared prediction format (answer + citations)."""
import argparse
import json
import os
import re
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))


def ask(base, q, timeout=180, retries=3):
    """Retry with backoff — dev has no ALB/retry layer, deep queries occasionally 500."""
    body = json.dumps({"query": q, "include_citations": True,
                       "include_benchmark_evidence": False, "max_citations": 20}).encode()
    last = None
    for i in range(retries):
        try:
            req = urllib.request.Request(f"{base}/api/ai_assistant/research_query",
                                         data=body, headers={"Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return json.load(r)
        except Exception as e:
            last = e
            if i < retries - 1:
                time.sleep(6 * (i + 1))
    raise last


def pick_option(answer, options):
    """Map BioMate's free-text answer to the option it best endorses (token overlap on the
    text after 'ANSWER:', falling back to the whole answer)."""
    low = (answer or "").lower()
    m = re.search(r"answer\s*[:\-]\s*(.+)", low, re.S)
    tail = m.group(1) if m else low
    best, best_score = None, -1
    for o in options:
        toks = set(re.findall(r"[a-z0-9]{3,}", o.lower()))
        score = sum(1 for w in toks if w in tail) / (len(toks) or 1)
        if score > best_score:
            best, best_score = o, score
    return best


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="https://dev-public.biomate.ai")
    ap.add_argument("--data", default=os.path.join(HERE, "data.jsonl"))
    ap.add_argument("--limit", type=int, default=0)
    args = ap.parse_args()
    rows = [json.loads(l) for l in open(args.data)]
    if args.limit:
        rows = rows[:args.limit]
    outdir = os.path.join(HERE, "results", "biomate")
    os.makedirs(outdir, exist_ok=True)
    out = os.path.join(outdir, "litqa2.jsonl")
    n = 0
    with open(out, "w") as f:
        for r in rows:
            q = (r["question"] + "\n\nChoose exactly ONE option and end your answer with "
                 "'ANSWER: <the option text verbatim>'.\nOptions:\n"
                 + "\n".join(f"- {o}" for o in r["options"]))
            try:
                d = ask(args.base, q)
                ans = d.get("answer", "") or ""
                cites = [{"title": c.get("title"), "pmid": c.get("pmid"), "doi": c.get("doi")}
                         for c in (d.get("citations") or [])]
                pred = {"answer": pick_option(ans, r["options"])}
            except Exception as e:
                sys.stderr.write(f"[{r['id']}] ERR {e}\n")
                pred, cites = {"answer": ""}, []
            f.write(json.dumps({"id": r["id"], "prediction": pred, "citations": cites}) + "\n")
            n += 1
            if n % 20 == 0:
                sys.stderr.write(f"  {n}/{len(rows)}\n")
    print(f"wrote {n} -> {out}")


if __name__ == "__main__":
    main()
