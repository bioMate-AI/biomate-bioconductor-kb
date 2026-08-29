#!/usr/bin/env python3
"""
Phase-1 cross-system comparison runner (CPU + DB-search tier).

Encodes the representative task list (docs/20260817_COMPARISON_TASKLIST_...) as
structured data, the R0–R5 evaluation ladder, and a per-task truth-set checker
registry. `--dry-run` (DEFAULT) emits the full execution plan + a cost preview
and spends NOTHING. Actually launching a system is gated behind explicit flags
AND an env confirmation, so this file cannot silently cost money.

Money gate (honours the standing "never waste my money" rule):
  * default is --dry-run: no API calls, no compute, no spend.
  * --execute requires BOTH the flag and REALBIO_PHASE1_CONFIRM=yes in the env.
  * even with --execute, Phase-2 (GPU) tasks are refused unless --allow-gpu.

Usage:
  python3 run_phase1.py                      # dry-run: print plan + cost preview
  python3 run_phase1.py --system claude_code # dry-run the plan for one system
  REALBIO_PHASE1_CONFIRM=yes python3 run_phase1.py --execute --system biomate  # real (gated)
"""
import argparse, json, os, sys

# ------------------------------------------------------------------ the ladder
LADDER = [
    ("R0", "refuses / wrong domain / hallucinated non-answer"),
    ("R1", "correct DESIGN — names the right workflow, tools, params"),
    ("R2", "runnable ARTIFACT — code/spec that is syntactically valid & would run"),
    ("R3", "EXECUTES to completion by any allowed means (install/code/run)"),
    ("R4", "CORRECT RESULT — matches the task truth-set metric"),
    ("R5", "GOVERNED & reproducible — QC-gated, params validated, audit trail"),
]
RUNG_INDEX = {r[0]: i for i, r in enumerate(LADDER)}

SYSTEMS = {
    # ceiling = the highest rung the system class can reach on CPU/DB tasks (no rule cap on GPU;
    # see the task-list doc §3b — ceilings here are the *class* maxima, the run measures actuals)
    "biomate":     dict(kind="curated-exec",   ceiling="R5", methods="curated validated-pipeline execution"),
    "biomni":      dict(kind="agent",          ceiling="R4", methods="agentic execution (in-domain)"),
    "coscientist": dict(kind="agent-chem",     ceiling="R4", methods="chemistry/hypothesis agents (partial)"),
    "claude_code": dict(kind="code-agent",     ceiling="R4", methods="full latitude: install/code/run any tool/DB"),
    "codex":       dict(kind="code-agent",     ceiling="R4", methods="full latitude: install/code/run any tool/DB"),
    "bare_llm":    dict(kind="llm",            ceiling="R1", methods="text only (R4 only on pure-reasoning tasks)"),
}

