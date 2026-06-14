#!/usr/bin/env python3
"""Add the OSCA → pseudobulk DESeq2 single-cell chain to workflow_chains.

This matches the bioc-sc-routing design tour story (BiocTours.jsx):
    scater QC → scran normalise + HVG → PCA + cluster →
    scoreMarkers ∥ SingleR (parallel) → pseudobulk DESeq2

Adds it alongside the existing scrna_consensus_de_bioc (MAST + Monocle
multi-method DE), which is kept for its niche use case.

Biology rationale: per-cell DE tests (MAST hurdle, Monocle pseudotime)
treat cells as replicates, which is pseudoreplication when the
biological question is condition-vs-condition. The OSCA-book
recommendation is to aggregate to pseudobulk per sample × cell type,
then run DESeq2 on the resulting sample-level table.
"""
import json
import os
import sqlite3
import sys

DB_PATH = os.path.join(
    os.path.dirname(__file__), "..", "database", "galaxy_ai_tools.db"
)

CHAIN = {
    "name": "scrna_pseudobulk_de_bioc",
    "display_name": "scRNA-seq → Pseudobulk DESeq2 (OSCA)",
    "domain": "single_cell",
    "description": (
        "Single-cell condition DE done the statistically correct way. "
        "Follows the OSCA book: scater per-cell QC + scran normalisation "
        "with pooled size factors and HVG selection, PCA + graph-based "
        "clustering, scoreMarkers and SingleR annotation in parallel, "
        "then aggregateAcrossCells to pseudobulk per sample × cell type "
        "for DESeq2 condition DE. Avoids the per-cell pseudoreplication "
        "trap that hurdle / pseudotime methods don't fix."
    ),
    "steps": [
        {"order": 1, "workflow_name": "nf-core/scrnaseq",
         "role": "scrna_processing",
         "params_template": {"aligner": "cellranger"}},
        {"order": 2, "workflow_name": "scater",
         "role": "per_cell_qc",
         "params_template": {"mito_max": 0.12, "min_features": 500}},
        {"order": 3, "workflow_name": "scran",
         "role": "normalisation_and_hvg",
         "params_template": {"hvg_n": 2000}},
        {"order": 4, "workflow_name": "scran",
         "role": "pca_and_cluster",
         "params_template": {"npcs": 30, "k": 10, "cluster_fn": "louvain"}},
        {"order": 5, "workflow_name": "scran",
         "role": "marker_detection",
         "params_template": {"test": "scoreMarkers"}},
        {"order": 6, "workflow_name": "singler",
         "role": "celltype_annotation",
         "params_template": {"reference": "HumanPrimaryCellAtlasData"}},
        {"order": 7, "workflow_name": "deseq2",
         "role": "pseudobulk_de",
         "params_template": {"aggregate": "aggregateAcrossCells",
                              "group_by": "sample + cluster",
                              "design": "~ condition"}},
    ],
    "connections": [
        {"from_step": 1, "from_output": "sce_or_h5ad", "to_step": 2, "to_input": "sce"},
        {"from_step": 2, "from_output": "qc_sce",      "to_step": 3, "to_input": "sce"},
        {"from_step": 3, "from_output": "normalised_sce", "to_step": 4, "to_input": "sce"},
        # PCA+cluster fans out to BOTH marker detection and SingleR annotation
        {"from_step": 4, "from_output": "clustered_sce", "to_step": 5, "to_input": "sce"},
        {"from_step": 4, "from_output": "clustered_sce", "to_step": 6, "to_input": "sce"},
        # Both branches rejoin into pseudobulk DESeq2
        {"from_step": 5, "from_output": "markers",      "to_step": 7, "to_input": "markers"},
        {"from_step": 6, "from_output": "annotated_sce", "to_step": 7, "to_input": "sce"},
    ],
    "required_inputs": [
        {"name": "scrna_fastq", "type": "fastq"},
        {"name": "sample_sheet", "type": "csv",
         "description": "Per-sample condition labels — pseudobulk replicates are samples, not cells."},
        {"name": "reference_transcriptome", "type": "string"},
    ],
    "expected_outputs": [
        {"name": "pseudobulk_de_results", "type": "tsv",
         "description": "DESeq2 results per cluster, treating samples as replicates."},
        {"name": "marker_table", "type": "tsv"},
        {"name": "celltype_annotations", "type": "tsv"},
        {"name": "qc_report", "type": "html"},
    ],
    "example_queries": [
        "scRNA-seq condition DE the right way (pseudobulk)",
        "single-cell DE without pseudoreplication",
        "OSCA scater scran cluster scoreMarkers SingleR pseudobulk DESeq2",
        "differential expression per cell type with proper replicates",
    ],
    "tags": ["scrna", "pseudobulk", "deseq2", "osca", "scater", "scran",
             "singler", "bioconductor", "single_cell"],
}


def main() -> int:
    if not os.path.exists(DB_PATH):
        print(f"DB not found: {DB_PATH}", file=sys.stderr)
        return 1
    with sqlite3.connect(DB_PATH) as conn:
        cur = conn.cursor()
        cur.execute("SELECT id FROM workflow_chains WHERE name=?", (CHAIN["name"],))
        row = cur.fetchone()
        if row:
            print(f"Chain '{CHAIN['name']}' already present (id={row[0]}). No-op.")
            return 0
        cur.execute("PRAGMA table_info(workflow_chains)")
        cols = {c[1] for c in cur.fetchall()}
        # Build the INSERT dynamically against whatever columns exist.
        fields = ["name", "display_name", "domain", "description",
                  "steps", "connections", "required_inputs",
                  "expected_outputs", "example_queries", "tags"]
        fields = [f for f in fields if f in cols]
        values = []
        for f in fields:
            v = CHAIN[f]
            values.append(json.dumps(v) if not isinstance(v, str) else v)
        placeholders = ", ".join("?" * len(fields))
        cur.execute(
            f"INSERT INTO workflow_chains ({', '.join(fields)}) VALUES ({placeholders})",
            values,
        )
        new_id = cur.lastrowid
        conn.commit()
        print(f"Inserted scrna_pseudobulk_de_bioc → id={new_id}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
