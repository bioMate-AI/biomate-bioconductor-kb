"""Multi-LLM committee audit of the literature-recipe 10k DATA + the extractor CODE, before folding into SFT.
Reuses the committee call infra. Each model independently: (1) rates a sample of recipe instances for
BIOINFORMATICS relevance / correctness / format + estimates contamination %, (2) reviews the extractor code
for bugs and why the domain filter/tool-extraction failed. Synthesis by the caller.
Usage: python committee_recipe_audit.py --recipe recipe_sft.jsonl --code build_recipe_extractor.py --out out.json
"""
import argparse, json, os, collections
from concurrent.futures import ThreadPoolExecutor
from committee_sft_audit import call, MEMBERS


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--recipe", required=True); ap.add_argument("--code", required=True); ap.add_argument("--out", required=True)
    ap.add_argument("--per", type=int, default=5)
    a = ap.parse_args()
    rows = [json.loads(l) for l in open(a.recipe)]
    by = collections.defaultdict(list)
    for r in rows:
        by[r.get("task", "?")].append(r)
    counts = {t: len(v) for t, v in by.items()}
    samples = []
    for t, v in by.items():
        for r in v[:a.per]:
            m = {x["role"]: x["content"] for x in r["messages"]}
            samples.append(f"[{t}]\nUSER: {m.get('user','')[:400]}\nASSISTANT: {m.get('assistant','')[:400]}")
    code = open(a.code).read()
    PROMPT = f"""You are on an expert review committee auditing training data for BioMate, an agentic
BIOINFORMATICS assistant (RNA-seq, variant calling, proteomics, cryo-EM, drug discovery, etc.). This data
was auto-extracted from PubMed Central full-text papers via an LLM "analysis-recipe" extractor, intended to
teach BioMate tasks: findings_interpretation, conclusion_drawing, task_decomposition,
dataset_prerequisite_check, tool_recommendation, parameter_extraction.

Be rigorous and critical. Your job is to decide if this data is safe to fine-tune BioMate on.

# Row counts by task
{json.dumps(counts, indent=2)}

# {len(samples)} real sample instances (user -> assistant)
{chr(10).join(samples)}

# The extractor CODE that produced this data
```python
{code[:9000]}
```

# Audit — answer ALL, be concrete and quantitative:
A. DATA DOMAIN RELEVANCE: What FRACTION of these samples are actually BIOINFORMATICS/computational-biology
   vs off-domain (clinical epidemiology, psychology, tourism, urban planning, materials science, etc.)?
   Give a % estimate and cite specific off-domain examples. Is this data safe to train a BIOINFORMATICS
   assistant on, or will it teach BioMate to handle tourism/psychology studies?
B. CORRECTNESS/FAITHFULNESS: Are the assistant answers faithful to the stated results? Any hallucination,
   mismatch (e.g. a conclusion about different content than the results), or degenerate extraction?
C. TASK-FIT/FORMAT: Do tool_recommendation/parameter_extraction actually contain bioinformatics TOOLS/PARAMS
   (e.g. STAR, DESeq2, --min-count) or generic methods/stats (ANOVA, sample size, PCA)? Are findings/decomp
   well-formed and useful?
D. CODE REVIEW: Find bugs and design flaws in the extractor. WHY did the bioinformatics domain filter let
   through off-domain papers? WHY are tool_recommendation/parameter_extraction near-zero (11-19 of 10k)?
   Concrete fixes (e.g. require catalog-tool mention, journal allowlist, stricter filter).
E. VERDICT: keep-all / keep-subset(which tasks) / drop-all — and the single most important fix.

Return structured prose with headers A-E. Be specific and quantitative."""
    def run(name):
        prov, model = MEMBERS[name]
        if prov == "anthropic" and not os.environ.get("ANTHROPIC_API_KEY"):
            return name, "[skipped: no ANTHROPIC_API_KEY]"
        return name, call(prov, model, PROMPT, mx=6000)
    out = {}
    with ThreadPoolExecutor(max_workers=3) as ex:
        for name, resp in ex.map(run, MEMBERS):
            out[name] = resp; print(f"=== {name} ({'ok' if not resp.startswith('[') else resp[:40]}) ===", flush=True)
    json.dump({"counts": counts, "reviews": out}, open(a.out, "w"), indent=2)
    print(f"COMMITTEE AUDIT -> {a.out}")


if __name__ == "__main__":
    raise SystemExit(main())
