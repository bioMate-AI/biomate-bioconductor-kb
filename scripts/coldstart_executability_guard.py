#!/usr/bin/env python3
"""Cold-start executability guard  (checkRoutes() equivalent, offline/static).

Purpose
-------
The reference cold-start UI (reference/claude_design/data_centroid_design/
dataui/data-part3.js :: window.checkRoutes) asserts that EVERY advertised
example a first-time user can click actually routes to a real module — so the
promise the front door makes can never drift away from what the system can run.

The BioMate app has the inverse problem. `WELCOME_PROMPTS`
(frontend/client/src/components/chat-interface.tsx) is a 32-prompt cold-start
grid (8 domains x 4 queries). It is currently DISABLED — `ReturningUserWelcome`
returns null — precisely because those prompts were never validated against the
workflows that can actually execute. Some map to a verified, container-backed
subworkflow; some map only to an `biomni_workflows/nfcore/` parameter stub that
fails at runtime; some map to nothing at all.

This guard is the gate that must go green before those seeds are re-enabled.

What "verified/executable" means here
-------------------------------------
`backend/biomni_workflows/nextflow_nfcore/test_results/passed_workflows.txt`
lists the ~236 subworkflows that were actually run to completion in a container.
Each line is `<biomni_test_domain>/<workflow_leaf_name>`. The leaf name is the
directory under `nextflow_nfcore/subworkflows/<subwf_domain>/<leaf>/main.nf`.
NB the domain PREFIX in passed_workflows.txt is the Biomni test taxonomy, which
does not always equal the subworkflow directory (e.g. `docking_autodock_vina`
lives under `subworkflows/drug_discovery/` but is filed as
`pharmacology/docking_autodock_vina` in the passed list). The leaf names are
unique across the passed list, so the leaf name is the reliable key.

A prompt PASSES iff it maps to a workflow whose leaf name is present in
passed_workflows.txt (a real, container-backed, verified-executable workflow).
A prompt FAILS iff its only achievable target is an `nfcore/` parameter stub
(rnaseq / sarek / atacseq / scrnaseq / methylseq / ... — NOT in passed_workflows)
or nothing at all.

The suite exits non-zero if ANY advertised prompt is not backed by a verified
workflow. That is the honest-advertising invariant: do not offer a first-time
user a one-click example we cannot actually run to completion.

Run
---
    python3 scripts/coldstart_executability_guard.py          # table + exit code
    python3 scripts/coldstart_executability_guard.py --json   # machine-readable

Self-contained and offline: reads only two repo files, no network, no Batch,
no Galaxy. Keep it green before re-enabling the seeds in chat-interface.tsx.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
CHAT_INTERFACE = REPO / "frontend/client/src/components/chat-interface.tsx"
PASSED_LIST = (
    REPO
    / "backend/biomni_workflows/nextflow_nfcore/test_results/passed_workflows.txt"
)
SUBWF_ROOT = REPO / "backend/biomni_workflows/nextflow_nfcore/subworkflows"

# ── Intended target of each advertised prompt ────────────────────────────────
# For every WELCOME_PROMPT, its intended workflow target expressed as the LEAF
# name of a subworkflow under nextflow_nfcore/subworkflows/**. The guard then
# checks whether that leaf is present in passed_workflows.txt (verified) — it
# does NOT trust this table's optimism, it verifies it. A value of None means
# the prompt has no verified subworkflow to resolve to: its only achievable
# target is an `nfcore/` parameter stub or nothing, which by definition FAILs.
#
# The mapping is grounded in the actual subworkflow directory listing; each
# non-None target below is a directory that exists on disk. Whether that
# directory was ever RUN to completion (i.e. is in passed_workflows.txt) is the
# question this guard answers.
PROMPT_TARGET: dict[str, str | None] = {
    # ── genomics ──
    # WGS / germline variant calling: subworkflow wgs_germline_gatk /
    # haplotypecaller_simple exist on disk but were never run to completion;
    # the executable path is the nfcore/sarek stub → not verified.
    "Run whole genome sequencing analysis on SRR1518169": "wgs_germline_gatk",
    "Call germline variants with GATK HaplotypeCaller": "haplotypecaller_simple",
    # Generic "RNA-seq differential expression" routes to the nfcore/rnaseq +
    # differentialabundance stubs; no verified subworkflow backs it.
    "Perform RNA-seq differential expression analysis": None,
    # Plain read alignment has no subworkflow at all — pure nfcore stub territory.
    "Align FASTQ reads with BWA-MEM2 against hg38": None,

    # ── drug_discovery ──
    "Run ADMET property prediction for aspirin (CC(=O)Oc1ccccc1C(=O)O)": "predict_admet_properties",
    "Predict binding affinity between imatinib and BCR-ABL kinase": "predict_binding_affinity_protein_1d_sequence",
    "Screen compound library for drug-likeness and toxicity": "predict_admet_properties",
    # PBPK subworkflows (pbpk_simulation, p0_pkpd_semaglutide, simcyp_pbpk) exist
    # on disk but none is in passed_workflows.txt.
    "Run PBPK/PK-PD modeling for semaglutide": "pbpk_simulation",

    # ── cryo_em ── (subworkflows exist; none was run to completion)
    "Process cryo-EM micrographs with standard SPA pipeline": "cryosparc_standard_spa",
    "Run CryoSPARC on EMPIAR-10025 apoferritin dataset": "cryosparc_standard_spa",
    "Perform helical reconstruction for filament data": "helical_refinement",
    "Run RELION multi-body refinement for flexible regions": None,

    # ── transcriptomics ──
    "Run nf-core/rnaseq differential expression analysis": None,   # explicit nfcore stub
    "Perform spatial transcriptomics analysis with Visium data": None,
    "Run single-cell RNA-seq with Seurat clustering": "annotate_celltype_scRNA",
    "Long-read RNA-seq with Oxford Nanopore data": None,

    # ── single_cell ──
    "Run scRNA-seq clustering and cell-type annotation": "annotate_celltype_scRNA",
    "Perform trajectory analysis on my scRNA-seq data": "trajectory_inference",
    "Integrate multi-modal single-cell ATAC + RNA data": None,
    "Identify rare cell populations with high-resolution clustering": "annotate_celltype_scRNA",

    # ── proteomics ── (no proteomics workflow is in passed_workflows.txt)
    "Run label-free quantification on DIA-MS data with DIA-NN": None,
    "Identify phosphorylation sites in my MS/MS spectra": None,
    "Run CyTOF mass cytometry analysis": None,
    "Perform protein-protein interaction network analysis": None,

    # ── structural_biology ──
    # AlphaFold2 as advertised has no verified subworkflow (the one that ran is
    # cryoem_alphafold3_pipeline, a different intent); the af2 subworkflows are stubs.
    "Run AlphaFold2 structure prediction for my protein sequence": None,
    "Perform molecular docking of ligand against EGFR": "docking_autodock_vina",
    "Run GROMACS MD simulation for protein-ligand complex": "gromacs_protein_md",
    "Predict binding affinity with MM-GBSA free energy": None,

    # ── epigenomics ──
    "Run ChIP-seq peak calling with MACS2": "perform_chipseq_peak_calling_with_macs2",
    "Perform ATAC-seq chromatin accessibility analysis": "analyze_atac_seq_differential_accessibility",
    "Run bisulfite sequencing DNA methylation analysis": None,
    "Integrate CUT&RUN with RNA-seq for regulatory analysis": None,
}


def parse_welcome_prompts(text: str) -> list[str]:
    """Extract the 32 WELCOME_PROMPTS strings from chat-interface.tsx.

    Single source of truth: the guard reads the real component so it cannot
    drift from the prompts the UI would show. If the block cannot be found or
    the count changes, that is itself a failure (someone edited the seeds
    without updating the guard).
    """
    m = re.search(r"const WELCOME_PROMPTS[^=]*=\s*\{(.*?)\n\}", text, re.S)
    if not m:
        raise SystemExit(
            "FATAL: could not locate `const WELCOME_PROMPTS = { ... }` in "
            f"{CHAT_INTERFACE}. If the seed block moved, update this guard."
        )
    body = m.group(1)
    # single-quoted JS string literals, honouring backslash escapes
    return [
        s.encode().decode("unicode_escape")
        for s in re.findall(r"'((?:[^'\\]|\\.)*)'", body)
    ]


def load_verified_leaves(path: Path) -> set[str]:
    leaves: set[str] = set()
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        leaves.add(line.split("/")[-1])
    return leaves


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--json", action="store_true", help="emit machine-readable JSON")
    args = ap.parse_args()

    for p in (CHAT_INTERFACE, PASSED_LIST):
        if not p.exists():
            raise SystemExit(f"FATAL: required input missing: {p}")

    prompts = parse_welcome_prompts(CHAT_INTERFACE.read_text())
    verified = load_verified_leaves(PASSED_LIST)

    rows = []
    for prompt in prompts:
        if prompt not in PROMPT_TARGET:
            # A new/edited prompt with no target mapping — treat as a hard fail
            # so the guard is never silently out of date with the seed grid.
            rows.append(
                {
                    "prompt": prompt,
                    "target": None,
                    "status": "FAIL",
                    "reason": "no target mapping in guard (seed edited?)",
                }
            )
            continue
        target = PROMPT_TARGET[prompt]
        if target is None:
            rows.append(
                {
                    "prompt": prompt,
                    "target": None,
                    "status": "FAIL",
                    "reason": "nfcore/ param stub or no workflow — not verified-executable",
                }
            )
        elif target in verified:
            rows.append(
                {
                    "prompt": prompt,
                    "target": target,
                    "status": "PASS",
                    "reason": "backed by container-verified workflow",
                }
            )
        else:
            # subworkflow file exists on disk but was never run to completion
            on_disk = any(True for _ in SUBWF_ROOT.glob(f"*/{target}/main.nf"))
            rows.append(
                {
                    "prompt": prompt,
                    "target": target,
                    "status": "FAIL",
                    "reason": (
                        "subworkflow exists on disk but is NOT in "
                        "passed_workflows.txt (never run to completion)"
                        if on_disk
                        else "target subworkflow not found on disk"
                    ),
                }
            )

    passed = [r for r in rows if r["status"] == "PASS"]
    failed = [r for r in rows if r["status"] == "FAIL"]

    if args.json:
        print(json.dumps({"total": len(rows), "passed": len(passed),
                          "failed": len(failed), "rows": rows}, indent=2))
    else:
        print("Cold-start executability guard  (checkRoutes equivalent)")
        print(f"  source : {CHAT_INTERFACE.relative_to(REPO)} :: WELCOME_PROMPTS")
        print(f"  verify : {PASSED_LIST.relative_to(REPO)} "
              f"({len(verified)} verified workflows)")
        print()
        status_w = 4
        print(f"  {'#':>2}  {'ST':<{status_w}}  {'TARGET':<42}  PROMPT")
        print("  " + "-" * 110)
        for i, r in enumerate(rows, 1):
            tgt = r["target"] or "—"
            print(f"  {i:>2}  {r['status']:<{status_w}}  {tgt:<42}  {r['prompt']}")
        print()
        print(f"  RESULT: {len(passed)}/{len(rows)} PASS, {len(failed)} FAIL")
        if failed:
            print()
            print("  Failing prompts (advertised but NOT backed by a verified workflow):")
            for r in failed:
                print(f"    - {r['prompt']}")
                print(f"        -> {r['reason']}")
            print()
            print("  These seeds MUST NOT be re-enabled in chat-interface.tsx until each")
            print("  resolves to a workflow present in passed_workflows.txt.")

    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
