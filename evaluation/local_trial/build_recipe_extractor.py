"""Literature -> ANALYSIS-RECIPE multi-task extractor. Per full-text paper, LLM-extract the analysis recipe
{problem, study_design, data, tools[], parameters[], results, findings, conclusion}, GROUND the tools against
our catalog (grounded-by-construction), and emit a grounded multi-task chain spanning the BioMate task
spectrum. Unmatched tools -> a catalog-expansion queue (the literature-coverage gap). Also feeds DB enrichment.

Tasks emitted per paper (only when the field is present + grounded):
  research_question / task_decomposition / dataset_prerequisite_check / tool_recommendation /
  parameter_extraction / findings_interpretation / conclusion_drawing
Usage:
  OPENAI_API_KEY=... python build_recipe_extractor.py --lit pmc_fulltext.jsonl --dbcat db_catalog.jsonl \
     --out recipe_sft.jsonl --gap-out tool_coverage_gap.jsonl --n 4000
"""
import argparse, json, os, re, time, urllib.request, collections
from concurrent.futures import ThreadPoolExecutor

KEY = os.environ.get("OPENAI_API_KEY"); GEN = os.environ.get("PARA_MODEL", "gpt-5-mini")


def canon(s): return re.sub(r"[\s_./-]+", " ", str(s).lower()).strip()


def load_catalog(dbcat):
    tool = set(); wf = set()
    for l in open(dbcat):
        t = json.loads(l).get("text", "")
        m = re.search(r"^Name:\s*(.+)$", t, re.M)
        if m and "Description:" in t: wf.add(canon(m.group(1)))
        mt = re.search(r"`([^`]+)` tool", t)
        if mt: tool.add(canon(mt.group(1)))
    return wf, tool


