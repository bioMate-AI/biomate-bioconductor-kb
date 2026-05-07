#!/usr/bin/env nextflow

/**
 * boltz_structure_prediction
 *
 * Biomolecular structure prediction using Boltz-2 (MIT licensed).
 * Predicts structures of proteins, RNA, DNA, ligands, and protein-ligand complexes
 * with binding affinity estimates. 1000x faster than physics-based FEP.
 *
 * Inputs:
 *   params.input_fasta   -- FASTA file (protein/RNA/DNA sequences)
 *   params.input_yaml    -- Boltz YAML input (overrides fasta; for complexes/ligands)
 *   params.use_msa_server -- use ColabFold MSA server (default: true)
 *   params.sampling_steps -- diffusion sampling steps (default: 200)
 *   params.output_format  -- 'pdb' | 'mmcif' (default: 'mmcif')
 *   params.recycling_steps -- recycling steps (default: 3)
 *   params.outdir        -- output directory (default: 'results')
 */

nextflow.enable.dsl = 2

params.input_fasta     = ''
params.input_yaml      = ''
params.use_msa_server  = true
params.sampling_steps  = 200
params.recycling_steps = 3
params.output_format   = 'mmcif'
params.outdir          = 'results'
params.publish_dir_mode = 'copy'

def ECR = '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/boltz:latest'

// -- Prepare input ------------------------------------------------------------

process PREPARE_INPUT {
    tag "prepare"
    label 'process_low'
    container ECR

    input:
    path(fasta)
    path(yaml_input)

    output:
    path("boltz_input.*"), emit: input_file

    script:
    """
    if [ "${yaml_input}" != "NO_FILE" ] && [ -f "${yaml_input}" ]; then
        cp "${yaml_input}" boltz_input.yaml
    else
        cp "${fasta}" boltz_input.fasta
    fi
    """
}

// -- Run Boltz-2 prediction ----------------------------------------------------

process BOLTZ_PREDICT {
    tag "boltz2"
    label 'process_gpu'
    publishDir "${params.outdir}/structures", mode: params.publish_dir_mode

    container ECR

    input:
    path(input_file)

    output:
    path("boltz_results/"), emit: results_dir
    path("boltz_results/**/*.${params.output_format}", glob: true), emit: structures, optional: true
    path("boltz_results/**/confidence_*.json", glob: true), emit: confidence, optional: true

    script:
    def msa_flag = params.use_msa_server ? '--use-msa-server' : ''
    """
    boltz predict ${input_file} \\
        --out_dir boltz_results/ \\
        --output-format ${params.output_format} \\
        --sampling-steps ${params.sampling_steps} \\
        --recycling-steps ${params.recycling_steps} \\
        ${msa_flag} \\
        --accelerator gpu \\
        --devices 1
    """
}

// -- Summarise results --------------------------------------------------------

process SUMMARISE_RESULTS {
    tag "summary"
    label 'process_low'
    publishDir "${params.outdir}", mode: params.publish_dir_mode

    container ECR

    input:
    path(results_dir)

    output:
    path("boltz_summary.json"), emit: summary

    script:
    """
    python3 - <<'EOF'
import json, glob, os

structures = glob.glob("${results_dir}/**/*.mmcif", recursive=True) + \
             glob.glob("${results_dir}/**/*.pdb", recursive=True)
confidence_files = glob.glob("${results_dir}/**/confidence_*.json", recursive=True)

confidence_data = []
for f in confidence_files:
    with open(f) as fh:
        confidence_data.append({"file": os.path.basename(f), "scores": json.load(fh)})

summary = {
    "tool": "Boltz-2",
    "version": "2.2.1",
    "structures_predicted": len(structures),
    "structure_files": [os.path.basename(s) for s in structures],
    "confidence_scores": confidence_data,
}
with open("boltz_summary.json", "w") as f:
    json.dump(summary, f, indent=2)
print(json.dumps(summary, indent=2))
EOF
    """
}

// -- Workflow ----------------------------------------------------------------

workflow {
    fasta_ch = params.input_fasta
        ? Channel.fromPath(params.input_fasta, checkIfExists: true)
        : Channel.fromPath('NO_FILE', checkIfExists: false).ifEmpty(file('NO_FILE'))

    yaml_ch = params.input_yaml
        ? Channel.fromPath(params.input_yaml, checkIfExists: true)
        : Channel.fromPath('NO_FILE', checkIfExists: false).ifEmpty(file('NO_FILE'))

    PREPARE_INPUT(fasta_ch, yaml_ch)
    BOLTZ_PREDICT(PREPARE_INPUT.out.input_file)
    SUMMARISE_RESULTS(BOLTZ_PREDICT.out.results_dir)
}
