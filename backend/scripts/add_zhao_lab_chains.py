#!/usr/bin/env python3
"""Insert workflow + workflow_chains for Dr. Zhongming Zhao's lab demos.

ZZ01 — tumor_reactive_t_cell_chain (3-step multi-tool):
       turep → scupa_polarization → immuneapp_hla_screen
ZZ02 — scgwas_immunology_chain (1-step):
       scgwas_immune_cell

Idempotent. Insert into both `workflows` and `workflow_chains`.
"""
from __future__ import annotations
import json, os, sqlite3, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DB_PATH = os.path.join(ROOT, "backend", "database", "galaxy_ai_tools.db")

WORKFLOWS = [
    {"name":"turep","domain":"immuno_oncology",
     "description":"Cross-cancer tumor-reactive CD8+ T-cell prediction from scRNA-seq + spatial. Wraps github.com/bsml320/turep (MIT)."},
    {"name":"scupa_polarization","domain":"immuno_oncology",
     "description":"Immune cell polarization scoring + subtype annotation. Wraps github.com/bsml320/Scupa (license clarification pending)."},
    {"name":"immuneapp_hla_screen","domain":"immuno_oncology",
     "description":"HLA-I epitope binding prediction for neoantigen screening. Wraps github.com/bsml320/ImmuneApp (MIT)."},
    {"name":"scgwas_immune_cell","domain":"population_genetics",
     "description":"Single-cell-resolved GWAS enrichment for immune cell types. Wraps github.com/bsml320/scGWAS (GPL-3.0)."},
]

CHAINS = [
    {
        "name":"tumor_reactive_t_cell_chain",
        "display_name":"Tumor-reactive T-cell pipeline (ZZ01)",
        "domain":"immuno_oncology",
        "description":("3-step Zhao-lab immuno-oncology chain: detect tumor-reactive CD8+ T cells (turep) → "
                       "annotate polarization state (Scupa) → predict HLA-I epitope binding for top neoantigens (ImmuneApp). "
                       "Showcases multi-tool chain composition with a single chat prompt."),
        "wfs":["turep","scupa_polarization","immuneapp_hla_screen"],
        "roles":["zhao_lab_turep","zhao_lab_polarization","zhao_lab_neoantigen"],
        "queries":[
            "Find tumor-reactive T cells in this scRNA-seq + predict neoantigens",
            "Run the Zhao-lab turep + Scupa + ImmuneApp pipeline",
            "tumor reactive T cell prediction with HLA-I neoantigen ranking",
        ],
        "tags":["scrna","tumor_reactive","immuno_oncology","neoantigen","hla","zhao_lab","multi_step"],
    },
    {
        "name":"scgwas_immunology_chain",
        "display_name":"Single-cell GWAS for immune cell types (ZZ02)",
        "domain":"population_genetics",
        "description":("Run scGWAS to enrich GWAS summary statistics against single-cell transcriptomic profiles, "
                       "returning trait × cell-type significance. Pairs with TorchGWAS (Z01) for a complete bulk + single-cell GWAS surface."),
        "wfs":["scgwas_immune_cell"],
        "roles":["zhao_lab_scgwas"],
        "queries":[
            "Run scGWAS on these summary stats + this scRNA-seq atlas",
            "single-cell GWAS enrichment for autoimmune traits",
            "which cell types are enriched for Crohn's disease GWAS hits",
        ],
        "tags":["gwas","scrna","scgwas","cell_type_enrichment","zhao_lab"],
    },
]


def _nf_path(wf): return f"nf-core-workflows/modules/biomate-ai-tools/{wf}/main.nf"


def _ensure_workflow_row(cur, w):
    cur.execute("PRAGMA table_info(workflows)")
    cols = {c[1] for c in cur.fetchall()}
    if cur.execute("SELECT 1 FROM workflows WHERE name=?", (w["name"],)).fetchone():
        return
    row = {
        "name": w["name"], "filename": _nf_path(w["name"]),
        "domain": w["domain"], "description": w["description"],
        "workflow_json": json.dumps({"name": w["name"], "format-version": "0.1",
                                     "steps": {}, "tags": ["zhao_lab"], "annotation": w["description"]}),
        "format": "nextflow", "source": "biomate-ai-tools",
        "category": "biomate-ai-tools", "step_count": 3,
        "tags": json.dumps(["zhao_lab", w["domain"]]),
    }
    fields = [f for f in row if f in cols]
    cur.execute(f"INSERT INTO workflows ({','.join(fields)}) VALUES ({','.join('?'*len(fields))})",
                [row[f] for f in fields])


def main():
    inserted = skipped = 0
    with sqlite3.connect(DB_PATH) as conn:
        cur = conn.cursor()
        for w in WORKFLOWS: _ensure_workflow_row(cur, w)
        cur.execute("PRAGMA table_info(workflow_chains)")
        cols = {c[1] for c in cur.fetchall()}
        for c in CHAINS:
            if cur.execute("SELECT id FROM workflow_chains WHERE name=?", (c["name"],)).fetchone():
                print(f"  skip: {c['name']}"); skipped += 1; continue
            steps = [{"order": i+1, "workflow_name": w, "role": r,
                      "params_template": {}, "nextflow_path": _nf_path(w)}
                     for i, (w, r) in enumerate(zip(c["wfs"], c["roles"]))]
            row = {
                "name": c["name"], "display_name": c["display_name"],
                "domain": c["domain"], "description": c["description"],
                "steps": steps, "connections": [],
                "required_inputs": [{"name":"input_json","type":"json"}],
                "expected_outputs":[{"name":"report_json","type":"json"},{"name":"report_md","type":"markdown"}],
                "example_queries": c["queries"], "tags": c["tags"],
            }
            fields = [f for f in row if f in cols]
            values = [json.dumps(row[f]) if not isinstance(row[f], str) else row[f] for f in fields]
            cur.execute(f"INSERT INTO workflow_chains ({','.join(fields)}) VALUES ({','.join('?'*len(fields))})", values)
            print(f"  + inserted {c['name']} → id={cur.lastrowid}")
            inserted += 1
        conn.commit()
    print(f"\ninserted={inserted} skipped={skipped}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
