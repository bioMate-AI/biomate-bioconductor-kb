#!/usr/bin/env nextflow

/**
 * scfv_antibody_design
 *
 * AI-driven scFv intrabody design using ProteinMPNN + AlphaFold2.
 * Converts conventional antibodies to functional single-chain Fv intrabodies.
 * Achieves 73% success rate vs 31% with standard methods. (Science Advances 2026)
 *
 * Inputs:
 *   params.antibody_pdb  -- input antibody PDB (heavy + light chain)
 *   params.num_designs   -- number of scFv sequences to design (default: 50)
 *   params.temperature   -- ProteinMPNN sampling temperature (default: 0.1)
 *   params.predict_structure -- run AlphaFold2 on top designs (default: true)
 *   params.top_n_predict -- number of top sequences to predict structure for (default: 5)
 *   params.outdir        -- output directory
 */

nextflow.enable.dsl = 2

params.antibody_pdb      = ''
params.num_designs        = 50
params.temperature        = 0.1
params.predict_structure  = true
params.top_n_predict      = 5
params.outdir             = 'results'
params.publish_dir_mode   = 'copy'

ECR = '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/scfv-pmpnn:latest'

// ── Design scFv sequences ─────────────────────────────────────────────────────

process SCFV_DESIGN {
    tag "scfv_design"
    label 'process_gpu'
    publishDir "${params.outdir}/designs", mode: params.publish_dir_mode

    container ECR

    input:
    path(antibody_pdb)

    output:
    path("designed_sequences.fasta"), emit: sequences
    path("design_scores.csv"), emit: scores

    script:
    """
    python /opt/scfv-pmpnn/run_design.py \\
        --input ${antibody_pdb} \\
        --num-designs ${params.num_designs} \\
        --temperature ${params.temperature} \\
        --output-fasta designed_sequences.fasta \\
        --output-scores design_scores.csv
    """
}

// ── Predict structure of top designs ─────────────────────────────────────────

process STRUCTURE_PREDICTION {
    tag "af2_predict"
    label 'process_gpu'
    publishDir "${params.outdir}/structures", mode: params.publish_dir_mode

    container ECR

    input:
    path(sequences)

    output:
    path("predicted_structures/"), emit: structures_dir
    path("predicted_structures/*.pdb", glob: true), emit: pdbs, optional: true

    script:
    """
    python /opt/scfv-pmpnn/run_predict.py \\
        --input ${sequences} \\
        --top-n ${params.top_n_predict} \\
        --output predicted_structures/
    """
}

// ── Summary report ────────────────────────────────────────────────────────────

process DESIGN_REPORT {
    tag "report"
    label 'process_low'
    publishDir "${params.outdir}", mode: params.publish_dir_mode

    container ECR

    input:
    path(sequences)
    path(scores)

    output:
    path("scfv_design_report.json"), emit: report

    script:
    """
    python3 - <<'EOF'
import json, csv

with open("${scores}") as f:
    designs = list(csv.DictReader(f))

designs_sorted = sorted(designs, key=lambda x: float(x.get('score', 0)), reverse=True)

report = {
    "tool": "scFv-pMPNN + AlphaFold2",
    "publication": "Science Advances 2026",
    "designs_generated": len(designs),
    "top_designs": designs_sorted[:${params.top_n_predict}],
    "success_rate_benchmark": "73% (vs 31% standard)",
}
with open("scfv_design_report.json", "w") as f:
    json.dump(report, f, indent=2)
print(f"Designed {len(designs)} scFv sequences")
EOF
    """
}

workflow {
    antibody_ch = Channel.fromPath(params.antibody_pdb, checkIfExists: true)
    SCFV_DESIGN(antibody_ch)
    STRUCTURE_PREDICTION(SCFV_DESIGN.out.sequences)
    DESIGN_REPORT(SCFV_DESIGN.out.sequences, SCFV_DESIGN.out.scores)
}
