#!/usr/bin/env python3
"""Consolidate the HAVE-NOW knowledge sources (midtrain_corpus + data_candidates_v2
knowledge subset) into one clean, provenance-labelled, deduplicated knowledge pool
for CPT. CPU/local only — no fetch, no training.

Output: docs/20260912_onprem_llm/knowledge_pool_v1/
  knowledge_pool.jsonl   union, one record per line:
     {id, text, provenance:{pool_source, orig_source, orig_id, license, tier, intended_task}}
  manifest.json          per-source kept/dropped + token estimates + dedup stats

Dedup: exact-text (sha256 of whitespace-collapsed lowercased text).
Supersession rules (documented in manifest):
  - tools_corpus is EXCLUDED: tool_knowledge (12,312) is a richer superset (10,532 ⊂).
  - docs_candidates is pointer-only (no body; overlaps internal_corpus) -> recorded, body excluded.
"""
from __future__ import annotations
import json, hashlib, re
from pathlib import Path

ONPREM = Path(__file__).resolve().parents[2] / "docs" / "20260912_onprem_llm"
MID = ONPREM / "midtrain_corpus"
CAND = ONPREM / "data_candidates_v2"
OUT = ONPREM / "knowledge_pool_v1"
OUT.mkdir(exist_ok=True)

LIC = {
    "chebi": "CC-BY-4.0", "go": "CC-BY-4.0", "hpo": "HPO-open", "so": "open",
    "edam": "CC-BY", "hetionet": "CC0", "gtn": "CC-BY-4.0",
    "internal": "internal", "db_kg": "internal", "wkg": "internal",
    "workflow_order": "internal", "code": "nf-core-MIT/internal",
    "tool_knowledge": "Bioconductor-Artistic/tool-native",
    "composition_rationale": "internal", "biomate_run_output": "internal",
    "git_fix_pair": "internal", "nf_program": "nf-core-MIT/internal",
    "workflow_spec": "internal", "official_nextflow_doc": "nextflow-io(verify-redistribution)",
}
TIER = {  # per scale-up plan
    **{k: "T4-DB-derived" for k in ["db_kg", "wkg", "workflow_order", "tool_knowledge",
       "composition_rationale", "workflow_spec", "code", "nf_program"]},
    **{k: "ontology" for k in ["chebi", "go", "hpo", "so", "edam", "hetionet"]},
    "gtn": "T2c-tutorial", "internal": "internal-prose",
    "biomate_run_output": "T3-findings", "git_fix_pair": "T3-repair",
    "official_nextflow_doc": "T2-method-doc",
}

_ws = re.compile(r"\s+")
def norm(t: str) -> str:
    return _ws.sub(" ", t).strip().lower()

def h(t: str) -> str:
    return hashlib.sha256(norm(t).encode()).hexdigest()

def tok(t: str) -> int:
    return len(t) // 4

seen: set[str] = set()
stats: dict[str, dict] = {}
fout = (OUT / "knowledge_pool.jsonl").open("w")
_n = 0

def emit(pool_source, orig_source, orig_id, text, intended_task):
    global _n
    text = (text or "").strip()
    st = stats.setdefault(pool_source, {"in": 0, "kept": 0, "dropped_dup": 0,
                                        "dropped_empty": 0, "kept_tok": 0})
    st["in"] += 1
    if len(text) < 20:
        st["dropped_empty"] += 1; return
    k = h(text)
    if k in seen:
        st["dropped_dup"] += 1; return
    seen.add(k)
    rec = {"id": f"{pool_source}:{_n}", "text": text,
           "provenance": {"pool_source": pool_source, "orig_source": orig_source,
                          "orig_id": orig_id, "license": LIC.get(pool_source, "unknown"),
                          "tier": TIER.get(pool_source, "unknown"),
                          "intended_task": intended_task}}
    fout.write(json.dumps(rec) + "\n")
    st["kept"] += 1; st["kept_tok"] += tok(text); _n += 1

def jl(path):
    with open(path, errors="replace") as f:
        for line in f:
            line = line.strip()
            if line:
                try: yield json.loads(line)
                except Exception: continue

# ---- midtrain_corpus (exclude tools_corpus [superseded] and midtrain_all [stale]) ----
MID_SRC = ["chebi", "go", "hpo", "so", "edam", "hetionet", "gtn", "internal",
           "db_kg", "wkg", "workflow_order", "code"]
for s in MID_SRC:
    p = MID / f"{s}_corpus.jsonl"
    if not p.exists():
        print("MISSING", p); continue
    for o in jl(p):
        emit(s, o.get("source", s), o.get("id") or o.get("kind"),
             o.get("text", ""), "cpt_knowledge")
    print("done midtrain", s, stats.get(s, {}).get("kept"))

# ---- data_candidates_v2 knowledge subset (verbalized) ----
def v_tool(o):
    parts = [f"Tool: {o.get('name','')}", f"Category: {o.get('category','')}"]
    if o.get("description"): parts.append(o["description"])
    for fld in ("inputs", "outputs", "parameters", "requirements", "examples"):
        v = o.get(fld)
        if v and str(v) not in ("", "{}", "[]", "null", "None"):
            parts.append(f"{fld.capitalize()}: {v}")
    ht = o.get("help_text")
    if ht:
        try:
            d = json.loads(ht) if isinstance(ht, str) else ht
            full = d.get("full_text") or " ".join(
                str(d.get(k, "")) for k in ("what_it_does", "how_to_use",
                "input_description", "output_description", "examples"))
            if full.strip(): parts.append(full.strip())
        except Exception:
            parts.append(str(ht))
    return "\n".join(x for x in parts if x and x.strip())

