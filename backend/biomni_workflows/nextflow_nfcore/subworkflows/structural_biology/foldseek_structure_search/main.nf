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
 * Search-from-SEQUENCE (params.query_type == 'sequence'): instead of a 3D
 * structure, the query may be a protein FASTA. Foldseek then uses ProstT5
 * (Heinzinger et al., "Bilingual language model for protein sequence and
 * structure", NAR Genomics and Bioinformatics 2024, lqae150;
 * https://huggingface.co/Rostlab/ProstT5) to predict the 3Di structural
 * alphabet DIRECTLY from sequence — no folding required — which is ~1000x
 * cheaper than predicting a structure (e.g. AlphaFold/ESMFold) first and then
 * searching. The ProstT5 weights are staged read-only from S3 (mounted, like
 * the foldseek_db; never Nextflow-staged) and passed via --prostt5-model.
 * See tools/prepare_prostt5_model.sh.
 *
 * Fan-out: one parallel Batch job per query (searches are independent), so
 * screening N structures/sequences scales horizontally. The target index is a
 * MOUNTED path (params.foldseek_db), never Nextflow-staged — the AFDB index is
 * hundreds of GB and must not be copied per task.
 *
 * QC (optional, downstream): reciprocal TM-align re-rank on the top-N hits.
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir              = './results'
params.query_structures    = null      // comma-separated query file paths (required):
                                        //   query_type='structure' -> PDB/mmCIF structures
                                        //   query_type='sequence'  -> protein FASTA files
params.query_type          = 'structure' // 'structure' (default, unchanged) | 'sequence' (ProstT5 3Di-from-seq)
params.prostt5_model       = null      // path to ProstT5 weights (mounted read-only; required iff query_type=='sequence')
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
    // Search-from-sequence: ProstT5 predicts the 3Di alphabet from the query
    // FASTA (--prostt5-model). Structure mode leaves the command unchanged.
    def is_seq = (params.query_type == 'sequence')
    def prostt5_arg = is_seq ? "--prostt5-model '${params.prostt5_model}'" : ''
    // A sequence query has NO 3D coordinates (ProstT5 emits only the 3Di
    // alphabet, not a structure), so TM-score-based output columns (alntmscore,
    // prob) can't be computed — foldseek's convertalis aborts with "Cannot find
    // query C-alpha". Drop them from the format in sequence mode. Structure mode
    // keeps the user's format verbatim.
    def eff_format = is_seq
        ? params.foldseek_format.toString().split(',').collect { it.trim() }.findAll { !(it in ['alntmscore', 'prob']) }.join(',')
        : params.foldseek_format
    """
    mkdir -p fs_tmp
    # Target index is referenced in place (mounted read-only), never staged/copied.
    # query_type='${params.query_type}': structure -> 3Di from geometry;
    #                                    sequence  -> 3Di from ProstT5 (predicted from AA).
    foldseek easy-search "${query_structure}" "${params.foldseek_db}" \\
        "${meta.id}_foldseek_hits.m8" fs_tmp \\
        -s ${params.foldseek_sensitivity} \\
        --max-seqs ${params.max_hits} \\
        ${prostt5_arg} \\
        --format-output '${eff_format}' || true

    python3 << 'PYEOF'
import json, os

fmt = "${eff_format}".split(",")
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
    "query_type": "${params.query_type}",
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
    if (!(params.query_type in ['structure', 'sequence'])) {
        error "Invalid --query_type '${params.query_type}' (allowed: 'structure' | 'sequence')"
    }
    if (!params.query_structures) {
        def kind = (params.query_type == 'sequence') ? 'protein FASTA' : 'PDB/mmCIF'
        error "Please provide --query_structures (comma-separated ${kind} file paths)"
    }
    if (!params.foldseek_db) {
        error "Please provide --foldseek_db (path to a prebuilt Foldseek target DB)"
    }
    if (params.query_type == 'sequence' && !params.prostt5_model) {
        error "--query_type=sequence requires --prostt5_model (path to the ProstT5 weights, mounted read-only; see tools/prepare_prostt5_model.sh)"
    }

    // Fan-out: one parallel search per query (structure or sequence).
    def q_paths = (params.query_structures instanceof List) ? params.query_structures
        : params.query_structures.toString().split(',').collect { it.trim() }.findAll { it }
    ch_queries = Channel.fromList(q_paths).map { p -> [ [id: file(p).baseName], file(p) ] }

    FOLDSEEK_STRUCTURE_SEARCH_WORKFLOW(ch_queries)

    FOLDSEEK_STRUCTURE_SEARCH_WORKFLOW.out.summary.view { "Summary: $it" }
}
