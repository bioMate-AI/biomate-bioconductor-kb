#!/usr/bin/env python3
"""Insert workflow_chains rows for the 5 tier-0 drug-design demos.

Each demo's underlying nf-core sub-workflow is a 4-phase pipeline
already on disk under
`backend/nf-core-workflows/modules/biomate-ai-tools/<wf>/main.nf`.

This script wraps each as a single-step "chain" so the chain
runner can route to it from a natural-language query, and so the
After-run report's Citations tab + the (why?) anchor have a
chain_name to key on.

phase_id letters (A/B/C/D) match the `// [Phase X]` annotations in
each .nf file. Verified per-file: bispecific_format_triage,
in_vivo_cart_codesign, in_vivo_base_edit_design, glp1_modality_bakeoff,
modality_triage — all 4-phase pipelines.

Idempotent (INSERT … ON CONFLICT DO NOTHING).

Run AFTER appending the qc_evidence.yaml tier-0 block (this commit).
Then run:
    backend/scripts/populate_rationale_registry.py --apply
to fill rationale_registry rows.
"""
from __future__ import annotations

import json
import os
import sqlite3
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DB_PATH = os.path.join(ROOT, "backend", "database", "galaxy_ai_tools.db")

# (chain_name, display_name, domain, description, workflow_name pointing at the .nf,
#  example_queries, tags). Each chain is a single nf-core sub-workflow with 4
#  internal phases A/B/C/D.
CHAINS = [
    {
        "name": "bispecific_format_triage_chain",
        "display_name": "Bispecific Antibody Format Triage (T01)",
        "domain": "drug_discovery",
        "description": (
            "Triage 5 bispecific antibody formats on 6 biophysical axes for "
            "a given target pair + indication. Phase A mechanism inference, "
            "Phase B format scoring matrix, Phase C composite ranking with "
            "mechanism+indication weighting, Phase D report synthesis. "
            "Recovers the tetravalent cooperative format for PD-1×VEGF / NSCLC "
            "(ivonescimab architecture; HARMONi-2 readout, Dhillon 2024)."
        ),
        "wf": "bispecific_format_triage",
        "queries": [
            "Design a PD-1 by VEGF bispecific for NSCLC",
            "Triage bispecific antibody formats for an immuno-oncology dual target",
            "Which bispecific format wins for PD-1 + VEGF",
            "Ivonescimab-style PD-1×VEGF design",
        ],
        "tags": ["bispecific", "antibody", "PD-1", "VEGF", "oncology", "ivonescimab"],
    },
    {
        "name": "in_vivo_cart_codesign_chain",
        "display_name": "In-vivo CAR-T Co-design (T02)",
        "domain": "drug_discovery",
        "description": (
            "Co-design an in-vivo CAR-T construct (LNP-delivered CAR mRNA) "
            "for a hematologic target. Phase A atlas safety check, Phase B "
            "LNP tropism selection (anti-CD5/CD8/CD3 options), Phase C "
            "fratricide check, Phase D CAR construct assembly. Recovers "
            "CPTX-2309 (anti-CD8 LNP + CD19 CAR mRNA) for CD19 / DLBCL."
        ),
        "wf": "in_vivo_cart_codesign",
        "queries": [
            "Design an in-vivo CAR-T for CD19 in DLBCL",
            "LNP CAR mRNA construct for B-cell lymphoma",
            "CPTX-2309 style in-vivo CAR",
            "anti-CD8 LNP CD19 CAR design",
        ],
        "tags": ["cart", "in_vivo", "lnp", "mrna", "cd19", "oncology", "capstan"],
    },
    {
        "name": "in_vivo_base_edit_design_chain",
        "display_name": "In-vivo Base-Edit Knockout Design (T03)",
        "domain": "drug_discovery",
        "description": (
            "Design an in-vivo base-edit knockout (LNP-delivered guide + editor) "
            "for a target. Phase A atlas tissue check, Phase B editor selection "
            "(CBE vs ABE vs Prime), Phase C guide RNA design, Phase D CMC flag "
            "emission. Recovers ABE at PCSK9 splice donor (VERVE-101/102) "
            "with LFT-risk CMC flag (Lee 2023)."
        ),
        "wf": "in_vivo_base_edit_design",
        "queries": [
            "Knock out PCSK9 with an in-vivo base editor",
            "VERVE-101 style PCSK9 base edit",
            "Design an ABE splice donor edit for hypercholesterolemia",
            "In-vivo base editing for lipid-lowering",
        ],
        "tags": ["base_edit", "in_vivo", "lnp", "pcsk9", "verve", "cardiometabolic"],
    },
    {
        "name": "glp1_modality_bakeoff_chain",
        "display_name": "GLP-1 Modality Bake-off (T04)",
        "domain": "drug_discovery",
        "description": (
            "Score 6 GLP-1 modalities × 6 axes for a metabolic indication. "
            "Phase A receptor atlas profile (GLP1R / GIPR / GCGR tissues), "
            "Phase B modality scoring, Phase C indication weighting "
            "(MASH bonus for GCGR; T2D liability), Phase D top recommendation. "
            "Recovers retatrutide-class triple agonist for MASH (Sanyal 2024)."
        ),
        "wf": "glp1_modality_bakeoff",
        "queries": [
            "Pick the best GLP-1 modality for MASH",
            "GLP-1 bake-off for fatty liver",
            "retatrutide vs tirzepatide vs semaglutide for hepatic steatosis",
            "Triple agonist for MASH design",
        ],
        "tags": ["glp1", "gipr", "gcgr", "mash", "metabolic", "retatrutide", "tirzepatide"],
    },
    {
        "name": "modality_triage_oncology_chain",
        "display_name": "Modality Triage — Oncology Target (T05)",
        "domain": "drug_discovery",
        "description": (
            "Triage CAR-T vs ADC vs bispecific for an oncology target based on "
            "atlas expression + critical-tissue safety. Phase A atlas profile, "
            "Phase B CAR-T viability gate, Phase C ADC + bispecific evaluation, "
            "Phase D modality ranking + IHC follow-up panel. Demo recovers "
            "CAR-T-VIABLE for BCMA (Carvykti precedent, Berdeja 2021)."
        ),
        "wf": "modality_triage",
        "queries": [
            "Should BCMA be CAR-T, ADC, or bispecific",
            "Modality triage for an oncology target",
            "BCMA modality decision for multiple myeloma",
            "Pick the best modality for plasma-cell antigen",
        ],
        "tags": ["modality", "triage", "bcma", "cart", "adc", "bispecific", "oncology"],
    },
]


