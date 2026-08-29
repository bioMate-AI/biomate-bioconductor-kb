#!/usr/bin/env python3
"""PaperQA2 baseline runner (FutureHouse, Apache-2.0) — the SOTA reference for LitQA2.

Setup:  pip install paper-qa>=5   (Python 3.11+);  export OPENAI_API_KEY=...
  equal-info condition:  --papers <dir of gold PDFs>   (both systems see the same corpus)
  live condition:        omit --papers                 (PaperQA2 uses S2/Crossref/OpenAlex/Unpaywall)

Writes results/paperqa2/litqa2.jsonl in the shared format. NOTE: the exact PaperQA2 response
schema (`contexts`, `.doc.doi`) varies across 5.x minor versions — adjust the extraction block
to the installed version if fields differ; the accuracy path is version-stable.
"""
import argparse
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def pick_option(answer, options):
    low = (answer or "").lower()
    best, best_score = None, -1
    for o in options:
        toks = set(re.findall(r"[a-z0-9]{3,}", o.lower()))
        score = sum(1 for w in toks if w in low) / (len(toks) or 1)
        if score > best_score:
            best, best_score = o, score
    return best


def extract_citations(resp):
    cites = []
    for c in (getattr(resp, "contexts", None) or []):
        doc = getattr(c, "doc", None)
        title = getattr(doc, "title", None) or getattr(doc, "docname", None)
        doi = getattr(doc, "doi", None)
        if title or doi:
            cites.append({"title": title, "doi": doi, "pmid": None})
    # dedup by (title,doi)
    seen, out = set(), []
    for c in cites:
        k = (c["title"], c["doi"])
        if k not in seen:
            seen.add(k)
            out.append(c)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", default=os.path.join(HERE, "data.jsonl"))
    ap.add_argument("--papers", default=None, help="dir of PDFs (equal-info); omit for live")
    ap.add_argument("--limit", type=int, default=0)
    args = ap.parse_args()
    try:
        from paperqa import Settings, ask
    except ImportError:
        sys.exit("pip install paper-qa>=5  (Python 3.11+); then set OPENAI_API_KEY")
    settings = Settings(paper_directory=args.papers) if args.papers else Settings()
    rows = [json.loads(l) for l in open(args.data)]
    if args.limit:
        rows = rows[:args.limit]
    outdir = os.path.join(HERE, "results", "paperqa2")
    os.makedirs(outdir, exist_ok=True)
    out = os.path.join(outdir, "litqa2.jsonl")
    n = 0
    with open(out, "w") as f:
        for r in rows:
            q = (r["question"] + "\n\nOptions:\n" + "\n".join(f"- {o}" for o in r["options"])
                 + "\nAnswer with exactly one option verbatim.")
            try:
                resp = ask(q, settings=settings)
                ans = getattr(resp, "formatted_answer", None) or str(resp)
                pred = {"answer": pick_option(ans, r["options"])}
                cites = extract_citations(resp)
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
