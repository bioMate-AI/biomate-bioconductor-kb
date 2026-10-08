#!/usr/bin/env python3
"""Build the reverse-decomposition TRAIN set: capability -> biomedical NEED -> natural query.

Direction is REVERSE: start from a real catalog CAPABILITY (whose accept-set is the hidden
answer-key), then have a strong LLM write the 1-few-sentence request a real scientist would
send to obtain it. The query states only the GOAL (data in hand + what to learn/decide +
deliverable); it NEVER names a tool, workflow, method or internal step.

Two phases:
  Phase 1 (--units, no API): sample capability COMBOS across the diversity grid and emit the
          gold (gold_units + structure + aggregation + deliverable + diversity_cell). Lets the
          grader be self-tested with zero API cost.
  Phase 2 (default, OpenRouter): for each gold spec, GENERATE the need-query and round-trip
          VALIDATE it (a second call recovers the implied capabilities from the query alone;
          keep iff it recovers the gold capabilities, drop/relabel otherwise).

Resumable + bounded (a prior agent hung 50 min): per-call timeout, capped concurrency,
incremental append, skip ids already written.

  python build_reverse_decomp.py --units --n 400 --out units.jsonl          # phase 1
  python build_reverse_decomp.py --units-in units.jsonl --out reverse_decomp_train.jsonl \
         --model anthropic/claude-sonnet-4.5 --workers 8 --limit 400         # phase 2
"""
from __future__ import annotations
import json, os, re, sys, time, argparse, random, itertools, urllib.request, urllib.error
from concurrent.futures import ThreadPoolExecutor, as_completed

HERE = os.path.dirname(os.path.abspath(__file__))
import importlib.util
_spec = importlib.util.spec_from_file_location("cap_lex", os.path.join(HERE, "capability_lexicon.py"))
cap_lex = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(cap_lex)

OPENROUTER_KEY_PATH = os.path.expanduser("~/.config/biomate/openrouter.key")
OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"

# ----------------------------------------------------------------------------------------
# canonical TRAIN pipelines — capability role SEQUENCES (each resolves to a real accept-set).
# These are standard biology, NOT workflow_chains rows -> source-unit-disjoint from the TEST
# set (which is harvested from workflow_chains / GTN). Prefixes give complexity variety.
# ----------------------------------------------------------------------------------------
PIPELINES = {
    "transcriptomics:de": ["transcriptomics:read_qc", "transcriptomics:rnaseq_quantification",
                           "transcriptomics:differential_expression", "transcriptomics:pathway_enrichment"],
    "variant:germline": ["transcriptomics:read_qc", "genomics:read_alignment",
                         "variant_calling:germline_variant_calling", "variant_calling:variant_annotation"],
    "variant:somatic": ["genomics:read_alignment", "variant_calling:somatic_variant_calling",
                        "variant_calling:variant_annotation"],
    "single_cell:std": ["single_cell:single_cell_qc_norm", "single_cell:batch_integration",
                       "single_cell:cell_type_annotation"],
    "proteomics:idquant": ["proteomics:peptide_identification", "proteomics:protein_quantification"],
    "epigenomics:peaks": ["transcriptomics:read_qc", "genomics:read_alignment", "epigenomics:peak_calling"],
    "metagenomics:profile": ["transcriptomics:read_qc", "metagenomics:taxonomic_classification"],
    "genomics:assembly": ["transcriptomics:read_qc", "genomics:genome_assembly"],
    "structural:fold_dock": ["structural_biology:protein_structure_prediction", "drug_discovery:molecular_docking"],
    "epigenomics:methyl": ["transcriptomics:read_qc", "epigenomics:methylation_analysis"],
    "metabolomics:features": ["transcriptomics:read_qc", "metabolomics:ms_feature_detection"],
    "genomics:phylo": ["genomics:multiple_sequence_alignment", "genomics:phylogenetic_tree"],
}
# multi-domain parallel-then-aggregate combos (two independent branches -> selection/ranking)
MULTI_DOMAIN = [
    ("drug_discovery:admet_prediction", "drug_discovery:molecular_docking", "rank"),
    ("drug_discovery:admet_prediction", "drug_discovery:qsar_modeling", "select"),
    ("variant_calling:germline_variant_calling", "transcriptomics:differential_expression", "integrate"),
    ("single_cell:cell_type_annotation", "transcriptomics:pathway_enrichment", "integrate"),
]
# single-capability + category-set units
SINGLE_CAPS = ["transcriptomics:differential_expression", "transcriptomics:pathway_enrichment",
               "drug_discovery:admet_prediction", "drug_discovery:molecular_docking",
               "variant_calling:germline_variant_calling", "single_cell:cell_type_annotation",
               "metagenomics:taxonomic_classification", "structural_biology:protein_structure_prediction",
               "proteomics:peptide_identification", "metabolomics:ms_feature_detection"]
