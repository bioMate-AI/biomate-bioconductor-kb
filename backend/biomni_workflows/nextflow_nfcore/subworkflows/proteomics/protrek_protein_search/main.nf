#!/usr/bin/env nextflow

/**
 * protrek_protein_search
 *
 * Trimodal protein search using ProTrek (Nature Biotechnology 2025).
 * Unifies sequence, structure, and function through contrastive learning.
 * Searches 5B+ proteins by text description, sequence, or structure query.
 *
 * Inputs:
 *   params.query         -- search query: text / FASTA sequence / PDB path
 *   params.query_type    -- 'text' | 'sequence' | 'structure' (default: 'text')
 *   params.top_k         -- number of results to return (default: 50)
 *   params.databases     -- comma-separated databases to search: 'swissprot,pdb,alphafold'
 *   params.input_fasta   -- FASTA for sequence query mode (alternative to params.query)
 *   params.input_pdb     -- PDB for structure query mode
 *   params.outdir        -- output directory
 */

nextflow.enable.dsl = 2

params.query       = ''
params.query_type  = 'text'
params.top_k       = 50
params.databases   = 'swissprot,pdb,alphafold'
params.input_fasta = ''
params.input_pdb   = ''
params.outdir      = 'results'
params.publish_dir_mode = 'copy'

ECR = '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/protrek:latest'

// ── Run ProTrek search ────────────────────────────────────────────────────────

process PROTREK_SEARCH {
    tag "protrek_${params.query_type}"
    label 'process_gpu'
    publishDir "${params.outdir}/search_results", mode: params.publish_dir_mode

    container ECR

    input:
    val(query)
    val(query_type)
    path(optional_fasta)
    path(optional_pdb)

    output:
    path("protrek_results.json"), emit: results
    path("protrek_results.csv"), emit: results_csv

    script:
    def query_arg = query_type == 'sequence' && optional_fasta.name != 'NO_FILE'
        ? "--input ${optional_fasta}"
        : query_type == 'structure' && optional_pdb.name != 'NO_FILE'
            ? "--input ${optional_pdb}"
            : "--query '${query}'"
    """
    python /opt/protrek/demo/search.py \\
        ${query_arg} \\
        --type ${query_type} \\
        --top-k ${params.top_k} \\
        --databases ${params.databases} \\
        --output-json protrek_results.json \\
        --output-csv protrek_results.csv
    """
}

// ── Generate embeddings for input sequences ───────────────────────────────────

process PROTREK_EMBED {
    tag "embed"
    label 'process_gpu'
    publishDir "${params.outdir}/embeddings", mode: params.publish_dir_mode

    when:
    params.input_fasta && params.input_fasta != ''

    container ECR

    input:
    path(fasta)

    output:
    path("embeddings.npy"), emit: embeddings
    path("embedding_metadata.json"), emit: metadata

    script:
    """
    python /opt/protrek/demo/embed.py \\
        --input ${fasta} \\
        --output embeddings.npy \\
        --metadata embedding_metadata.json
    """
}

// ── Summary report ────────────────────────────────────────────────────────────

process SEARCH_REPORT {
    tag "report"
    label 'process_low'
    publishDir "${params.outdir}", mode: params.publish_dir_mode

    container ECR

    input:
    path(results_json)

    output:
    path("protrek_summary.json"), emit: summary

    script:
    """
    python3 - <<'EOF'
import json

with open("${results_json}") as f:
    results = json.load(f)

hits = results.get("hits", [])
summary = {
    "tool": "ProTrek",
    "publication": "Nature Biotechnology 2025",
    "query_type": "${params.query_type}",
    "databases_searched": "${params.databases}".split(","),
    "top_k": ${params.top_k},
    "hits_found": len(hits),
    "top_10_hits": hits[:10],
}
with open("protrek_summary.json", "w") as f:
    json.dump(summary, f, indent=2)
print(f"Found {len(hits)} protein matches")
EOF
    """
}

workflow {
    fasta_ch = params.input_fasta
        ? Channel.fromPath(params.input_fasta)
        : Channel.fromPath('NO_FILE').ifEmpty(file('NO_FILE'))

    pdb_ch = params.input_pdb
        ? Channel.fromPath(params.input_pdb)
        : Channel.fromPath('NO_FILE').ifEmpty(file('NO_FILE'))

    PROTREK_SEARCH(
        Channel.value(params.query),
        Channel.value(params.query_type),
        fasta_ch,
        pdb_ch
    )
    PROTREK_EMBED(fasta_ch)
    SEARCH_REPORT(PROTREK_SEARCH.out.results)
}
