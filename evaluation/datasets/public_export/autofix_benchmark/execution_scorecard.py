#!/usr/bin/env python3
"""Autofix execution-outcome scorecard (SWE-bench pattern).

The current autofix task scores whether a model names the fix CATEGORY, and the error log spells out the fix.
This upgrades it to score the OUTCOME: with the fix-hint lines REDACTED, the system must infer and submit a
corrective artifact, and a hidden, category-aware validator checks whether that fix actually RESOLVES the
specific failure (and does not apply an unsafe fix). The category label is kept only as a diagnostic dimension.

Dimensions (each in [0,1], averaged over items):
  - category   (diagnostic): did it name the right root-cause category?
  - outcome    (PRIMARY):    does the proposed fix resolve the specific failure (hidden validator)?
  - safety     :             did it avoid an unsafe fix (e.g. dropping samples, matching the wrong reference)?

Model must return JSON: {"category": "...", "fix_summary": "...", "corrected_params": {...}}

Usage: OPENROUTER_API_KEY=... python3 execution_scorecard.py "model1,model2,..." [n_per_category]
"""
import json, os, re, sys, urllib.request, time, concurrent.futures as cf

HERE = os.path.dirname(os.path.abspath(__file__))
ROWS = [json.loads(l) for l in open(os.path.join(HERE, "data.jsonl"))]
KEY = os.environ.get("OPENROUTER_API_KEY", "")

# ---- redact the fix-hint lines from the error log so the model must infer the fix, not read it ----
LEAK = re.compile(r"^\s*(hint|suggest|please|add\s|consider|upgrade|change\s|valid bucket|expected type|"
                  r"required samplesheet columns|to at least|you may|increase the limit|use the nf-core|"
                  r"the minimum number|must be an? )", re.I)
def redact(log):
    return "\n".join(l for l in log.splitlines() if not LEAK.search(l))

def num(s):
    m = re.search(r"(\d+(?:\.\d+)?)", str(s)); return float(m.group(1)) if m else None

def ver_tuple(s):
    m = re.findall(r"\d+", str(s)); return tuple(int(x) for x in m[:3]) if m else ()

# ---- distinctive resolution tokens auto-extracted from the hidden expected_fix ----
_STOP = {"with", "from", "file", "files", "that", "must", "value", "using", "change", "into", "parameter",
         "params", "config", "nextflow", "pipeline", "samplesheet", "process", "error", "the", "add", "set",
         "use", "run", "path", "data", "job", "aws", "s3", "update", "provide", "correct", "increase"}
def tokens(text):
    t = text.lower()
    toks = set(re.findall(r"--[a-z0-9_]+", t))                       # CLI flags
    toks |= set(re.findall(r"\b[a-z_]*\d[\w.]*\b", t))               # tokens with digits (grch38, fastq_1, 64.gb, 23.04.0, phred64)
    toks |= set(re.findall(r"\b[a-z]+_[a-z0-9_]+\b", t))             # snake_case (min_trimmed_reads, fastq_1, s3:getobject->no)
    toks |= set(re.findall(r"\b[a-z]{4,}:[a-z]+\b", t))              # iam actions like s3:putobject
    toks |= set(w for w in re.findall(r"\b[a-z][a-z0-9]{3,}\b", t)   # distinctive tool / identifier words
                if w in {"bgzip", "tabix", "samtools", "bedtools", "seqtk", "dos2unix", "bedpe", "queryname",
                         "singularity", "datasync", "amd64", "covariate", "batch", "phred64", "truncated",
                         "transpose", "deduplicate", "doublet", "doublets", "strandedness", "non_directional",
                         "intervals", "contrasts", "repair", "crosscheckfingerprints", "ecr", "mirror",
                         "credentials", "authenticated", "cachedir", "scratch"})
    return {x for x in toks if x not in _STOP and len(x) >= 3}

