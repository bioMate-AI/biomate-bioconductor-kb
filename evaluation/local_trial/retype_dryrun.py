#!/usr/bin/env python3
"""
retype_dryrun.py  (READ-ONLY — writes NOTHING to the DB)
--------------------------------------------------------
Dry-run of the "separate, not discard" catalog fix: re-derive CLEAN type tokens for the
dirty `input_types` FROM `params_schema` (the structured knowledge: {name, type, description}),
leaving params_schema/description/etc. untouched. Only `input_types` is dirty (output_types is
~0% dirty), and the dirty input descriptions carry object-classes (ExpressionSet,
SingleCellExperiment, SummarizedExperiment, GRanges, …) that match the clean OUTPUT vocabulary —
so derived input tokens exact-match upstream outputs.

Reports: (1) how many dirty-input workflows become fully clean after derivation; (2) the composer
fire-rate on composer_eval's pipelines using the DERIVED input types IN MEMORY (vs the current
2/6) — the payoff of the data fix, before touching the canonical DB.

Run: python3 evaluation/local_trial/retype_dryrun.py
"""
from __future__ import annotations

import sys
for _m in ("sentence_transformers", "torch", "scipy"):
    sys.modules[_m] = None

import json
import re
import sqlite3
from pathlib import Path

_REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(_REPO / "backend" / "lib"))
from galaxy.ai.unified_workflow_search import UnifiedWorkflowSearch  # noqa: E402
from galaxy.ai.decomposed_dag import pick_workflow_match, build_dag_plan  # noqa: E402

_DB = _REPO / "backend" / "database" / "galaxy_ai_tools.db"
_GOLD = _REPO / "evaluation" / "datasets" / "composer_eval" / "pipelines.jsonl"


def _jl(s):
    try:
        return json.loads(s or "[]")
    except Exception:
        return []


def _clean(toks):
    return bool(toks) and all((" " not in t and "(" not in t) for t in toks)


_OBJ_RE = re.compile(
    r"(RangedSummarizedExperiment|TreeSummarizedExperiment|MultiAssayExperiment|"
    r"SingleCellExperiment|SummarizedExperiment|SpatialExperiment|GenomicRatioSet|"
    r"DESeqDataSet|GRangesList|ExpressionSet|DNAStringSet|DataFrame|GRanges|GeneSet|"
    r"FlowSet|FlowFrame|eSet)", re.I)

_NAME_MAP = {
    "counts": "counts_matrix", "count_data": "counts_matrix", "counts_matrix": "counts_matrix",
    "expression_matrix": "expression_matrix", "expression_data": "expression_matrix",
    "sce": "singlecellexperiment", "spe": "spatialexperiment", "se": "summarizedexperiment",
    "eset": "expressionset", "expressionset": "expressionset",
    "bam": "bam", "vcf": "vcf", "fastq": "fastq", "reads": "fastq", "samplesheet": "samplesheet",
    "genome": "fasta", "reference": "fasta", "fasta": "fasta", "peaks": "bed_peaks",
}


def _token_for(inp: dict):
    desc = inp.get("description") or ""
    m = _OBJ_RE.search(desc)
    if m:
        return m.group(1).lower().replace("eset", "expressionset") \
            if m.group(1).lower() == "eset" else m.group(1).lower()
    name = (inp.get("name") or "").strip().lower()
    base = re.sub(r"\.(csv|tsv|rdata|rds|txt|h5ad|h5|gz)$", "", name)
    base = re.sub(r"[^a-z0-9]+", "_", base).strip("_")
    if base in _NAME_MAP:
        return _NAME_MAP[base]
    ty = (inp.get("type") or "").strip().lower()
    if ty and ty not in ("data", "text", "integer", "float", "boolean", "select", "string", "number", "file"):
        return ty
    return None


def derive_input_tokens(params_schema: str):
    d = _jl(params_schema)
    if not isinstance(d, dict):
        return []
    out, seen = [], set()
    for inp in (d.get("data_inputs") or []):
        t = _token_for(inp)
        if t and t not in seen:
            seen.add(t); out.append(t)
    return out


def main() -> int:
    conn = sqlite3.connect(str(_DB))

    # ---- (1) coverage: dirty input_types → clean after derivation ----
    rows = conn.execute(
        "SELECT filename, input_types, params_schema FROM workflows "
        "WHERE input_types IS NOT NULL AND input_types NOT IN ('','[]')").fetchall()
    dirty = recovered = still_dirty = 0
    samples = []
    for fn, it, ps in rows:
        toks = _jl(it)
        if not toks or _clean(toks):
            continue
        dirty += 1
        derived = derive_input_tokens(ps)
        if _clean(derived):
            recovered += 1
            if len(samples) < 6:
                samples.append((fn, toks, derived))
        else:
            still_dirty += 1
    print(f"(1) dirty input_types workflows: {dirty}")
    print(f"    recovered to CLEAN tokens from params_schema: {recovered} ({100*recovered/max(dirty,1):.0f}%)")
    print(f"    still un-derivable (no params_schema / no type signal): {still_dirty}")
    print("    sample before → after:")
    for fn, before, after in samples:
        print(f"      {fn.split('/')[-1][:40]:42} {before} → {after}")

    # ---- (2) composer fire on composer_eval pipelines, DERIVED types in memory ----
    search = UnifiedWorkflowSearch(db_path=_DB)

    def _row(nf):
        return conn.execute(
            "SELECT input_types, output_types, params_schema FROM workflows "
            "WHERE filename=? OR name=? OR filename LIKE ? LIMIT 1",
            (nf, nf, f"%{nf.split('/')[-1]}%")).fetchone()

    def type_provider_current(nf):
        r = _row(nf)
        return (_jl(r[0]), _jl(r[1])) if r else ([], [])

    def type_provider_derived(nf):
        r = _row(nf)
        if not r:
            return ([], [])
        cur_in = _jl(r[0])
        new_in = cur_in if _clean(cur_in) else (derive_input_tokens(r[2]) or cur_in)
        return (new_in, _jl(r[1]))

    def fire_count(tp):
        n = 0
        for p in [json.loads(l) for l in _GOLD.open() if l.strip()]:
            stages = p["stages"]
            picks = {i: pick_workflow_match(search.search(st["desc"]))
                     for i, st in enumerate(stages, 1)}

            def resolver(task, _p=picks, _s=stages):
                for i, st in enumerate(_s, 1):
                    if st["desc"] == (task.get("description") if isinstance(task, dict) else ""):
                        return _p.get(i)
                return None
            tasks = [{"id": "s%d" % i, "description": st["desc"],
                      "depends_on": st.get("depends_on") or [],
                      "parallel_with": st.get("parallel_with")} for i, st in enumerate(stages, 1)]
            if build_dag_plan(tasks, resolver, type_provider=tp) is not None:
                n += 1
        return n

    total = sum(1 for _ in _GOLD.open())
    before = fire_count(type_provider_current)
    after = fire_count(type_provider_derived)
    print(f"\n(2) composer fire on {total} pipelines (in-memory, no DB write):")
    print(f"    current dirty input_types:  {before}/{total}")
    print(f"    DERIVED clean input_types:  {after}/{total}")
    print("\nREAD-ONLY: nothing written. If the lift holds, apply as a backed-up, reversible "
          "update to input_types only (params_schema/description untouched), then re-run composer_eval.py.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