# ------------------------------------------------------------------ the tasks
# tier: 'cpu' (Phase 1) | 'gpu' (Phase 2, gated). truth = the metric to score R4.
TASKS = [
    dict(id="T01", domain="transcriptomics", tier="cpu", wf="nf-core/rnaseq→differentialabundance→GSEA",
         inp="GSE49712", truth="DESeq2 concordance vs SEQC/ERCC known fold-changes"),
    dict(id="T02", domain="variant_calling", tier="cpu", wf="nf-core/sarek (chr20)",
         inp="GIAB HG002 chr20", truth="hap.py SNV/indel F1 vs GIAB v4.2.1"),
    dict(id="T03", domain="epigenomics", tier="cpu", wf="nf-core/chipseq→CHIPSEEKER→CLUSTERPROFILER",
         inp="ENCODE K562 H3K27ac ENCFF301TVL", truth="Jaccard overlap vs ENCODE consensus ENCFF044JNJ"),
    dict(id="T04", domain="proteomics", tier="cpu", wf="MSNBASE→LIMMA",
         inp="PXD002952 (UPS1)", truth="UPS1 recall @FDR5% / yeast FPR"),
    dict(id="T05", domain="metagenomics", tier="cpu", wf="assembly→binning→MAGs",
         inp="CAMI II low-complexity (5)", truth="AMBER bin-F1 vs CAMI gold"),
    dict(id="T06", domain="metabolomics", tier="cpu", wf="LC-MS consensus DE",
         inp="MTBLS136", truth="consensus DE feature recovery"),
    dict(id="T07", domain="single_cell", tier="cpu", wf="scran→SingleR→pseudobulk DESeq2",
         inp="10x PBMC 10k", truth="cluster markers + pseudoreplication-guarded DE"),
    dict(id="T09", domain="drug_discovery", tier="cpu", wf="ADMET screen + auto-loop",
         inp="3 SMILES (incl aspirin, C16-benzene)", truth="15-endpoint ADMET + hERG/DILI gate + C16→C4 remediation"),
    dict(id="T11", domain="drug_discovery", tier="cpu", wf="AutoDock Vina docking",
         inp="EGFR PDB 1M17 + ligands", truth="Vina score ranking + pose validity"),
    dict(id="T12", domain="pharma_pk", tier="cpu", wf="PBPK oral-dose projection",
         inp="remediated analogue", truth="dose ladder + Cmin vs target trough"),
    dict(id="T13", domain="clinical", tier="cpu", wf="BOIN phase-1 design",
         inp="target-tox 30%, 5 levels", truth="boundary table + correct-MTD % vs sim"),
    dict(id="T14", domain="pharma_chain", tier="cpu", wf="IND §2.6 assembly",
         inp="T09/T12/T13 outputs", truth="§2.6.1/2.6.4 DOCX with source mapping"),
    dict(id="T15", domain="genomics_sc", tier="cpu", wf="GWAS→scRNA→eQTL target chain",
         inp="GCST90093061 + GSE227835 + GTEx", truth="CTSH in top candidates (PP4≈0.85)"),
    dict(id="T16", domain="multi_omics", tier="cpu", wf="MOFA2 vs SNF",
         inp="Dietrich 2018 CLL", truth="MOFA2 IGHV AUC vs SNF ARI + over-correction 2×2"),
    dict(id="T17", domain="structural_search", tier="cpu", wf="foldseek structure search",
         inp="SCOPe40 query set", truth="sensitivity-to-1st-FP vs SCOPe superfamily", unverified=True),
    dict(id="T18", domain="seq_search", tier="cpu", wf="mmseqs2/diamond homology",
         inp="Pfam seed vs UniRef50", truth="homolog recall/precision vs Pfam", unverified=True),
    # ---- Phase 2 (GPU, gated) ----
    dict(id="T08", domain="cryo_em", tier="gpu", wf="cryosparc_standard_spa",
         inp="EMPIAR-10025", truth="GSFSC resolution vs published"),
    dict(id="T10", domain="structural", tier="gpu", wf="Boltz-2 structure prediction",
         inp="EGFR seq → PDB 1M17", truth="RMSD-to-1M17"),
    dict(id="T19", domain="md", tier="gpu", wf="GROMACS MD", inp="chignolin 5AWL",
         truth="native RMSD < 2Å (Honda 2008)", unverified=True),
    dict(id="T20", domain="complex", tier="gpu", wf="AF-Multimer/Boltz multimer",
         inp="EGF–EGFR 1IVO", truth="DockQ / interface-RMSD vs 1IVO", unverified=True),
]

# rough per-CPU-task LLM/agent token budget (from the derived cost estimate; input-dominated).
# BioMate/agent items make several calls; bare-prompt items are cheap. This is a PREVIEW only.
PHASE1_COST_PREVIEW_USD = {  # order-of-magnitude, per full CPU tier, per system
    "bare_llm":    "< $1  (design-only, no execution)",
    "claude_code": "$? compute + agent tokens (install/run) — measured by the run",
    "codex":       "$? compute + agent tokens — measured by the run",
    "biomni":      "$? agentic (multi-call) — measured by the run",
    "biomate":     "$? AWS Batch CPU-hrs + agent tokens — measured by billing router",
    "coscientist": "$? chemistry-only partial — measured by the run",
}


