#!/usr/bin/env nextflow

/**
 * state_perturbation_prediction
 *
 * Virtual cell perturbation prediction using STATE (Arc Institute).
 * Predicts cellular transcriptional responses to genetic or chemical
 * perturbations without running experiments. Trained on 270M+ cells
 * including the Tahoe-100M dataset.
 *
 * Inputs:
 *   params.input_h5ad    -- AnnData h5ad file with cell expression profiles
 *   params.perturbation  -- perturbation to simulate: gene name or compound SMILES
 *   params.perturbation_type -- 'genetic' | 'chemical' (default: 'genetic')
 *   params.cell_type     -- cell type to use (default: infer from h5ad obs)
 *   params.n_predictions -- number of cells to predict (default: 1000)
 *   params.mode          -- 'transition' (predict response) | 'embedding' (encode states)
 *   params.outdir        -- output directory
 */

nextflow.enable.dsl = 2

params.input_h5ad         = ''
params.perturbation        = ''
params.perturbation_type   = 'genetic'
params.cell_type           = ''
params.n_predictions       = 1000
params.mode                = 'transition'
params.outdir              = 'results'
params.publish_dir_mode    = 'copy'

ECR = '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/state:latest'

// ── Run STATE transition model ────────────────────────────────────────────────

process STATE_TRANSITION {
    tag "state_tx"
    label 'process_gpu'
    publishDir "${params.outdir}/predictions", mode: params.publish_dir_mode

    when:
    params.mode == 'transition'

    container ECR

    input:
    path(h5ad)

    output:
    path("state_predictions.h5ad"), emit: predicted_h5ad
    path("state_transition_scores.csv"), emit: scores

    script:
    def cell_type_flag = params.cell_type ? "--cell-type '${params.cell_type}'" : ""
    """
    state tx infer \\
        --input ${h5ad} \\
        --perturbation '${params.perturbation}' \\
        --perturbation-type ${params.perturbation_type} \\
        --n-predictions ${params.n_predictions} \\
        --output state_predictions.h5ad \\
        --scores state_transition_scores.csv \\
        ${cell_type_flag}
    """
}

// ── Run STATE embedding model ─────────────────────────────────────────────────

process STATE_EMBEDDING {
    tag "state_emb"
    label 'process_gpu'
    publishDir "${params.outdir}/embeddings", mode: params.publish_dir_mode

    when:
    params.mode == 'embedding'

    container ECR

    input:
    path(h5ad)

    output:
    path("state_embeddings.h5ad"), emit: embedded_h5ad
    path("embeddings.npy"), emit: embeddings

    script:
    """
    state emb transform \\
        --input ${h5ad} \\
        --output state_embeddings.h5ad \\
        --embeddings-out embeddings.npy
    """
}

// ── Analyse perturbation response ─────────────────────────────────────────────

process PERTURBATION_ANALYSIS {
    tag "analysis"
    label 'process_medium'
    publishDir "${params.outdir}", mode: params.publish_dir_mode

    container ECR

    input:
    path(predicted_h5ad)
    path(scores_csv)

    output:
    path("state_analysis_report.json"), emit: report
    path("top_degs.csv"), emit: degs

    script:
    """
    python3 - <<'EOF'
import json, csv, os

scores = []
if os.path.exists("${scores_csv}"):
    with open("${scores_csv}") as f:
        scores = list(csv.DictReader(f))

top_responding = sorted(scores, key=lambda x: abs(float(x.get('effect_size', 0))), reverse=True)[:50]

import csv as _csv
with open("top_degs.csv", "w", newline="") as f:
    if top_responding:
        writer = _csv.DictWriter(f, fieldnames=top_responding[0].keys())
        writer.writeheader()
        writer.writerows(top_responding)

report = {
    "tool": "STATE (Arc Institute)",
    "training_data": "270M+ cells including Tahoe-100M",
    "perturbation": "${params.perturbation}",
    "perturbation_type": "${params.perturbation_type}",
    "cell_type": "${params.cell_type}" or "inferred",
    "cells_predicted": ${params.n_predictions},
    "genes_scored": len(scores),
    "top_responding_genes": top_responding[:10],
}
with open("state_analysis_report.json", "w") as f:
    json.dump(report, f, indent=2)
print(f"Predicted response for {${params.n_predictions}} cells; {len(scores)} genes scored")
EOF
    """
}

workflow {
    h5ad_ch = Channel.fromPath(params.input_h5ad, checkIfExists: true)

    STATE_TRANSITION(h5ad_ch)
    STATE_EMBEDDING(h5ad_ch)

    if (params.mode == 'transition') {
        PERTURBATION_ANALYSIS(
            STATE_TRANSITION.out.predicted_h5ad,
            STATE_TRANSITION.out.scores
        )
    }
}