def call(prompt, n=900):
    body = json.dumps({"model": GEN, "messages": [{"role": "user", "content": prompt}],
                       "max_completion_tokens": n, "reasoning_effort": "low"}).encode()
    for _ in range(3):
        try:
            d = json.load(urllib.request.urlopen(urllib.request.Request(
                "https://api.openai.com/v1/chat/completions", data=body,
                headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"}), timeout=90))
            return d["choices"][0]["message"]["content"]
        except Exception:
            time.sleep(1.5)
    return ""


SCHEMA = ("Extract the ANALYSIS RECIPE from this biomedical paper as JSON, grounded ONLY in the text:\n"
          "{\"problem\": one-sentence research problem/objective,\n"
          " \"study_design\": the analysis plan as ordered steps,\n"
          " \"data\": the input data/assay type,\n"
          " \"tools\": [software/methods actually used],\n"
          " \"parameters\": [notable parameter=value settings mentioned],\n"
          " \"results\": concrete results/numbers,\n"
          " \"findings\": what the results mean,\n"
          " \"conclusion\": conclusion + implications}\n"
          "Omit any field not stated. Reply ONLY the JSON.\n\nPAPER:\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lit", required=True); ap.add_argument("--dbcat", required=True)
    ap.add_argument("--out", required=True); ap.add_argument("--gap-out", default="tool_coverage_gap.jsonl")
    ap.add_argument("--n", type=int, default=4000); ap.add_argument("--workers", type=int, default=12)
    a = ap.parse_args()
    if not KEY:
        print("no OPENAI_API_KEY — abort"); return 1
    wf, tool = load_catalog(a.dbcat); catalog = wf | tool
    print(f"catalog grounding set: {len(catalog):,} names", flush=True)
    # DOMAIN FILTER: only computational-biology papers — random PMC (clinical/humanities) yields noise
    # ("iodine", "national portrait gallery") not bioinformatics tools. Require >=2 signal terms OR a catalog tool.
    BIOINFO = re.compile(r"\b(bioinformatic|sequenc|RNA-?seq|scRNA|single-cell|genome|transcriptom|proteom|"
                         r"variant call|alignment|read(s)?\b|FASTQ|BAM|VCF|differential expression|"
                         r"assembl|annotation|pipeline|workflow|CHIP-?seq|ATAC|metagenom|phylogen|"
                         r"gene expression|reference genome|nextflow|galaxy|bioconductor)\b", re.I)
    catl = [n for n in catalog if len(n) > 4]
    texts = []
    for l in open(a.lit):
        try: t = json.loads(l).get("text", "")
        except Exception: continue
        if len(t) <= 800:            # keep long full-text (was wrongly excluded at 14000); call truncates to 10k
            continue
        head = t[:6000]
        if len(BIOINFO.findall(head)) >= 2 or any(c in head.lower() for c in catl[:2000]):
            texts.append(t)
        if len(texts) >= a.n: break
    print(f"papers to process (bioinformatics-scoped): {len(texts):,}", flush=True)

    def S(x):  # coerce any LLM field (str | list | None) to a clean string
        if isinstance(x, list): return " ; ".join(str(i) for i in x).strip()
        return str(x or "").strip()

    def one(t):
      try:
        o = call(SCHEMA + t[:10000]); m = re.search(r"\{.*\}", o, re.S)
        if not m: return ([], [])
        try: r = json.loads(m.group(0))
        except Exception: return ([], [])
        rows = []; gaps = []
        def L(x):  # a string field must NOT be iterated char-by-char; wrap it as a single-item list
            return x if isinstance(x, list) else ([x] if isinstance(x, str) and x.strip() else [])
        prob = S(r.get("problem")); design = r.get("study_design"); data = S(r.get("data"))
        tools = [x.strip() for x in L(r.get("tools")) if isinstance(x, str) and len(x.strip()) > 1]
        params = [x.strip() for x in L(r.get("parameters")) if isinstance(x, str) and len(x.strip()) > 1]
        results = S(r.get("results")); findings = S(r.get("findings")); concl = S(r.get("conclusion"))
        # RECENCY: PMCID != publication year (bulk includes digitized OLD papers, e.g. 1800s Chicago Med Exam).
        # Old tool/param settings are stale -> gate the TIME-SENSITIVE tasks on year>=RECENT_MIN. Findings/
        # decomposition are time-INVARIANT skills -> always kept.
        yrs = [int(y) for y in re.findall(r"\b(19\d{2}|20\d{2})\b", t[:4000])]
        recent_ok = (not yrs) or (max(yrs) >= int(os.environ.get("RECENT_MIN", "2018")))
        grounded = [x for x in tools if canon(x) in catalog]
        for x in tools:
            if canon(x) not in catalog: gaps.append(x)
        SYS = "You are BioMate, an agentic bioinformatics assistant."
        if prob and design:
            dz = design if isinstance(design, str) else " ; ".join(map(str, design))
            rows.append({"messages": [{"role": "system", "content": SYS},
                {"role": "user", "content": f"Research problem: {prob}" + (f"\nData: {data}" if data else "") + "\n\nOutline the analysis plan (ordered steps)."},
                {"role": "assistant", "content": dz}], "task": "task_decomposition", "source": "recipe_lit"})
        if prob and grounded and recent_ok:   # tool recs from old papers can be stale -> recency-gated
            rows.append({"messages": [{"role": "system", "content": SYS},
                {"role": "user", "content": f"For this task, what tools/methods are appropriate?\nTask: {prob}" + (f"\nData: {data}" if data else "")},
                {"role": "assistant", "content": "Suitable tools/methods: " + ", ".join(grounded) + "."}], "task": "tool_recommendation", "source": "recipe_lit"})
        if grounded and params and recent_ok:  # param values age fastest -> recency-gated
            rows.append({"messages": [{"role": "system", "content": SYS},
                {"role": "user", "content": f"Using {', '.join(grounded[:4])} for: {prob}. What parameter settings are appropriate?"},
                {"role": "assistant", "content": "Parameters: " + "; ".join(params) + "."}], "task": "parameter_extraction", "source": "recipe_lit"})
        if prob and data:
            rows.append({"messages": [{"role": "system", "content": SYS},
                {"role": "user", "content": f"What input data is required for: {prob}?"},
                {"role": "assistant", "content": data}], "task": "dataset_prerequisite_check", "source": "recipe_lit"})
        if results and findings:
            rows.append({"messages": [{"role": "system", "content": SYS},
                {"role": "user", "content": f"Here are the analysis results:\n{results}\n\nInterpret them and state the key findings."},
                {"role": "assistant", "content": findings}], "task": "findings_interpretation", "source": "recipe_lit"})
        if results and concl:
            rows.append({"messages": [{"role": "system", "content": SYS},
                {"role": "user", "content": f"Given these results:\n{results}\n\nWhat can be concluded, and what are the implications?"},
                {"role": "assistant", "content": concl}], "task": "conclusion_drawing", "source": "recipe_lit"})
        return (rows, gaps)
      except Exception:
        return ([], [])   # one bad article must not kill the whole pool

    allrows = []; allgaps = collections.Counter()
    with ThreadPoolExecutor(max_workers=a.workers) as ex:
        for i, (rows, gaps) in enumerate(ex.map(one, texts)):
            allrows.extend(rows)
            for g in gaps: allgaps[canon(g)] += 1
            if i % 300 == 0: print(f"  {i}/{len(texts)} -> {len(allrows)} tasks, {len(allgaps)} gap-tools", flush=True)
    import random; random.seed(9); random.shuffle(allrows)
    with open(a.out, "w") as f:
        for r in allrows: f.write(json.dumps(r) + "\n")
    with open(a.gap_out, "w") as f:
        for name, c in allgaps.most_common(): f.write(json.dumps({"tool": name, "count": c}) + "\n")
    print(f"RECIPE: {len(allrows):,} tasks -> {a.out} ({dict(collections.Counter(r['task'] for r in allrows))})", flush=True)
    print(f"  catalog-coverage gaps: {len(allgaps):,} distinct tools not in catalog (top: {[n for n,_ in allgaps.most_common(10)]})", flush=True)


if __name__ == "__main__":
    raise SystemExit(main())
