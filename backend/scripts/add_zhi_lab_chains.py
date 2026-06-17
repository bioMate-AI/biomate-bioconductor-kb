#!/usr/bin/env python3
"""Insert workflow + workflow_chains rows for Dr. Degui Zhi's lab demos.

Two demos grounded in the lab's recent papers:
  Z01 — TorchGWAS on UDIP brain phenotypes
        (Nat Commun 2026; github.com/ZhiGroup/TorchGWAS MIT,
         github.com/ZhiGroup/UDIP-FA)
  Z02 — Folding-Docking-Affinity (FDA) protein-ligand screen
        (github.com/ZhiGroup/FDA MIT, June 2026)

Both nf-core sub-workflows are 4-phase ABCD pipelines under
backend/nf-core-workflows/modules/biomate-ai-tools/<name>/main.nf.

Idempotent (INSERT … ON CONFLICT DO NOTHING via name UNIQUE).
"""
from __future__ import annotations

import json
import os
import sqlite3
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DB_PATH = os.path.join(ROOT, "backend", "database", "galaxy_ai_tools.db")

WORKFLOWS = [
    {
        "name": "torchgwas_udip_phenotype_scan",
        "domain": "population_genetics",
        "description": "GPU-accelerated GWAS over UDIP-derived brain image phenotypes. "
                       "4-phase pipeline (phenotype QC, kernel + stratify, TorchGWAS scan, "
                       "loci report). Wraps github.com/ZhiGroup/TorchGWAS (MIT).",
    },
    {
        "name": "fda_protein_ligand_affinity",
        "domain": "drug_discovery",
        "description": "Folding-Docking-Affinity (FDA) protein-ligand affinity screen. "
                       "4-phase pipeline (ESMFold target, library docking, FDA affinity "
                       "head, ranked report with uncertainty). Wraps github.com/ZhiGroup/FDA.",
    },
]

CHAINS = [
    {
        "name": "torchgwas_udip_chain",
        "display_name": "TorchGWAS on UDIP brain phenotypes (Z01)",
        "domain": "population_genetics",
        "description": (
            "Run a GPU-accelerated GWAS across UDIP-derived white-matter image "
            "phenotypes. Recovers the HLA/HFE region for FA_007 in <2h on a "
            "single GPU node (Zhi lab Nat Commun 2026)."
        ),
        "wf": "torchgwas_udip_phenotype_scan",
        "queries": [
            "Run TorchGWAS on UDIP brain phenotypes",
            "GWAS across 256 UDIP-derived white-matter image phenotypes",
            "Scan UK Biobank with TorchGWAS for image-genetics loci",
            "image-phenotype GWAS Zhi lab style",
        ],
        "tags": ["gwas", "torchgwas", "udip", "imaging_genetics", "ukb", "gpu",
                 "zhi_lab"],
    },
    {
        "name": "fda_ligand_screen_chain",
        "display_name": "Folding-Docking-Affinity ligand screen (Z02)",
        "domain": "drug_discovery",
        "description": (
            "Score a ligand library against a protein target by folding (ESMFold), "
            "docking, and affinity prediction with the Zhi-lab FDA framework. "
            "Returns top-N with predictive uncertainty."
        ),
        "wf": "fda_protein_ligand_affinity",
        "queries": [
            "Run Folding-Docking-Affinity on a kinase target",
            "Screen 1000 compounds against EGFR T790M",
            "FDA protein-ligand affinity prediction with uncertainty",
            "predict binding affinity for a SMILES library",
        ],
        "tags": ["affinity", "docking", "esmfold", "drug_repurposing",
                 "uncertainty", "zhi_lab"],
    },
]


def _nf_path(wf: str) -> str:
    return f"nf-core-workflows/modules/biomate-ai-tools/{wf}/main.nf"


def _steps_for(wf: str) -> list:
    return [{
        "order": 1,
        "workflow_name": wf,
        "role": "zhi_lab_pipeline",
        "params_template": {},
        "nextflow_path": _nf_path(wf),
    }]


def _ensure_workflow_row(cur: sqlite3.Cursor, w: dict) -> None:
    """Insert into `workflows` so chain composer can resolve workflow_name."""
    cur.execute("PRAGMA table_info(workflows)")
    cols = {c[1] for c in cur.fetchall()}
    if not cols:
        return
    if cur.execute("SELECT 1 FROM workflows WHERE name=?", (w["name"],)).fetchone():
        return
    row = {
        "name": w["name"],
        "filename": _nf_path(w["name"]),
        "domain": w["domain"],
        "description": w["description"],
        "workflow_json": json.dumps({
            "name": w["name"],
            "format-version": "0.1",
            "steps": {},
            "tags": ["zhi_lab"],
            "annotation": w["description"],
        }),
        "format": "nextflow",
        "source": "biomate-ai-tools",
        "category": "biomate-ai-tools",
        "step_count": 4,
        "tags": json.dumps(["zhi_lab", w["domain"]]),
    }
    fields = [f for f in row if f in cols]
    placeholders = ", ".join("?" * len(fields))
    cur.execute(
        f"INSERT INTO workflows ({', '.join(fields)}) VALUES ({placeholders})",
        [row[f] for f in fields],
    )


def main() -> int:
    if not os.path.exists(DB_PATH):
        print(f"DB not found: {DB_PATH}", file=sys.stderr)
        return 1
    inserted = skipped = 0
    with sqlite3.connect(DB_PATH) as conn:
        cur = conn.cursor()

        for w in WORKFLOWS:
            _ensure_workflow_row(cur, w)

        cur.execute("PRAGMA table_info(workflow_chains)")
        cols = {c[1] for c in cur.fetchall()}

        for c in CHAINS:
            existing = cur.execute(
                "SELECT id FROM workflow_chains WHERE name=?", (c["name"],)
            ).fetchone()
            if existing:
                print(f"  skip: {c['name']} (id={existing[0]})")
                skipped += 1
                continue
            row = {
                "name": c["name"],
                "display_name": c["display_name"],
                "domain": c["domain"],
                "description": c["description"],
                "steps": _steps_for(c["wf"]),
                "connections": [],
                "required_inputs": [{"name": "input_json", "type": "json"}],
                "expected_outputs": [{"name": "report_json", "type": "json"},
                                      {"name": "report_md", "type": "markdown"}],
                "example_queries": c["queries"],
                "tags": c["tags"],
            }
            fields = [f for f in row if f in cols]
            placeholders = ", ".join("?" * len(fields))
            values = [json.dumps(row[f]) if not isinstance(row[f], str) else row[f]
                      for f in fields]
            cur.execute(
                f"INSERT INTO workflow_chains ({', '.join(fields)}) VALUES ({placeholders})",
                values,
            )
            print(f"  + inserted {c['name']} → id={cur.lastrowid}")
            inserted += 1
        conn.commit()
    print(f"\ninserted={inserted} skipped={skipped}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