def ladder_ceiling_for(task, sysname):
    """The highest rung this system *could* reach on this task (class ceiling, tier-aware)."""
    s = SYSTEMS[sysname]
    ceil = s["ceiling"]
    # GPU tasks: code agents/LLMs realistically lower (reliability/infra), not a rule cap
    if task["tier"] == "gpu" and s["kind"] in ("code-agent", "llm"):
        ceil = "R2" if s["kind"] == "code-agent" else "R1"
    # bare LLM reaches R4 only on pure-reasoning tasks (BOIN design)
    if s["kind"] == "llm" and task["id"] == "T13":
        ceil = "R4"
    # co-scientists only attempt chemistry tasks
    if s["kind"] == "agent-chem" and task["domain"] not in ("drug_discovery", "structural"):
        ceil = "R0"
    return ceil


def dry_run(systems, include_gpu):
    # lazy imports so run_phase1 works standalone AND the harness is coherent when the
    # adapter/scorer modules are present (adapters.py imports from this module).
    try:
        from adapters import ADAPTERS
    except Exception:
        try:
            from evaluation.comparison.adapters import ADAPTERS
        except Exception:
            ADAPTERS = {}
    try:
        from scorers import REGISTRY as SCORERS
    except Exception:
        try:
            from evaluation.comparison.scorers import REGISTRY as SCORERS
        except Exception:
            SCORERS = {}

    tasks = [t for t in TASKS if include_gpu or t["tier"] == "cpu"]
    print(f"# Phase-1 dry-run — {len(tasks)} tasks × {len(systems)} systems  (NO SPEND)")
    print(f"# adapters wired: {sorted(ADAPTERS)} · scorers wired: {sorted(SCORERS)}\n")
    print("Ladder:")
    for r, d in LADDER: print(f"  {r}: {d}")
    print()
    for t in tasks:
        flag = "  [UNVERIFIED — smoke-test first]" if t.get("unverified") else ""
        gpu = "  [GPU · Phase-2 gated]" if t["tier"] == "gpu" else ""
        scorer = "  [scorer ✓]" if t["id"] in SCORERS else "  [scorer: none — R4 not auto-scored]"
        print(f"## {t['id']} {t['domain']} — {t['wf']}{gpu}{flag}{scorer}")
        print(f"   input: {t['inp']}")
        print(f"   truth (scores R4): {t['truth']}")
        for s in systems:
            line = f"     - {s:<12} ceiling {ladder_ceiling_for(t, s)}"
            if s in ADAPTERS:
                try:
                    inv = ADAPTERS[s]().plan(t)["invocation"].replace("\n", " ")
                    line += f"  →  {inv[:88]}…"
                except Exception:
                    line += f"  ({SYSTEMS[s]['methods']})"
            else:
                line += f"  ({SYSTEMS[s]['methods']})"
            print(line)
        print()
    print("## Cost preview (per full CPU tier, per system) — order of magnitude only:")
    for s in systems:
        print(f"   {s:<12} {PHASE1_COST_PREVIEW_USD.get(s, '?')}")
    print("\nNothing was executed. To run for real: --execute + REALBIO_PHASE1_CONFIRM=yes (Phase-2 also needs --allow-gpu).")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--system", action="append", choices=list(SYSTEMS),
                    help="restrict to one or more systems (default: all)")
    ap.add_argument("--execute", action="store_true", help="actually run (GATED — needs env confirm)")
    ap.add_argument("--allow-gpu", action="store_true", help="include Phase-2 GPU tasks")
    args = ap.parse_args()
    systems = args.system or list(SYSTEMS)

    if not args.execute:
        dry_run(systems, include_gpu=args.allow_gpu)
        return
    # --- money gate ---
    if os.environ.get("REALBIO_PHASE1_CONFIRM") != "yes":
        sys.exit("REFUSED: --execute requires REALBIO_PHASE1_CONFIRM=yes in the env "
                 "(this run would spend money). Re-run without --execute for a free dry-run.")
    sys.exit("Executors not wired in this scaffold: per-system adapters (biomate/biomni/claude_code/…) "
             "and truth-set scorers are the next implementation step. Refusing to pretend a run happened.")


if __name__ == "__main__":
    main()
