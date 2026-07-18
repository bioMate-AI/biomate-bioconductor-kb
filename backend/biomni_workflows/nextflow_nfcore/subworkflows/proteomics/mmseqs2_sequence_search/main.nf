#!/usr/bin/env nextflow
/*
 * proteomics/mmseqs2_sequence_search
 *
 * Fast protein/nucleotide sequence homology search with MMseqs2 (Steinegger &
 * Soeding, Nat Biotechnol 2017; MMseqs2-GPU, Nat Methods 2025). ~6x faster than
 * CPU MMseqs2 and up to ~177x vs JackHMMER with GPU (--gpu 1), at PSI-BLAST-
 * beating sensitivity. Searches a query FASTA against a PREBUILT target database
 * (UniRef / nr / Swiss-Prot MMseqs2 DB, staged read-only from S3).
 *
 * SELF-HOSTED, license-clean: MMseqs2 is GPL-3.0 open source and runs directly on
 * our AWS Batch (GPU) workers — no NVIDIA AI Enterprise / NIM production license
 * required (the NVIDIA-hosted msa_search NIM is the convenience dev path only).
 *
 * The target DB is a MOUNTED path (params.mmseqs_db), never Nextflow-staged — a
 * UniRef/nr index is large and must not be copied per task. MMseqs2 is internally
 * batch-parallel over the whole query FASTA, so there is no per-query fan-out.
 * Build/host the target DB once with tools/prepare_mmseqs_db.sh (-> S3).
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir           = './results'
params.query_fasta      = null      // path to query FASTA (protein or nucleotide) (required)
params.mmseqs_db        = null      // path to a prebuilt MMseqs2 target DB or FASTA (mounted; required)
params.sensitivity      = 5.7       // -s (higher = more sensitive, slower; 7.5 for remote homologs)
params.max_hits         = 300       // --max-seqs per query
params.use_gpu          = false     // true => --gpu 1 (MMseqs2-GPU on a GPU Batch node)
params.mmseqs_format    = 'query,target,evalue,bits,pident,alnlen'
// A recent MMseqs2 biocontainer; on GPU Batch mirror the GPU build to ECR.
params.mmseqs_container  = 'quay.io/biocontainers/mmseqs2:16.747c6--pl5321hd6d6fdc_0'

process MMSEQS_SEQUENCE_SEARCH {
    tag "${query_fasta.baseName}"
    label 'process_medium'
    publishDir "${params.outdir}/mmseqs", mode: 'copy'

    container params.mmseqs_container

    input:
    path query_fasta

    output:
    path("mmseqs_hits.m8"),      emit: hits
    path("mmseqs_summary.json"), emit: summary
    path "versions.yml",         emit: versions

    script:
    def gpu_flag = (params.use_gpu?.toString() == 'true') ? '--gpu 1' : ''
    """
    mkdir -p mm_tmp
    mmseqs easy-search "${query_fasta}" "${params.mmseqs_db}" mmseqs_hits.m8 mm_tmp \\
        -s ${params.sensitivity} \\
        --max-seqs ${params.max_hits} \\
        --format-output '${params.mmseqs_format}' \\
        ${gpu_flag} -v 1 || true

    python3 << 'PYEOF'
import json, os
from collections import defaultdict

fmt = "${params.mmseqs_format}".split(",")
num = {"evalue", "bits", "pident", "alnlen"}
per_query = defaultdict(list)
path = "mmseqs_hits.m8"
if os.path.exists(path):
    with open(path) as f:
        for line in f:
            parts = line.rstrip("\\n").split("\\t")
            if len(parts) < len(fmt):
                continue
            row = {}
            for col, val in zip(fmt, parts):
                if col in num:
                    try: val = float(val)
                    except ValueError: pass
                row[col] = val
            per_query[row.get("query")].append(row)

summary = {"queries": [], "n_queries": 0, "total_hits": 0, "method": "mmseqs2_easy_search"}
for q, hits in per_query.items():
    hits.sort(key=lambda h: h.get("evalue", 1e9) if isinstance(h.get("evalue"), float) else 1e9)
    summary["queries"].append({
        "query": q,
        "n_hits": len(hits),
        "best_hit": hits[0] if hits else None,
        "top_hits": hits[:${params.max_hits}],
    })
    summary["total_hits"] += len(hits)
summary["n_queries"] = len(summary["queries"])
with open("mmseqs_summary.json", "w") as f:
    json.dump(summary, f, indent=2, default=str)
print("mmseqs2_sequence_search: %d queries, %d total hits" % (summary["n_queries"], summary["total_hits"]))
PYEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        mmseqs2: \$(mmseqs version 2>/dev/null | head -1)
    END_VERSIONS
    """
}

workflow MMSEQS2_SEQUENCE_SEARCH_WORKFLOW {
    take:
    ch_query   // channel: path(query_fasta)

    main:
    MMSEQS_SEQUENCE_SEARCH(ch_query)

    emit:
    hits     = MMSEQS_SEQUENCE_SEARCH.out.hits
    summary  = MMSEQS_SEQUENCE_SEARCH.out.summary
    versions = MMSEQS_SEQUENCE_SEARCH.out.versions
}

// Entry workflow for standalone execution
workflow {
    if (!params.query_fasta) {
        error "Please provide --query_fasta (path to a query FASTA)"
    }
    if (!params.mmseqs_db) {
        error "Please provide --mmseqs_db (path to a prebuilt MMseqs2 target DB or FASTA)"
    }

    ch_query = Channel.fromPath(params.query_fasta)
    MMSEQS2_SEQUENCE_SEARCH_WORKFLOW(ch_query)
    MMSEQS2_SEQUENCE_SEARCH_WORKFLOW.out.summary.view { "Summary: $it" }
}
