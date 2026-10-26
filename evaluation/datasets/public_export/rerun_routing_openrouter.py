#!/usr/bin/env python3
"""Uniform, EMPTIES-AWARE routing re-run via OpenRouter — the tool the leaderboard needs before publishing.

Why: audit_routing_provenance.py found the routing_harness column mixes two menu conditions (rich `described`
vs legacy names-only `catalog`) and has empties-contaminated cells for reasoning models. This script re-runs
routing for a uniform model roster under ONE condition — the production-faithful `described` menu built from
the live workflows DB + the committed gold corrections — and is empties-aware so reasoning models don't
produce fake ~0 cells:
  * max_tokens budgeted past thinking tokens (default 2000),
  * every call retried on empty/exception (default 4x) with backoff,
  * per-model empty + off-menu-hallucination counts written to a sidecar so contamination is visible,
  * low concurrency to avoid the rate-limit artifact that nuked earlier runs.

Writes each model's predictions to results/<model>/cross_domain_routing_catalog_described.jsonl (the file the
leaderboard prefers), so after a run `python3 regen_leaderboard_csv.py` produces a uniform, clean column.

COST NOTE: this calls paid APIs across the roster — a real (bounded) spend. Run it deliberately, not casually.

Usage:
  OPENROUTER_API_KEY=... python3 rerun_routing_openrouter.py \
      --models qwen/qwen3.5-9b,anthropic/claude-opus-5,... [--db ../../../backend/database/galaxy_ai_tools.db]
      [--max-tokens 2000] [--workers 4] [--limit 0]
"""
import argparse, json, os, re, sqlite3, time, urllib.request, concurrent.futures as cf

HERE = os.path.dirname(os.path.abspath(__file__))


def build_menu(db_path):
    rows = [json.loads(l) for l in open(os.path.join(HERE, "cross_domain_routing", "data.jsonl"))]
    labs = sorted({str(r["correct_workflow"]) for r in rows})
    con = sqlite3.connect(db_path); wf = {}
    for nm, ds in con.execute(
        "SELECT name, COALESCE(NULLIF(TRIM(description),''), annotation, '') FROM workflows WHERE source IN "
        "('nfcore','nfcore_subwf','nextflow','biomni_nextflow','bioconductor','custom','custom_composer','biomate-ai-tools')"):
        if nm not in wf or (ds and not wf[nm]):
            wf[nm] = ds or ""
    con.close()
    menu = "\n".join((f"{l} — {(wf.get(l) or '')[:120].replace(chr(10),' ').strip()}" if wf.get(l) else l) for l in labs)
    return rows, labs, menu


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--models", required=True, help="comma-separated OpenRouter model ids")
    ap.add_argument("--db", default=os.path.join(HERE, "..", "..", "..", "backend", "database", "galaxy_ai_tools.db"))
    ap.add_argument("--max-tokens", type=int, default=2000)
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--retries", type=int, default=4)
    ap.add_argument("--limit", type=int, default=0)
    a = ap.parse_args()
    key = os.environ["OPENROUTER_API_KEY"]
    rows, labs, menu = build_menu(os.path.abspath(a.db))
    if a.limit:
        rows = rows[:a.limit]
    labset = {l.lower(): l for l in labs}
    norm = lambda s: re.sub(r"[\s_]+", " ", (s or "").strip().lower())

    def on_menu(raw):
        t = norm(raw); return any(norm(l) in t for l in labs)

    def parse(raw):
        t = norm(raw)
        for l in sorted(labset, key=len, reverse=True):
            if norm(l) in t:
                return labset[l]
        return (t.split() or [""])[0]

    def ask(model, q):
        body = json.dumps({"model": model, "temperature": 0, "max_tokens": a.max_tokens,
                           "messages": [{"role": "user", "content":
                               "Choose the single best-matching workflow. Each candidate is 'name — description'. "
                               f"Respond with EXACTLY its name:\n{menu}\n\nINPUT:\n{q}"}]}).encode()
        req = urllib.request.Request("https://openrouter.ai/api/v1/chat/completions", data=body,
                                     headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"})
        for _ in range(a.retries):
            try:
                c = json.loads(urllib.request.urlopen(req, timeout=120).read())["choices"][0]["message"].get("content")
                if c:
                    return c
            except Exception:
                pass
            time.sleep(3)
        return ""   # empty after retries — recorded, not silently counted wrong

    for model in a.models.split(","):
        outdir = os.path.join(HERE, "results", model.replace("/", "_"))
        os.makedirs(outdir, exist_ok=True)
        results = {}
        empty = hallu = 0
        with cf.ThreadPoolExecutor(max_workers=a.workers) as ex:
            for r, raw in zip(rows, ex.map(lambda r: ask(model, r["query"]), rows)):
                results[r["id"]] = raw
                if not (raw or "").strip():
                    empty += 1
                elif not on_menu(raw):
                    hallu += 1
        outpath = os.path.join(outdir, "cross_domain_routing_catalog_described.jsonl")
        with open(outpath, "w") as f:
            for r in rows:
                f.write(json.dumps({"id": r["id"], "prediction": parse(results[r["id"]])}) + "\n")
        json.dump({"model": model, "n": len(rows), "empty": empty, "hallucination": hallu,
                   "max_tokens": a.max_tokens, "menu": "described"},
                  open(os.path.join(outdir, "cross_domain_routing_catalog_described.audit.json"), "w"), indent=2)
        print(f"{model:32s} n={len(rows)} empty={empty} hallucination={hallu} -> {outpath}")
    print("\nDone. Re-run `python3 regen_leaderboard_csv.py` for a uniform, empties-flagged routing column.")


if __name__ == "__main__":
    main()
