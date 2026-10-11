#!/usr/bin/env nextflow

/**
 * chai1_structure_prediction
 *
 * Multi-modal biomolecular structure prediction using Chai-1.
 * Handles proteins, small molecules, DNA, RNA, glycosylations, and multi-chain
 * complexes in a single forward pass. Apache 2.0 licensed.
 *
 * Inputs (provide one):
 *   params.input_fasta   -- path to a FASTA file (use Chai-1 headers for multi-chain:
 *                           >protein|name=A, >ligand|name=LIG|smiles=CCO, >rna|name=R)
 *   params.sequence      -- raw amino-acid sequence string; the workflow writes a
 *                           FASTA file automatically (single-chain protein assumed)
 *
 * Other params:
 *   params.num_trunk_recycles        -- trunk recycling steps (default: 3)
 *   params.num_diffusion_timesteps   -- diffusion steps (default: 200)
 *   params.seed                      -- random seed (default: 42)
 *   params.outdir                    -- output directory
 */

nextflow.enable.dsl = 2

params.input_fasta               = ''
params.sequence                  = ''  // raw AA/NT sequence — alternative to input_fasta
params.num_trunk_recycles        = 3
params.num_diffusion_timesteps   = 200
params.seed                      = 42
params.outdir                    = 'results'
params.publish_dir_mode          = 'copy'

def ECR = '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/chai1:latest'

// -- Chai-1 structure prediction -----------------------------------------------
// Handles both input modes inside the process script so no intermediate channel
// or local temp file is needed (collectFile breaks with S3 work directories).

process CHAI1_PREDICT {
    tag "chai1"
    label 'process_gpu'
    publishDir "${params.outdir}/structures", mode: params.publish_dir_mode

    container ECR

    output:
    path("chai_output/"), emit: results_dir
    path("chai_output/*.cif"), emit: structures, optional: true
    path("chai_output/scores.json"), emit: scores, optional: true

    script:
    def fasta_path = params.input_fasta?.toString()?.trim() ?: ''
    def seq        = params.sequence?.toString()?.trim()    ?: ''
    if (!fasta_path && !seq) error "Provide params.input_fasta (FASTA file path) or params.sequence (raw AA/NT sequence)"
    def fasta_arg  = fasta_path ?: 'input_sequence.fasta'
    def write_cmd  = fasta_path ? '' : "printf '>protein|name=query\\\\n${seq}\\\\n' > input_sequence.fasta"
    """
    ${write_cmd}
    python -m chai_lab.main predict \\
        --fasta ${fasta_arg} \\
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
    CHAI1_PREDICT()
    SUMMARISE_RESULTS(CHAI1_PREDICT.out.results_dir)
}
