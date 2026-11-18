#!/usr/bin/env nextflow
/*
 * BioMate ML Training — GPU LLM preference/RL fine-tuning wrapper (DPO / GRPO).
 *
 * The GPU tier for real LLM adaptation. Identical CLI wiring to chemprop_train.nf
 * (dispatch is by --model-type in galaxy.ai.ml_training.cli → trl_trainer.py), but
 * the single TRAIN process carries `label 'process_gpu'` so nextflow_executor.py
 * routes it to the GPU AWS Batch queue (nextflow_executor.py maps process_gpu → the
 * GPU CE/queue) instead of the CPU process_low default.
 *
 * ROUTING IS OPT-IN: routing.nextflow_path_for only returns this wrapper for
 * trl_dpo/trl_grpo when ML_TRAINING_GPU_LLM=1. Do NOT enable that flag until:
 *   1. the CUDA trl-training image is built + pushed (CI: a +cuXXX variant of
 *      backend/docker/trl-training.Dockerfile — mirror diffusion-training.Dockerfile),
 *   2. a GPU Batch queue sized for the target model is provisioned (the existing
 *      biomate-gpu-spot-queue is small; 7B+ needs larger-VRAM instances),
 *   3. the executor selects the CUDA image for trl_dpo/trl_grpo under the flag.
 * See docs/20261118_ML_TRAINING_GPU_TIER.md. Until then DPO/GRPO stay on the verified
 * CPU path (chemprop_train.nf, small models). The container is set per run by the
 * executor from compute_config.container (executor_payload); this file is validated
 * for routing/param wiring, not executed in the sandbox.
 */
nextflow.enable.dsl = 2

params.dataset           = null            // s3://…/pairs.jsonl | hf:… | fixture:preference | fixture:prompts
params.model_name        = 'llm-adapted'
params.model_type        = 'trl_dpo'       // trl_dpo | trl_grpo (set per-run by the executor)
params.task_type         = 'text_generation'
params.epochs            = 3
params.learning_rate     = 0.0001
params.seed              = 42
params.metric            = 'train_loss'
params.gate_threshold    = null
params.mlflow_experiment = 'biomate-ml-training'
params.campaign_id       = 'default'
params.outdir            = 'results'
// LLM fine-tuning / preference-optimization / RL params (see config.LLMSpec).
params.base_model          = 'HuggingFaceTB/SmolLM2-135M-Instruct'
params.instruction_col     = 'instruction'
params.output_col          = 'output'
params.adapter             = 'lora'
params.max_sequence_length = 256
params.beta                = 0.1           // DPO KL strength
params.num_generations     = 4             // GRPO group size
params.reward              = 'length'      // GRPO reward: length | keyword | numeric_answer | composite
params.reward_keyword      = ''

process TRAIN {
    // DPO/GRPO on real models need a GPU. Route to the GPU AWS Batch queue via the
    // label (nextflow_executor.py maps process_gpu → the GPU CE/queue). Memory tiers
    // injected by the executor. Requires the CUDA trl-training image (see header).
    label 'process_gpu'
    publishDir "${params.outdir}", mode: 'copy'

    output:
    path 'results/metrics.json', emit: metrics
    path 'results/artifact/**',  emit: artifact, optional: true

    script:
    def gate = params.gate_threshold != null ? "--gate-threshold ${params.gate_threshold}" : ''
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
        --base-model '${params.base_model}' \
        --instruction-col '${params.instruction_col}' \
        --output-col '${params.output_col}' \
        --adapter '${params.adapter}' \
        --max-sequence-length ${params.max_sequence_length} \
        --beta ${params.beta} \
        --num-generations ${params.num_generations} \
        --reward '${params.reward}' \
        --reward-keyword '${params.reward_keyword}' \
        --mlflow-experiment '${params.mlflow_experiment}' \
        --campaign-id '${params.campaign_id}' \
        --out results
    """
}

workflow {
    if( !params.dataset )
        error "params.dataset is required (preference pairs for DPO, or prompts for GRPO)"
    TRAIN()
}
