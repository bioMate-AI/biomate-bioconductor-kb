#!/usr/bin/env nextflow
/*
 * BioMate ML Training — single-cell expression structure-diffusion wrapper.
 *
 * Fine-tune a pretrained scDiffusion/CFGen checkpoint OR train the diffusion
 * backbone from scratch on an h5ad AnnData, then sample new (optionally
 * cell-type / perturbation-conditioned) cells for augmentation / in-silico
 * perturbation.
 *
 * The single TRAIN process carries `label 'process_gpu'`, which
 * nextflow_executor.py routes to the GPU AWS Batch queue (see
 * nextflow_executor.py:2388) — diffusion training/sampling needs CUDA.
 *
 * The heavy lifting lives in the Python CLI
 * (galaxy.ai.ml_training.cli, model-type=scrna_diffusion → scrna_diffusion_trainer),
 * so this wrapper stays thin: stage the h5ad, invoke the CLI, publish outputs.
 * The container is set per-run by the executor from compute_config.container
 * (executor_payload._resolve_container → SC_DIFFUSION_TRAINING_IMAGE).
 *
 * Skeleton note: the concrete scDiffusion/CFGen fit + sampling runs inside the
 * sc-diffusion-training image (torch-cuda + scDiffusion/CFGen + scanpy/anndata
 * + staged weights); this file is validated for routing/param wiring, not
 * executed in the sandbox.
 */
nextflow.enable.dsl = 2

params.dataset             = null            // s3://…/cells.h5ad | /local/cells.h5ad | fixture:pbmc_h5ad
params.model_name          = 'scrna-diffusion'
params.model_type          = 'scrna_diffusion'
params.task_type           = 'expression_generation'
params.epochs              = 50
params.batch_size          = 128
params.learning_rate       = 0.0001
params.seed                = 42
params.metric              = 'marker_fidelity_frac'
params.gate_threshold      = null
params.mlflow_experiment   = 'biomate-ml-training'
params.campaign_id         = 'default'
params.outdir              = 'results'
// Single-cell diffusion knobs (SCDiffusionSpec).
params.sc_framework          = 'scdiffusion'   // scdiffusion | cfgen
params.sc_base_checkpoint    = ''              // pretrained diffusion backbone (fine-tune warm-start)
params.sc_base_model         = ''              // pretrained autoencoder/foundation weight (e.g. SCimilarity)
params.sc_finetune           = true            // fine-tune vs. train-from-scratch
params.sc_cell_type          = ''              // condition on cell type
params.sc_condition_label    = ''              // obs column for perturbation/condition
params.sc_n_cells_to_generate = 1000
params.sc_n_genes            = 0               // 0 = infer from h5ad
params.sc_guidance_scale     = 1.0
params.sc_diffusion_steps    = 1000
params.sc_noise_schedule     = 'cosine'        // cosine | linear | sqrt

process TRAIN {
    // Diffusion training + sampling needs CUDA → GPU queue. The executor injects
    // the GPU memory/instance tier for this label (design doc §4.1) and sets the
    // container to the sc-diffusion-training image.
    label 'process_gpu'
    publishDir "${params.outdir}", mode: 'copy'

    output:
    path 'results/metrics.json',            emit: metrics
    path 'results/artifact/**',             emit: artifact, optional: true

    script:
    def gate = params.gate_threshold != null ? "--gate-threshold ${params.gate_threshold}" : ''
    def ft   = params.sc_finetune ? '--sc-finetune' : '--no-sc-finetune'
    """
    python -m ml_training.cli \\
        --dataset '${params.dataset}' \\
        --model-name '${params.model_name}' \\
        --model-type '${params.model_type}' \\
        --task-type '${params.task_type}' \\
        --epochs ${params.epochs} \\
        --batch-size ${params.batch_size} \\
        --learning-rate ${params.learning_rate} \\
        --seed ${params.seed} \\
        --metric '${params.metric}' \\
        ${gate} \\
        --sc-framework '${params.sc_framework}' \\
        --sc-base-checkpoint '${params.sc_base_checkpoint}' \\
        --sc-base-model '${params.sc_base_model}' \\
        ${ft} \\
        --sc-cell-type '${params.sc_cell_type}' \\
        --sc-condition-label '${params.sc_condition_label}' \\
        --sc-n-cells-to-generate ${params.sc_n_cells_to_generate} \\
        --sc-n-genes ${params.sc_n_genes} \\
        --sc-guidance-scale ${params.sc_guidance_scale} \\
        --sc-diffusion-steps ${params.sc_diffusion_steps} \\
        --sc-noise-schedule '${params.sc_noise_schedule}' \\
        --mlflow-experiment '${params.mlflow_experiment}' \\
        --campaign-id '${params.campaign_id}' \\
        --out results
    """
}

workflow {
    if( !params.dataset )
        error "params.dataset is required (s3://…/cells.h5ad | /local/cells.h5ad | fixture:pbmc_h5ad)"
    TRAIN()
}
