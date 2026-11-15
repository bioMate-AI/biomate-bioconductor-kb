#!/usr/bin/env nextflow
/*
 * BioMate ML Training — protein/peptide structure-diffusion training wrapper.
 *
 * Fine-tunes (or trains from scratch) a structure-diffusion model (RFdiffusion /
 * Chroma / Genie) on a set of PDB/mmCIF backbones, then samples designed
 * backbones under the given contig/hotspot conditioning.
 *
 * The single TRAIN process carries `label 'process_gpu'` — nextflow_executor.py
 * routes that to the GPU AWS Batch queue (see nextflow_executor.py:2388). GPU
 * routing is via THIS label, not the payload (executor_payload sets only the
 * awsbatch executor + the diffusion-training container). RFdiffusion's SE(3)
 * transformer + released weights are GPU-only, so unlike chemprop_train.nf's
 * process_low default this wrapper is GPU from the start.
 *
 * The heavy lifting lives in the Python CLI (ml_training.cli), which dispatches
 * model_type=protein_diffusion → diffusion_trainer.py. The container is the
 * separate biomate/diffusion-training image (torch-cuda + rfdiffusion), set per
 * run by the executor from compute_config.container (executor_payload).
 *
 * The TRAIN process runs `python -m ml_training.cli` inside the diffusion-training
 * image (rfdiffusion + Base/Complex ckpts under /opt/RFdiffusion/models). Executor
 * injects compute_config.container; chat Confirm & Run falls back via
 * resolve_ml_training_container(model_type / this .nf path).
 */
nextflow.enable.dsl = 2

params.dataset           = null            // s3://…/structures/ | dir | manifest.txt | fixture:structures
params.model_name        = 'protein-diffusion'
params.model_type        = 'protein_diffusion'
params.task_type         = 'structure_generation'
params.epochs            = 5
params.learning_rate     = 0.0001
params.seed              = 42
params.metric            = 'scrmsd'
params.gate_threshold    = null
params.mlflow_experiment = 'biomate-ml-training'
params.campaign_id       = 'default'
params.outdir            = 'results'
// Structure-diffusion params (model_type = protein_diffusion).
params.framework         = 'rfdiffusion'   // rfdiffusion | chroma | genie
params.base_checkpoint   = 'rfdiffusion/Base_ckpt.pt'
params.finetune          = true            // fine-tune a checkpoint vs. from scratch
params.target_pdb        = ''
params.hotspot_residues  = ''              // e.g. A30,A33,A34
params.motif_pdb         = ''
params.contig            = ''
params.length_min        = 60
params.length_max        = 100
params.num_designs       = 8
params.diffusion_steps   = 50
params.noise_schedule    = 'linear'        // linear | cosine

process TRAIN {
    // RFdiffusion's SE(3) transformer + released weights are GPU-only. Route to
    // the GPU AWS Batch queue via the label (nextflow_executor.py maps
    // process_gpu → the GPU CE/queue). Memory tiers injected by the executor.
    label 'process_gpu'
    publishDir "${params.outdir}", mode: 'copy'

    output:
    path 'results/metrics.json', emit: metrics
    path 'results/artifact/**',  emit: artifact, optional: true

    script:
    def gate = params.gate_threshold != null ? "--gate-threshold ${params.gate_threshold}" : ''
    def ft   = params.finetune ? '--finetune' : '--from-scratch'
    """
    python -m ml_training.cli \
        --dataset '${params.dataset}' \
        --model-name '${params.model_name}' \
        --model-type '${params.model_type}' \
        --task-type '${params.task_type}' \
        --epochs ${params.epochs} \
        --learning-rate ${params.learning_rate} \
        --seed ${params.seed} \
        --metric '${params.metric}' \
        ${gate} \
        --framework '${params.framework}' \
        --base-checkpoint '${params.base_checkpoint}' \
        ${ft} \
        --target-pdb '${params.target_pdb}' \
        --hotspot-residues '${params.hotspot_residues}' \
        --motif-pdb '${params.motif_pdb}' \
        --contig '${params.contig}' \
        --length-min ${params.length_min} \
        --length-max ${params.length_max} \
        --num-designs ${params.num_designs} \
        --diffusion-steps ${params.diffusion_steps} \
        --noise-schedule '${params.noise_schedule}' \
        --mlflow-experiment '${params.mlflow_experiment}' \
        --campaign-id '${params.campaign_id}' \
        --out results
    """
}

workflow {
    if( !params.dataset )
        error "params.dataset is required (s3://…/structures/ | dir | manifest.txt | fixture:structures)"
    TRAIN()
}
