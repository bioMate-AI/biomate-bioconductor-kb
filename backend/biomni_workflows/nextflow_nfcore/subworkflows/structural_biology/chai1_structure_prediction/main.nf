#!/usr/bin/env nextflow

/**
 * chai1_structure_prediction
 *
 * Multi-modal biomolecular structure prediction using Chai-1.
 * Handles proteins, small molecules, DNA, RNA, glycosylations, and multi-chain
 * complexes in a single forward pass. Apache 2.0 licensed.
 *
 * Inputs:
 *   params.input_fasta   -- FASTA file (use FASTA headers to specify chain type:
 *                           >protein|name=A, >ligand|name=LIG|smiles=CCO, >rna|name=R)
 *   params.num_trunk_recycles -- trunk recycling steps (default: 3)
 *   params.num_diffusion_timesteps -- diffusion steps (default: 200)
 *   params.seed          -- random seed for reproducibility (default: 42)
 *   params.outdir        -- output directory
 */

nextflow.enable.dsl = 2

params.input_fasta               = ''
params.num_trunk_recycles        = 3
params.num_diffusion_timesteps   = 200
params.seed                      = 42
params.outdir                    = 'results'
params.publish_dir_mode          = 'copy'

def ECR = '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/chai1:latest'

// -- Chai-1 structure prediction -----------------------------------------------

process CHAI1_PREDICT {
    tag "chai1"
    label 'process_gpu'
    publishDir "${params.outdir}/structures", mode: params.publish_dir_mode

    container ECR

    input:
    path(fasta)

    output:
    path("chai_output/"), emit: results_dir
    path("chai_output/*.cif", glob: true), emit: structures, optional: true
    path("chai_output/scores.json"), emit: scores, optional: true

    script:
    """
    python -m chai_lab.main predict \\
        --fasta ${fasta} \\
        --output chai_output/ \\
        --num-trunk-recycles ${params.num_trunk_recycles} \\
        --num-diffusion-timesteps ${params.num_diffusion_timesteps} \\
        --seed ${params.seed}
    """
}

// -- Summarise -----------------------------------------------------------------

process SUMMARISE_RESULTS {
    tag "summary"
    label 'process_low'
    publishDir "${params.outdir}", mode: params.publish_dir_mode

    container ECR

    input:
    path(results_dir)

    output:
    path("chai1_summary.json"), emit: summary

    script:
    """
    python3 - <<'EOF'
import json, glob, os

structures = glob.glob("${results_dir}/*.cif")
scores = {}
score_file = "${results_dir}/scores.json"
if os.path.exists(score_file):
    with open(score_file) as f:
        scores = json.load(f)

summary = {
    "tool": "Chai-1",
    "structures_predicted": len(structures),
    "structure_files": [os.path.basename(s) for s in structures],
    "scores": scores,
}
with open("chai1_summary.json", "w") as f:
    json.dump(summary, f, indent=2)
print(json.dumps(summary, indent=2))
EOF
    """
}

workflow {
    fasta_ch = Channel.fromPath(params.input_fasta, checkIfExists: true)
    CHAI1_PREDICT(fasta_ch)
    SUMMARISE_RESULTS(CHAI1_PREDICT.out.results_dir)
}