CATEGORY_CAPS = ["proteomics:peptide_toolset", "drug_discovery:cheminformatics_toolset"]

# diversity grid axes
GRID = {
    "specificity": ["explicit_params", "vague", "negation_constraint"],
    "input": ["explicit", "recover_from_prior", "accession"],
    "count": ["single", "multi_task"],
    "persona": ["terse_PI", "verbose_postdoc", "zh", "lay", "jargon"],
    "output_intent": ["run", "run_rank_select", "interpret"],
}


def _unit(cap_id, caps, order, depends_on):
    c = caps[cap_id]
    return {"order": order, "depends_on": depends_on, "capability": c["capability"],
            "domain": c["domain"], "deliverable": c["deliverable"],
            "accept_set": c["accept_set"], "is_category_set": c.get("is_category_set", False),
            "n_accept": c["n_members"], "cap_id": cap_id}


def sample_units(caps, n, seed=7):
    """Emit n gold specs (no query yet) across complexity x diversity grid."""
    rng = random.Random(seed)
    out, sig_seen = [], set()

    def cell():
        return {k: rng.choice(v) for k, v in GRID.items()}

    def add(gold_units, structure, aggregation, complexity, source_unit):
        # dataset scale = STRUCTURE x diversity-cell; the dedup signature folds both in so one
        # capability combo yields many distinct, structurally-diverse natural queries.
        c = cell()
        cell_sig = "|".join(f"{k}={c[k]}" for k in sorted(c))
        full_sig = f"{source_unit}##{cell_sig}"
        if full_sig in sig_seen:
            return False
        sig_seen.add(full_sig)
        out.append({"gold_units": gold_units, "structure": structure,
                    "aggregation": aggregation, "complexity": complexity,
                    "deliverable": gold_units[-1]["deliverable"], "source_unit": source_unit,
                    "diversity_cell": c, "provenance": "reverse_generated"})
        return True

    attempts = 0
    while len(out) < n and attempts < n * 40:
        attempts += 1
        r = rng.random()
        if r < 0.22:  # single capability
            cid = rng.choice([c for c in SINGLE_CAPS if c in caps])
            gu = [_unit(cid, caps, 1, [])]
            add(gu, "single", "none", "single", f"single::{cid}")
        elif r < 0.32:  # category set
            cid = rng.choice([c for c in CATEGORY_CAPS if c in caps])
            gu = [_unit(cid, caps, 1, [])]
            add(gu, "single", "none", "category", f"category::{cid}")
        elif r < 0.78:  # linear pipeline (a prefix of a canonical pipeline, len 2..full)
            pname = rng.choice(list(PIPELINES))
            seq = [c for c in PIPELINES[pname] if c in caps]
            if len(seq) < 2:
                continue
            k = rng.randint(2, len(seq))
            start = rng.randint(0, len(seq) - k)
            seq = seq[start:start + k]
            gu = [_unit(seq[0], caps, 1, [])]
            for i, cid in enumerate(seq[1:], start=2):
                gu.append(_unit(cid, caps, i, [i - 1]))
            agg = "none"
            add(gu, "sequential", agg, "linear",
                f"linear::{pname}::{start}:{k}")
        else:  # multi-domain: two parallel branches -> aggregation (fan-in)
            a, b, aggk = rng.choice(MULTI_DOMAIN)
            if a not in caps or b not in caps:
                continue
            gu = [_unit(a, caps, 1, []), _unit(b, caps, 2, [])]
            # aggregation node (role = the selection/ranking; accept-set = the two deliverables' consumers)
            gu.append({"order": 3, "depends_on": [1, 2], "capability": aggk + "_selection",
                       "domain": "systems_biology", "deliverable": aggk + "ed_shortlist",
                       "accept_set": [aggk], "is_category_set": False, "n_accept": 1,
                       "cap_id": f"agg:{aggk}"})
            add(gu, "mixed", aggk, "multi_domain", f"multidomain::{a}+{b}::{aggk}")
    return out


# ----------------------------------------------------------------------------------------
# OpenRouter
# ----------------------------------------------------------------------------------------
def _key():
    with open(OPENROUTER_KEY_PATH) as f:
        return f.read().strip()