for o in jl(CAND / "tool_knowledge_candidates.jsonl"):
    emit("tool_knowledge", o.get("tool_id"), o.get("candidate_id"),
         v_tool(o), o.get("intended_task", "tool_knowledge_grounding"))
print("done tool_knowledge", stats["tool_knowledge"]["kept"])

for o in jl(CAND / "composition_rationale_candidates.jsonl"):
    r = o.get("record", {})
    txt = (f"Composition rule [{o.get('source_table','')}]: " +
           "; ".join(f"{k}={v}" for k, v in r.items()))
    emit("composition_rationale", o.get("source_table"), o.get("candidate_id"),
         txt, o.get("intended_task", "tool_composition"))
print("done composition", stats["composition_rationale"]["kept"])

for o in jl(CAND / "biomate_run_output_candidates.jsonl"):
    txt = o.get("produced_output", "") or ""
    if o.get("expected"): txt += f"\n\n[Reference expected]: {o['expected']}"
    emit("biomate_run_output", o.get("result_set"), o.get("candidate_id"),
         txt, o.get("intended_task", "findings"))
print("done run_output", stats["biomate_run_output"]["kept"])

for o in jl(CAND / "git_fix_pair_candidates.jsonl"):
    txt = f"Issue: {o.get('issue_statement','')}\n\nFix diff:\n{o.get('fix_diff_excerpt','')}"
    emit("git_fix_pair", o.get("commit"), o.get("candidate_id"),
         txt, o.get("intended_task", "issue_diagnosis_and_fix"))
print("done git_fix", stats["git_fix_pair"]["kept"])

for o in jl(CAND / "nf_program_candidates.jsonl"):
    parts = []
    if o.get("readme"): parts.append(f"README:\n{o['readme']}")
    if o.get("code"): parts.append(f"Nextflow program:\n{o['code']}")
    if o.get("config"): parts.append(f"Config:\n{o['config']}")
    if o.get("schema"): parts.append(f"Schema:\n{o['schema']}")
    emit("nf_program", o.get("source_path"), o.get("candidate_id"),
         "\n\n".join(parts), o.get("intended_task", "nextflow_generate_understand"))
print("done nf_program", stats["nf_program"]["kept"])

for o in jl(CAND / "workflow_spec_candidates.jsonl"):
    parts = [f"Workflow: {o.get('workflow_name','')} (domain: {o.get('domain','')}, "
             f"lane: {o.get('lane','')}, steps: {o.get('step_count','')})"]
    if o.get("description"): parts.append(o["description"])
    if o.get("annotation"): parts.append(f"Annotation: {o['annotation']}")
    for fld in ("input_types", "output_types", "tools_used"):
        if o.get(fld): parts.append(f"{fld}: {o[fld]}")
    if o.get("real_exec_status"):
        parts.append(f"real_exec_status: {o['real_exec_status']}")
    if o.get("workflow_json_excerpt"): parts.append(o["workflow_json_excerpt"])
    emit("workflow_spec", o.get("workflow_name"), o.get("candidate_id"),
         "\n".join(parts), o.get("intended_task", "retrieval_material"))
print("done workflow_spec", stats["workflow_spec"]["kept"])

for o in jl(CAND / "official_nextflow_doc_candidates.jsonl"):
    emit("official_nextflow_doc", o.get("source"), o.get("candidate_id"),
         o.get("content", ""), o.get("intended_task", "nextflow_language_knowledge"))
print("done official_nf_doc", stats["official_nextflow_doc"]["kept"])

fout.close()

# ---- pointer-only sources (recorded, body excluded) ----
docs_ptr = sum(1 for _ in jl(CAND / "docs_candidates.jsonl"))

tot_kept = sum(s["kept"] for s in stats.values())
tot_tok = sum(s["kept_tok"] for s in stats.values())
tot_in = sum(s["in"] for s in stats.values())
tot_dup = sum(s["dropped_dup"] for s in stats.values())

manifest = {
    "pool": "knowledge_pool_v1",
    "built_from": {"midtrain_corpus": "13 live sources (tools_corpus superseded, "
                   "midtrain_all stale-excluded)", "data_candidates_v2": "8 knowledge sources"},
    "dedup": "exact-text sha256(whitespace-collapsed, lowercased); first-seen wins",
    "supersession": {
        "tools_corpus": "EXCLUDED — tool_knowledge (12,312) is richer superset of tools_corpus (10,532)",
        "docs_candidates": f"POINTER-ONLY, body excluded (overlaps internal_corpus); {docs_ptr} pointers recorded",
        "benchmarks": "all_/public_benchmark EXCLUDED — eval items, not CPT knowledge (held out)",
    },
    "totals": {"records_in": tot_in, "records_kept": tot_kept,
               "records_dropped_dup": tot_dup, "kept_tok_c4": tot_tok,
               "docs_pointers_recorded": docs_ptr},
    "per_source": stats,
    "note": "token est = chars/4 (~1.5x a real tokenizer). HAVE-NOW only; no fetched data.",
}
(OUT / "manifest.json").write_text(json.dumps(manifest, indent=2))
# license-split .gitignore matching repo convention (track manifest, ignore big jsonl)
(OUT / ".gitignore").write_text(
    "# Derived knowledge pool — regenerate with evaluation/local_trial/build_knowledge_pool.py\n"
    "# Manifest tracked; large JSONL not.\n*.jsonl\n")
print("\n=== POOL BUILT ===")
print(f"records kept={tot_kept:,}  dropped_dup={tot_dup:,}  kept_tok(c/4)~{tot_tok:,}")
print(json.dumps({k: {kk: v[kk] for kk in ('in','kept','dropped_dup','kept_tok')}
                  for k, v in stats.items()}, indent=2))
