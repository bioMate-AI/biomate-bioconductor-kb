#!/usr/bin/env nextflow
/*
 * structural_biology/foldseek_structure_search
 *
 * Fast structure-based homology search with Foldseek (van Kempen et al.,
 * Nature Biotechnology 2023; doi:10.1038/s41587-023-01773-0). Foldseek encodes
 * each residue's local geometry into a 20-state 3Di alphabet, reducing structure
 * alignment to fast 3Di+AA sequence alignment — ~10^3-10^5x faster than TM-align
 * or Dali at comparable sensitivity (AlphaFold DB search: ~6 s vs ~33 h / ~10 d).
 *
 * Searches one or more query protein structures (PDB/mmCIF) against a PREBUILT
 * target database — e.g. the AlphaFold DB / Swiss-Prot / PDB Foldseek index,
 * staged read-only from S3 on the Batch worker (see tools/prepare_foldseek_db.sh).
 *
 * Fan-out: one parallel Batch job per query structure (searches are independent),
 * so screening N structures scales horizontally. The target index is a MOUNTED
 * path (params.foldseek_db), never Nextflow-staged — the AFDB index is hundreds
 * of GB and must not be copied per task.
 *
 * QC (optional, downstream): reciprocal TM-align re-rank on the top-N hits.
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir              = './results'
params.query_structures    = null      // comma-separated PDB/mmCIF query file paths (required)
params.foldseek_db         = null      // path to prebuilt Foldseek target DB (mounted; required)
params.foldseek_format     = 'query,target,evalue,bits,alntmscore,prob'
params.foldseek_sensitivity = 9.5      // -s (higher = more sensitive, slower)
params.max_hits            = 50        // top hits to keep per query
// A recent Foldseek biocontainer; on Batch, mirror to ECR as needed.
params.foldseek_container  = 'quay.io/biocontainers/foldseek:9.427df8a--pl5321hb365157_1'

process FOLDSEEK_STRUCTURE_SEARCH {
    tag "$meta.id"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    container params.foldseek_container

    input:
    tuple val(meta), path(query_structure)

    output:
    tuple val(meta), path("${meta.id}_foldseek_hits.m8"),      emit: hits
    tuple val(meta), path("${meta.id}_foldseek_summary.json"), emit: summary
    path "versions.yml",                                       emit: versions

    script:
    """
    mkdir -p fs_tmp
    # Target index is referenced in place (mounted read-only), never staged/copied.
    foldseek easy-search "${query_structure}" "${params.foldseek_db}" \\
        "${meta.id}_foldseek_hits.m8" fs_tmp \\
        -s ${params.foldseek_sensitivity} \\
        --max-seqs ${params.max_hits} \\
        --format-output '${params.foldseek_format}' || true

    python3 << 'PYEOF'
import json, os

fmt = "${params.foldseek_format}".split(",")
def _num(v):
    try:
        return float(v)
    except (ValueError, TypeError):
        return v

hits = []
path = "${meta.id}_foldseek_hits.m8"
if os.path.exists(path):
    with open(path) as f:
        for line in f:
            parts = line.rstrip("\\n").split("\\t")
            if len(parts) < len(fmt):
                continue
            row = {}
            for col, val in zip(fmt, parts):
                row[col] = _num(val) if col in ("evalue", "bits", "alntmscore", "prob") else val
            hits.append(row)

hits.sort(key=lambda h: h.get("evalue", 1e9) if isinstance(h.get("evalue"), (int, float)) else 1e9)
summary = {
    "query": "${meta.id}",
    "n_hits": len(hits),
    "best_hit": hits[0] if hits else None,
    "top_hits": hits[:${params.max_hits}],
    "method": "foldseek_easy_search",
    "sensitivity": ${params.foldseek_sensitivity},
}
with open("${meta.id}_foldseek_summary.json", "w") as f:
    json.dump(summary, f, indent=2, default=str)
print("foldseek_structure_search: %d hits for ${meta.id}" % len(hits))
PYEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        foldseek: \$(foldseek version 2>/dev/null | head -1)
    END_VERSIONS
    """
}

workflow FOLDSEEK_STRUCTURE_SEARCH_WORKFLOW {
    take:
    ch_queries   // channel: [ val(meta), path(structure) ]

    main:
    FOLDSEEK_STRUCTURE_SEARCH(ch_queries)   // one parallel search per query structure

    emit:
    hits     = FOLDSEEK_STRUCTURE_SEARCH.out.hits
    summary  = FOLDSEEK_STRUCTURE_SEARCH.out.summary
    versions = FOLDSEEK_STRUCTURE_SEARCH.out.versions
}

// Entry workflow for standalone execution
workflow {
    if (!params.query_structures) {
        error "Please provide --query_structures (comma-separated PDB/mmCIF file paths)"
    }
    if (!params.foldseek_db) {
        error "Please provide --foldseek_db (path to a prebuilt Foldseek target DB)"
    }

    // Fan-out: one parallel search per query structure.
    def q_paths = (params.query_structures instanceof List) ? params.query_structures
        : params.query_structures.toString().split(',').collect { it.trim() }.findAll { it }
    ch_queries = Channel.fromList(q_paths).map { p -> [ [id: file(p).baseName], file(p) ] }

    FOLDSEEK_STRUCTURE_SEARCH_WORKFLOW(ch_queries)

    FOLDSEEK_STRUCTURE_SEARCH_WORKFLOW.out.summary.view { "Summary: $it" }
}