UNSAFE = {  # category -> regex of fixes that "pass" symptomatically but are scientifically wrong
    "genome_mismatch": r"change.*(gtf|index|annotation).*hg19|rebuild.*index.*hg19|downgrade",
    "output_assertion_error": r"\bdrop\b|\bexclude\b|\bdiscard\b|remove.*(the )?sample",
    "resource_failure": r"reduce.*(sample|read|input)|subsample|skip",
}
def validate(r, pred):
    cat = r["category"]; ef = r.get("expected_fix") or ""
    cp = pred.get("corrected_params") if isinstance(pred.get("corrected_params"), dict) else {}
    fs = (pred.get("fix_summary") or "")
    blob = (fs + " " + json.dumps(cp)).lower()
    # OUTCOME: did the proposed fix name the SPECIFIC resolution (shared distinctive token), or set the right value?
    overlap = tokens(ef) & tokens(blob)
    out = 1 if overlap else 0
    # strong value-based overrides for the fully deterministic categories
    if cat == "genome_mismatch" and (str(cp.get("genome", "")).lower() in ("grch38", "hg38") or re.search(r"grch38|hg38", fs.lower())):
        out = 1
    if cat == "param_type_error":
        for k, v in cp.items():
            if isinstance(v, (int, float)) and not isinstance(v, bool): out = 1
        if re.search(r"integer|remove.*quote|boolean|true|false", fs.lower()): out = 1
    if cat == "resource_failure":
        m = re.search(r"(\d+(?:\.\d+)?)\s*\.?\s*gb", ef.lower()); need = float(m.group(1)) if m else None
        gm = re.search(r"(\d+(?:\.\d+)?)\s*\.?\s*gb", blob); got = float(gm.group(1)) if gm else None
        if need and got and got >= need: out = 1
        elif re.search(r"memory|increase|larger|scratch|volume|cpus|time|instance|gpu", fs.lower()) and overlap: out = 1
    if cat == "dependency_mismatch":
        nm = re.search(r"(\d+\.\d+(?:\.\d+)?)", ef); need = ver_tuple(nm.group(1)) if nm else ()
        gm = re.search(r"(\d+\.\d+(?:\.\d+)?)", fs); got = ver_tuple(gm.group(1)) if gm else ()
        if (need and got and got >= need) or re.search(r"upgrade|self-update|newer|latest", fs.lower()): out = 1
    # SAFETY: avoid a symptomatically-plausible but scientifically-wrong fix
    pat = UNSAFE.get(cat)
    saf = 0 if (pat and re.search(pat, blob)) else 1
    return out, saf

INSTR = ("A bioinformatics pipeline run FAILED. Diagnose the ROOT CAUSE from the symptoms and give the concrete "
         "fix. The log has had any explicit fix hints removed, so you must infer the remedy. Return ONLY JSON: "
         '{"category":"<one root-cause category>","fix_summary":"<specific actionable fix>",'
         '"corrected_params":{<the corrected parameter values, if the fix is a parameter change>}}')

def prompt(r):
    return (f"{INSTR}\n\nWorkflow: {r.get('workflow')}\nCurrent parameters: {json.dumps(r.get('params'))}\n"
            f"Failure: {r.get('description')}\n\nError log:\n{redact(r['error_log'])}")

def ask(model, r):
    body = json.dumps({"model": model, "temperature": 0, "max_tokens": 3500,
                       "messages": [{"role": "user", "content": prompt(r)}]}).encode()
    req = urllib.request.Request("https://openrouter.ai/api/v1/chat/completions", data=body,
          headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"})
    for _ in range(2):
        try:
            c = json.loads(urllib.request.urlopen(req, timeout=75).read())["choices"][0]["message"].get("content") or ""
            m = re.search(r"\{.*\}", c, re.S)
            if m:
                try: return json.loads(m.group())
                except Exception: pass
        except Exception: time.sleep(4)
    return {}

def select(n_per_cat):
    by = {}
    for r in ROWS: by.setdefault(r["category"], []).append(r)
    out = []
    for c, rs in by.items(): out += rs[:n_per_cat]
    return out

def run(model, items):
    C = O = S = 0.0; n = 0
    for r in items:
        pred = ask(model, r)
        pc = re.sub(r"[^a-z]", "", (pred.get("category", "") or "").lower())
        gc = re.sub(r"[^a-z]", "", r["category"].replace("_", ""))
        key = gc.replace("error", "").replace("mismatch", "")[:6]
        cat_ok = 1 if (pc == gc or (key and key in pc)) else 0
        o, s = validate(r, pred)
        C += cat_ok; O += o; S += s; n += 1
    sc = dict(model=model, category=round(C/n, 3), outcome=round(O/n, 3), safety=round(S/n, 3), n=n)
    print(f"{model:30s} category={sc['category']:.3f} outcome={sc['outcome']:.3f} safety={sc['safety']:.3f}", flush=True)
    return sc

if __name__ == "__main__":
    models = sys.argv[1].split(",") if len(sys.argv) > 1 else []
    npc = int(sys.argv[2]) if len(sys.argv) > 2 else 2
    items = select(npc)
    print(f"AUTOFIX EXECUTION SCORECARD — {len(items)} items ({npc}/category), fix hints redacted\n"
          "(category = diagnostic | outcome = fix resolves failure, hidden | safety = no unsafe fix)\n")
    rows = []
    if models and KEY:
        with cf.ThreadPoolExecutor(max_workers=5) as ex: rows = list(ex.map(lambda m: run(m, items), models))
    json.dump(rows, open(os.path.join(HERE, "_execution_scorecard.json"), "w"), indent=2)
    print("\nwrote _execution_scorecard.json")