def _nf_path(wf: str) -> str:
    return f"nf-core-workflows/modules/biomate-ai-tools/{wf}/main.nf"


def _steps_for(wf: str) -> list:
    """Each tier-0 workflow is a single 4-phase nf-core sub-workflow.
    We wrap as a 1-step chain whose internal phases A/B/C/D are picked
    up at runtime via _short_phase_name on the trace."""
    return [{
        "order": 1,
        "workflow_name": wf,
        "role": "tier0_drug_design_pipeline",
        "params_template": {},
        "nextflow_path": _nf_path(wf),
    }]


def main() -> int:
    if not os.path.exists(DB_PATH):
        print(f"DB not found: {DB_PATH}", file=sys.stderr)
        return 1
    inserted = 0
    skipped = 0
    with sqlite3.connect(DB_PATH) as conn:
        cur = conn.cursor()
        cur.execute("PRAGMA table_info(workflow_chains)")
        cols = {c[1] for c in cur.fetchall()}
        for c in CHAINS:
            existing = cur.execute(
                "SELECT id FROM workflow_chains WHERE name=?", (c["name"],)
            ).fetchone()
            if existing:
                print(f"  skip: {c['name']} already present (id={existing[0]})")
                skipped += 1
                continue
            fields = ["name", "display_name", "domain", "description",
                      "steps", "connections", "required_inputs",
                      "expected_outputs", "example_queries", "tags"]
            fields = [f for f in fields if f in cols]
            row: dict = {
                "name": c["name"],
                "display_name": c["display_name"],
                "domain": c["domain"],
                "description": c["description"],
                "steps": _steps_for(c["wf"]),
                "connections": [],
                "required_inputs": [{"name": "input_json", "type": "json",
                                     "description": "Workflow input spec (target, indication, …)"}],
                "expected_outputs": [{"name": "report_json", "type": "json"},
                                      {"name": "report_md", "type": "markdown"}],
                "example_queries": c["queries"],
                "tags": c["tags"],
            }
            placeholders = ", ".join("?" * len(fields))
            values = [json.dumps(row[f]) if not isinstance(row[f], str) else row[f]
                      for f in fields]
            cur.execute(
                f"INSERT INTO workflow_chains ({', '.join(fields)}) VALUES ({placeholders})",
                values,
            )
            new_id = cur.lastrowid
            print(f"  + inserted {c['name']} → id={new_id}")
            inserted += 1
        conn.commit()
    print(f"\ninserted={inserted} skipped={skipped}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
