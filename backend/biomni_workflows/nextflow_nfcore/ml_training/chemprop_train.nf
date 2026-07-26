#!/usr/bin/env nextflow
/*
 * BioMate ML Training — molecular model training wrapper.
 *
 * Runs one training job through the standard executor path. The single TRAIN
 * process carries `label 'process_gpu'`, which nextflow_executor.py routes to
 * the GPU AWS Batch queue (see nextflow_executor.py:2388). Memory tiers are
 * injected by the executor per label (design doc §4.1).
 *
 * The heavy lifting lives in the Python CLI (galaxy.ai.ml_training.cli), so
 * this wrapper stays thin: stage the dataset, invoke the CLI, publish outputs.
 *
 * Skeleton note: the concrete Chemprop fit runs inside the training container
 * image (which has chemprop/torch installed); this file is validated for
 * routing/param wiring, not executed in the sandbox.
 */
nextflow.enable.dsl = 2

params.dataset           = null            // s3://…/data.csv | tdc:hERG | fixture:herg
params.smiles_col        = 'smiles'
params.target_col        = 'y'
params.split             = 'scaffold'
params.val_frac          = 0.1
params.test_frac         = 0.1
params.model_name        = 'molecular-model'
params.model_type        = 'chemprop_gnn'
params.task_type         = 'classification'
params.featurizer        = 'rdkit_2d'
params.epochs            = 50
params.batch_size        = 50
params.depth             = 3
params.hidden_size       = 300
params.dropout           = 0.0
params.learning_rate     = 0.001
params.ensemble_size     = 1
params.seed              = 42
params.metric            = 'auc'
params.gate_threshold    = null
params.mlflow_experiment = 'biomate-ml-training'
params.campaign_id       = 'default'
params.outdir            = 'results'

process TRAIN {
    // ludwig_tabular (default) + sklearn_gbr are CPU. Use process_low
    // (2 cpu / 12 GB) — plenty for RDKit descriptors + a small Ludwig/torch-CPU
    // NN, and it SCHEDULES: the Batch CE (biomate-nextflow-ce-v2) tops out at
    // 64 GB instances, so process_high (72 GB) is unschedulable → MISCONFIGURATION.
    // Only chemprop_gnn needs a GPU; when that path lands, route it to process_gpu.
    label 'process_low'
    publishDir "${params.outdir}", mode: 'copy'

    output:
    path 'results/metrics.json', emit: metrics
    path 'results/artifact/**',  emit: artifact, optional: true

    script:
    def gate = params.gate_threshold != null ? "--gate-threshold ${params.gate_threshold}" : ''
    // ml_training is copied to the training image top-level (see
    // backend/docker/ml-training.Dockerfile), so it runs standalone — no galaxy
    // backend / httpx / pydantic-conflict. The container is set per-run by the
    // executor from compute_config.container (executor_payload).
    """
    python -m ml_training.cli \
        --dataset '${params.dataset}' \
        --smiles-col '${params.smiles_col}' \
        --target-col '${params.target_col}' \
        --split '${params.split}' \
        --val-frac ${params.val_frac} \
        --test-frac ${params.test_frac} \
        --model-name '${params.model_name}' \
        --model-type '${params.model_type}' \
        --task-type '${params.task_type}' \
        --featurizer '${params.featurizer}' \
        --epochs ${params.epochs} \
        --batch-size ${params.batch_size} \
        --depth ${params.depth} \
        --hidden-size ${params.hidden_size} \
        --dropout ${params.dropout} \
        --learning-rate ${params.learning_rate} \
        --ensemble-size ${params.ensemble_size} \
        --seed ${params.seed} \
        --metric '${params.metric}' \
        ${gate} \
        --mlflow-experiment '${params.mlflow_experiment}' \
        --campaign-id '${params.campaign_id}' \
        --out results
    """
}

workflow {
    if( !params.dataset )
        error "params.dataset is required (s3://…/data.csv | tdc:hERG | fixture:herg)"
    TRAIN()
}