def call_openrouter(messages, model, key, timeout=45, max_tokens=700, temperature=0.9):
    body = json.dumps({"model": model, "messages": messages, "max_tokens": max_tokens,
                       "temperature": temperature}).encode()
    req = urllib.request.Request(OPENROUTER_URL, data=body, method="POST", headers={
        "Authorization": f"Bearer {key}", "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        d = json.loads(r.read().decode())
    content = d["choices"][0]["message"].get("content")
    return content or ""   # some models return null content (reasoning); coerce to "" not None


# ----------------------------------------------------------------------------------------
# REAL style exemplars (few-shot) — harvested real queries anchor the generator to real voice
# so it does not emit its sanitized default. Exemplars are used for STYLE ONLY (never as labels);
# generated queries are deduped against them so none is copied into TRAIN.
# ----------------------------------------------------------------------------------------
def load_exemplars(path):
    """Group real queries by complexity band (single-step vs multi-step) from a jsonl with
    {query, gold_units}. Used for few-shot style seeding."""
    band = {"single": [], "multi": []}
    norms = set()
    if not path or not os.path.exists(path):
        return band, norms
    for l in open(path):
        try:
            r = json.loads(l)
        except Exception:
            continue
        q = (r.get("query") or "").strip()
        if not q:
            continue
        norms.add(_qnorm(q))
        b = "single" if len(r.get("gold_units", [])) <= 1 else "multi"
        band[b].append(q)
    return band, norms


def _qnorm(q):
    return re.sub(r"\s+", " ", re.sub(r"[^a-z0-9 ]", "", str(q).lower())).strip()[:160]


def _fewshot_block(exemplars, complexity, rng, k=4):
    band = "single" if complexity in ("single", "category") else "multi"
    pool = exemplars.get(band) or exemplars.get("multi") or exemplars.get("single") or []
    if not pool:
        return ""
    picks = rng.sample(pool, min(k, len(pool)))
    ex = "\n".join(f"  - {p}" for p in picks)
    return ("\nHere are REAL requests from working scientists. Imitate their VOICE, length and "
            "register (NOT their specific science/content):\n" + ex + "\n")


GEN_SYS = (
    "You write realistic biomedical analysis requests exactly as a working scientist would send "
    "to a bioinformatics assistant. You are given the HIDDEN capability the request must map to. "
    "Write ONLY the request. ABSOLUTE RULES: (1) State the scientific GOAL — the data/material in "
    "hand, what the scientist wants to learn/decide/produce, and the expected deliverable. "
    "(2) NEVER name any tool, software, algorithm, package, workflow, pipeline, database, or "
    "internal processing step (no 'DESeq2', 'STAR', 'GATK', 'alignment', 'normalization', "
    "'peak calling' — describe the GOAL, e.g. 'find which genes change between conditions'). "
    "(3) Match the requested STYLE cell precisely. (4) 1-4 sentences. (5) SCOPE: ask ONLY for the "
    "hidden capability's goal and its deliverable — do NOT pile on extra downstream analyses, "
    "sub-questions, or 'the works' laundry lists beyond what the stated capability produces. "
    "Output the request text only, no preamble, no quotes.")


def _cell_instructions(cell, gold_units, aggregation):
    goals = "; ".join(f"{u['capability'].replace('_',' ')} (-> {u['deliverable'].replace('_',' ')})"
                      for u in gold_units)
    lines = [f"HIDDEN capability chain (do NOT reveal, phrase only as a goal): {goals}"]
    sp = cell["specificity"]
    lines.append({"explicit_params": "Include 1-2 concrete biological parameters (organism, "
                  "tissue, condition names, a threshold) phrased naturally.",
                  "vague": "Keep it loose; omit specifics, just the scientific question.",
                  "negation_constraint": "Include one NEGATION/constraint (e.g. 'but not the raw "
                  "QC, I already did that' or 'without using any paid method')."}[sp])
    lines.append({"explicit": "Name the input data concretely (e.g. 'my 24 paired-end FASTQ files').",
                  "recover_from_prior": "Refer to data produced by a previous step without re-specifying it.",
                  "accession": "Reference a public accession (e.g. a GEO/SRA/PDB id) as the input."}[cell["input"]])
    if cell["count"] == "multi_task":
        lines.append("Ask for TWO related things in one message.")
    lines.append({"terse_PI": "Voice: a terse senior PI, 1 sentence, imperative.",
                  "verbose_postdoc": "Voice: a verbose postdoc giving background and motivation.",
                  "zh": "Write the ENTIRE request in natural, idiomatic Simplified Chinese.",
                  "lay": "Voice: a wet-lab biologist with little computational jargon.",
                  "jargon": "Voice: heavy domain jargon, assumes expert reader."}[cell["persona"]])
    lines.append({"run": "Intent: just get it done.",
                  "run_rank_select": "Intent: run it AND rank/shortlist the best candidates.",
                  "interpret": "Intent: run it AND interpret what the result means biologically."}[cell["output_intent"]])
    if aggregation and aggregation != "none":
        lines.append(f"The two analyses must be COMBINED/{aggregation} into one decision at the end "
                     "(phrase as a goal, e.g. 'and tell me which candidates win on both').")
    return "\n".join(lines)


VAL_SYS = (
    "You are a bioinformatics planner. Given ONLY a scientist's request, list the distinct "
    "FUNCTIONAL capabilities (analysis steps) needed to satisfy it, as a short JSON array of "
    "lowercase phrases (e.g. [\"differential expression\",\"pathway enrichment\"]). "
    "Do not name tools. Output only the JSON array.")


def _leak_check(query, gold_units):
    """Hard reject if the query leaked a known tool/method token."""
    banned = {"deseq2", "edger", "limma", "star", "salmon", "hisat2", "gatk", "bwa", "bowtie",
              "macs2", "macs3", "seurat", "scanpy", "alphafold", "autodock", "vina", "kraken",
              "maxquant", "fastqc", "multiqc", "bismark", "clusterprofiler", "haplotypecaller",
              "deepvariant", "nextflow", "nf-core", "nfcore", "normalization", "alignment",
              "peak calling", "variant calling", "enrichment analysis"}
    q = query.lower()
    return [b for b in banned if b in q]


def _roles_recovered(recovered, gold_units, thresh=0.5):
    """Round-trip: did the capabilities recovered from the query cover the gold roles?"""
    def toks(s):
        return {t for t in re.findall(r"[a-z0-9]+", s.lower())} - cap_lex_stop
    gold_core = [u for u in gold_units if not u["cap_id"].startswith("agg:")
                 and u["capability"] not in ("read_qc",)]  # QC is implicit, not required to recover
    if not gold_core:
        gold_core = gold_units
    rtoks = [toks(x) for x in recovered]
    hit = 0
    for u in gold_core:
        g = toks(u["capability"].replace("_", " "))
        if any(len(g & rt) / max(1, len(g)) >= 0.5 for rt in rtoks):
            hit += 1
    return hit / len(gold_core)


cap_lex_stop = {"the", "a", "an", "of", "and", "to", "analysis", "data", "step"}


REALISM_SYS = (
    "You judge whether a message reads like it was written by a real working scientist to a "
    "bioinformatics assistant, versus a sanitized/templated AI-generated prompt. Answer with a "
    "single token: REAL or SYNTHETIC. SYNTHETIC tells: over-complete laundry lists, unnatural "
    "completeness, textbook tone, 'I would like to request that you perform', no elision.")


def _realism_ok(q, model, key):
    try:
        v = call_openrouter([{"role": "system", "content": REALISM_SYS},
                             {"role": "user", "content": q}], model, key,
                            max_tokens=8, temperature=0.0).strip().upper()
        # only DROP on an explicit SYNTHETIC verdict; ambiguous / non-English replies -> keep
        # (the discriminator sometimes answers in the query's language, which is not a reject)
        if "SYNTHETIC" in v and "REAL" not in v:
            return False, v
        return True, v
    except Exception:
        return True, "skip"   # don't drop on discriminator error


def generate_one(spec, model, key, do_validate=True, exemplars=None, test_norms=None, rng=None):
    cell = spec["diversity_cell"]
    rng = rng or random.Random(hash(spec.get("id", "")) & 0xffffffff)
    user = _cell_instructions(cell, spec["gold_units"], spec["aggregation"])
    if exemplars:
        user += _fewshot_block(exemplars, spec["complexity"], rng)
    q = ""
    for _ in range(2):  # one retry: models occasionally return empty (reasoning) content
        q = call_openrouter([{"role": "system", "content": GEN_SYS},
                             {"role": "user", "content": user}], model, key).strip().strip('"')
        if q:
            break
    if not q:
        row = dict(spec); row["query"] = None
        row["validation"] = {"status": "error:empty_content"}
        return row
    leak = _leak_check(q, spec["gold_units"])
    dup = bool(test_norms and _qnorm(q) in test_norms)
    realism_ok, realism_tok = _realism_ok(q, model, key)
    status = "ok"
    recovered, rt = [], None
    if leak:
        status = "rejected_leak"
    elif dup:
        status = "rejected_dup_test"      # never let a test query leak into train
    elif not realism_ok:
        status = "rejected_synthetic"     # realism discriminator
    elif do_validate:
        try:
            raw = call_openrouter([{"role": "system", "content": VAL_SYS},
                                   {"role": "user", "content": q}], model, key,
                                  max_tokens=300, temperature=0.0)
            m = re.search(r"\[.*\]", raw, re.S)
            recovered = json.loads(m.group()) if m else []
            if not isinstance(recovered, list):
                recovered = []
        except Exception:
            recovered = []
        rt = _roles_recovered([str(x) for x in recovered], spec["gold_units"])
        if rt < 0.5:
            status = "rejected_roundtrip"   # query under-specifies the gold capability
    n_gold_core = max(1, len([u for u in spec["gold_units"] if not u["cap_id"].startswith("agg:")]))
    overspec = (len(recovered) / n_gold_core) if recovered else None
    row = dict(spec)
    row["query"] = q
    row["validation"] = {"status": status, "leak_tokens": leak, "realism": realism_tok,
                         "roundtrip_recall": rt, "recovered": recovered,
                         "n_recovered": len(recovered), "overspec_ratio": overspec}
    return row


def phase2(units, out_path, model, workers, key, limit=None, validate=True,
           exemplars=None, test_norms=None):
    done_ids = set()
    if os.path.exists(out_path):
        for l in open(out_path):
            try:
                done_ids.add(json.loads(l)["id"])
            except Exception:
                pass
    todo = []
    for i, u in enumerate(units):
        u = dict(u); u["id"] = u.get("id") or f"rev_{u['complexity']}_{i}"
        if u["id"] in done_ids:
            continue
        todo.append(u)
    if limit:
        todo = todo[:limit]
    print(f"phase2: {len(todo)} to generate (model={model}, workers={workers}), "
          f"{len(done_ids)} already done", flush=True)
    kept = rej = err = 0
    t0 = time.time()
    with open(out_path, "a") as fout, ThreadPoolExecutor(max_workers=workers) as ex:
        futs = {ex.submit(generate_one, u, model, key, validate, exemplars, test_norms,
                          random.Random(i)): u for i, u in enumerate(todo)}
        for n, fut in enumerate(as_completed(futs), 1):
            u = futs[fut]
            try:
                row = fut.result()
            except Exception as e:
                err += 1
                row = dict(u); row["query"] = None
                row["validation"] = {"status": f"error:{type(e).__name__}"}
            fout.write(json.dumps(row) + "\n"); fout.flush()
            st = row["validation"]["status"]
            if st == "ok":
                kept += 1
            elif st.startswith("rejected"):
                rej += 1
            if n % 10 == 0 or n == len(todo):
                print(f"  [{n}/{len(todo)}] kept={kept} rejected={rej} err={err} "
                      f"({time.time()-t0:.0f}s)", flush=True)
    print(f"phase2 done: kept={kept} rejected={rej} err={err}", flush=True)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--units", action="store_true", help="phase 1: emit gold specs only")
    ap.add_argument("--units-in", help="phase 2: gold specs file produced by --units")
    ap.add_argument("--n", type=int, default=400)
    ap.add_argument("--out", required=True)
    ap.add_argument("--accept-sets", default=os.path.join(HERE, "accept_sets.json"))
    ap.add_argument("--model", default="anthropic/claude-sonnet-4.5")
    ap.add_argument("--workers", type=int, default=8)
    ap.add_argument("--limit", type=int, default=None)
    ap.add_argument("--no-validate", action="store_true")
    ap.add_argument("--exemplars", help="jsonl of REAL queries for few-shot style seeding + "
                                        "test-dedup (e.g. reverse_decomp_test_real.jsonl)")
    ap.add_argument("--seed", type=int, default=7)
    a = ap.parse_args()
    caps = json.load(open(a.accept_sets))
    if a.units:
        specs = sample_units(caps, a.n, a.seed)
        with open(a.out, "w") as f:
            for i, s in enumerate(specs):
                s["id"] = f"rev_{s['complexity']}_{i}"
                f.write(json.dumps(s) + "\n")
        from collections import Counter
        print(f"emitted {len(specs)} gold specs -> {a.out}")
        print("complexity:", dict(Counter(s["complexity"] for s in specs)))
    elif a.units_in:
        units = [json.loads(l) for l in open(a.units_in) if l.strip()]
        exemplars, test_norms = load_exemplars(a.exemplars)
        if a.exemplars:
            print(f"loaded {sum(len(v) for v in exemplars.values())} real exemplars "
                  f"({len(test_norms)} test-dedup norms) from {a.exemplars}", flush=True)
        phase2(units, a.out, a.model, a.workers, _key(), a.limit, not a.no_validate,
               exemplars, test_norms)
    else:
        ap.error("pass --units (phase 1) or --units-in (phase 2)")
