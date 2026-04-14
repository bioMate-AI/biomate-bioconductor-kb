#!/usr/bin/env nextflow

/**
 * profam_fitness_prediction
 *
 * Protein variant fitness prediction using ProFAM-1 (251M parameter
 * autoregressive protein family language model). State-of-the-art on
 * ProteinGym benchmark (0.47 substitutions, 0.53 indels). No MSA required.
 *
 * Inputs:
 *   params.input_fasta   -- FASTA with wildtype and/or variant sequences
 *   params.variants_csv  -- CSV with columns: mutant (e.g. 'A42G,K57R'), sequence
 *   params.wildtype      -- wildtype sequence as string (alternative to FASTA)
 *   params.scoring_mode  -- 'marginal' | 'conditional' (default: 'marginal')
 *   params.outdir        -- output directory
 */

nextflow.enable.dsl = 2

params.input_fasta    = ''
params.variants_csv   = ''
params.wildtype       = ''
params.scoring_mode   = 'marginal'
params.outdir         = 'results'
params.publish_dir_mode = 'copy'

ECR = '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/profam:latest'

// ── Predict variant fitness ───────────────────────────────────────────────────

process PROFAM_PREDICT {
    tag "profam"
    label 'process_high'
    publishDir "${params.outdir}/fitness", mode: params.publish_dir_mode

    container ECR

    input:
    path(input_fasta)
    path(variants_csv)

    output:
    path("profam_scores.csv"), emit: scores
    path("profam_logits.npy"), emit: logits, optional: true

    script:
    def input_arg = variants_csv.name != 'NO_FILE'
        ? "--variants ${variants_csv}"
        : "--fasta ${input_fasta}"
    def wt_arg = params.wildtype ? "--wildtype '${params.wildtype}'" : ""
    """
    python /opt/profam/predict.py \\
        ${input_arg} \\
        ${wt_arg} \\
        --scoring-mode ${params.scoring_mode} \\
        --output-scores profam_scores.csv \\
        --output-logits profam_logits.npy
    """
}

// ── Rank and report ───────────────────────────────────────────────────────────

process FITNESS_REPORT {
    tag "report"
    label 'process_low'
    publishDir "${params.outdir}", mode: params.publish_dir_mode

    container ECR

    input:
    path(scores_csv)

    output:
    path("profam_fitness_report.json"), emit: report

    script:
    """
    python3 - <<'EOF'
import json, csv

with open("${scores_csv}") as f:
    variants = list(csv.DictReader(f))

variants_sorted = sorted(variants, key=lambda x: float(x.get('fitness_score', 0)), reverse=True)

report = {
    "tool": "ProFAM-1",
    "benchmark": "ProteinGym (0.47 substitutions, 0.53 indels Spearman rho)",
    "scoring_mode": "${params.scoring_mode}",
    "variants_scored": len(variants),
    "top_10_variants": variants_sorted[:10],
    "bottom_5_variants": variants_sorted[-5:],
}
with open("profam_fitness_report.json", "w") as f:
    json.dump(report, f, indent=2)
print(f"Scored {len(variants)} variants; top fitness: {variants_sorted[0].get('fitness_score','N/A') if variants_sorted else 'N/A'}")
EOF
    """
}

workflow {
    fasta_ch = params.input_fasta
        ? Channel.fromPath(params.input_fasta)
        : Channel.fromPath('NO_FILE').ifEmpty(file('NO_FILE'))

    variants_ch = params.variants_csv
        ? Channel.fromPath(params.variants_csv)
        : Channel.fromPath('NO_FILE').ifEmpty(file('NO_FILE'))

    PROFAM_PREDICT(fasta_ch, variants_ch)
    FITNESS_REPORT(PROFAM_PREDICT.out.scores)
}
