#!/usr/bin/env nextflow
/*
 * drug_discovery/reinvent4_finetune_rl
 *
 * MODELS TRAINED ON YOUR OWN DATA (deck slide 4): generator fine-tuning +
 * reinforcement learning, on REINVENT4 (MolecularAI, Apache-2.0).
 *
 * Unlike reinvent4_lead_design (which SAMPLES a frozen prior — inference only),
 * this workflow TRAINS new checkpoints:
 *
 *   STAGE_TRAIN_SMILES  — materialise the partner/in-house SMILES set.
 *   TRANSFER_LEARNING   — run_type=transfer_learning: fine-tune the base
 *                         REINVENT4 prior on YOUR SMILES -> *_finetuned.model.
 *                         (generator fine-tuning)
 *   STAGED_RL           — run_type=staged_learning, [learning_strategy] type="dap":
 *                         RL-optimise the (fine-tuned) agent against a
 *                         MULTI-OBJECTIVE reward (affinity-proxy x SA x safety x
 *                         QED) with an IdenticalMurckoScaffold [diversity_filter]
 *                         that suppresses reward hacking — "inspectable,
 *                         adjustable reward" -> *_rl.model. (reinforcement learning)
 *
 * All training logic lives in the UNCHANGED, unit-tested trainer reached via
 * PYTHONPATH=/opt/biomate:
 *   backend/lib/galaxy/ai/drug_discovery/reinvent4_trainer.py
 * The bin/run_reinvent4_training.py entrypoint just drives it; no training logic
 * lives in this .nf. Reward components are the SAME objectives the MPO loop uses
 * (mpo_denovo_optimization/bin/run_mpo_round.py).
 *
 * HONESTY: a missing reinvent CLI / prior / training data, or a non-zero
 * REINVENT4 exit, fails the process LOUDLY (non-zero rc) and writes a
 * diagnosable training_summary.json — it NEVER fabricates a checkpoint.
 *
 * Container: reinvent4-nf (carries the reinvent CLI + priors under
 *   $REINVENT4_PRIORS). Built from backend/docker/reinvent4-nf/Dockerfile.
 *   x86-only in practice (torch + reinvent wheels); training runs on AWS Batch.
 *
 * Outputs:
 *   <prefix>_finetuned.model   — transfer-learned checkpoint (if stage transfer|both)
 *   <prefix>_rl.model          — RL-optimised checkpoint    (if stage rl|both)
 *   training_summary.json      — provenance: run types, reward, reason on failure
 *   *_tl.log / *_rl.csv        — REINVENT4's own training-progress logs
 *
 * References:
 *   REINVENT4: Loeffler et al. J. Cheminform. 2024, 16:20 —
 *     https://github.com/MolecularAI/REINVENT4
 *   DAP RL / transfer learning: REINVENT4 configs/toml/{transfer,staged}_learning.toml
 */

nextflow.enable.dsl = 2

// ============================================================================
// Default Parameters
// ============================================================================

params.outdir            = './results/reinvent4_finetune_rl'
params.publish_dir_mode  = 'copy'

// Which stages to run: 'transfer' | 'rl' | 'both'
params.stage             = 'both'

// Partner/in-house training SMILES: inline comma list OR an s3:// / file path
// staged as train_smiles.txt (one SMILES per line). Required for transfer|both.
params.train_smiles      = 'CCO,c1ccccc1,CC(=O)Nc1ccccc1,CC(=O)O,c1ccncc1,CC(=O)N,c1ccc(O)cc1,c1ccc(N)cc1'
params.output_prefix     = 'reinvent4'

// Transfer-learning (generator fine-tuning) hyperparameters
params.epochs            = 10
params.tl_batch_size     = 128
params.tl_learning_rate  = 0.0001

// Staged RL (reinforcement learning) config
//   reward = 'default' -> affinity-proxy x SA x safety(herg) x QED
//   or a comma list kind[:weight], e.g. 'affinity:1.0,sa:0.6,herg_proxy:0.6,qed:0.4'
params.reward            = 'default'
params.rl_steps          = 300
params.rl_batch_size     = 128
params.sigma             = 128.0
params.rl_learning_rate  = 0.0001
params.diversity_filter  = true      // reward-hacking suppression (keep ON)

// Base prior (default: $REINVENT4_PRIORS/reinvent.prior inside the container)
params.prior_path        = ''        // optional: empty -> use container's baked-in default prior

params.gpu               = false

// ============================================================================
// Container — reinvent4-nf (reinvent CLI + priors baked in)
// ============================================================================

// local (ARM dev): biomate/reinvent4-nf:latest (CLI is x86-only; process fails
//   honestly on ARM). aws batch (AMD64 ECR): biomate/reinvent4-nf:x86
def _useAws = System.getenv('NEXTFLOW_USE_AWS') == 'true'
def _ECR_RI = '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/reinvent4-nf:x86'
def _LOCAL_RI = 'biomate/reinvent4-nf:latest'
def REINVENT4_CONTAINER = _useAws ? _ECR_RI : _LOCAL_RI

// ============================================================================
// Processes
// ============================================================================

process STAGE_TRAIN_SMILES {
    /*
     * Materialise the training SMILES set as train_smiles.txt (one per line).
     * Accepts an inline comma list in params.train_smiles.
     */
    tag "stage_train"
    container REINVENT4_CONTAINER
    publishDir "${params.outdir}/input", mode: params.publish_dir_mode

    output:
    path "train_smiles.txt", emit: train

    script:
    def train_escaped = params.train_smiles.replace("'", "\\'")
    """
    python3 - <<'PYEOF'
raw = '''${train_escaped}'''
items = [s.strip() for s in raw.split(',') if s.strip()]
with open('train_smiles.txt', 'w') as fh:
    fh.write("\\n".join(items) + "\\n")
print(f"staged {len(items)} training SMILES")
PYEOF
    """
}

process REINVENT4_TRAIN {
    /*
     * The training round: transfer_learning (fine-tune) and/or staged_learning
     * (RL). Delegates entirely to the reviewed Batch entrypoint; all REINVENT4
     * config + honesty gating is the unchanged reinvent4_trainer.py reached via
     * PYTHONPATH=/opt/biomate.
     */
    tag "reinvent4_train"
    container REINVENT4_CONTAINER
    publishDir "${params.outdir}", mode: params.publish_dir_mode

    input:
    path train_smiles
    path run_training       // bin/run_reinvent4_training.py, staged via projectDir

    output:
    path "training_summary.json",        emit: summary
    path "*_finetuned.model", optional: true, emit: finetuned
    path "*_rl.model",        optional: true, emit: rl_model
    path "*.log",             optional: true, emit: tl_logs
    path "*.csv",             optional: true, emit: rl_logs

    script:
    def use_gpu   = params.gpu ? 'cuda:0' : 'cpu'
    def prior_arg = params.prior_path ? "--prior-path '${params.prior_path}'" : ''
    def div_arg   = params.diversity_filter ? '' : '--no-diversity-filter'
    def needs_train = params.stage in ['transfer', 'both']
    def train_arg = needs_train ? "--train-smiles ${train_smiles}" : ''
    """
    set -euo pipefail
    # ECR :x86 keeps the git tree at /opt/REINVENT4 (not always pip-installed).
    # Prefer that tree + /opt/biomate runner helpers on PYTHONPATH.
    export PYTHONPATH="/opt/REINVENT4:/opt/biomate:\${PYTHONPATH:-}"
    export REINVENT4_DEVICE='${use_gpu}'
    export REINVENT4_PRIORS="\${REINVENT4_PRIORS:-/opt/reinvent4/priors}"

    python3 ${run_training} \\
        --stage '${params.stage}' \\
        ${train_arg} \\
        --output-prefix '${params.output_prefix}' \\
        --epochs ${params.epochs} \\
        --tl-batch-size ${params.tl_batch_size} \\
        --tl-learning-rate ${params.tl_learning_rate} \\
        --reward '${params.reward}' \\
        --rl-steps ${params.rl_steps} \\
        --rl-batch-size ${params.rl_batch_size} \\
        --sigma ${params.sigma} \\
        --rl-learning-rate ${params.rl_learning_rate} \\
        ${div_arg} \\
        ${prior_arg}
    """
}

// ============================================================================
// Workflow
// ============================================================================

workflow {

    if (!(params.stage in ['transfer', 'rl', 'both'])) {
        error "ERROR: --stage must be 'transfer', 'rl' or 'both'"
    }
    if (params.stage in ['transfer', 'both'] && !params.train_smiles) {
        error "ERROR: --train_smiles is required for the transfer (fine-tuning) stage"
    }

    // Ship the reviewed entrypoint from this workflow's bin/ into the task work
    // dir so Batch runs the exact reviewed script (not an image-baked copy).
    ch_entrypoint = Channel.fromPath("${projectDir}/bin/run_reinvent4_training.py")

    STAGE_TRAIN_SMILES()

    REINVENT4_TRAIN(
        STAGE_TRAIN_SMILES.out.train,
        ch_entrypoint
    )

    REINVENT4_TRAIN.out.summary
        .view { summary ->
            def data = new groovy.json.JsonSlurper().parseText(summary.text)
            log.info ""
            log.info "═══════════════════════════════════════════════════"
            log.info "  REINVENT4 Fine-tuning + RL — Training Summary"
            log.info "═══════════════════════════════════════════════════"
            log.info "  Stage:            ${data.stage}"
            log.info "  Status:           ${data.status}"
            if (data.steps?.transfer) {
                log.info "  Transfer (fine-tune): ${data.steps.transfer.reason} " +
                         "-> ${data.steps.transfer.checkpoint}"
            }
            if (data.steps?.rl) {
                log.info "  RL (staged):      ${data.steps.rl.reason} " +
                         "-> ${data.steps.rl.checkpoint}"
                log.info "  Reward:           ${data.steps.rl.reward_components}"
                log.info "  Diversity filter: ${data.steps.rl.diversity_filter}"
            }
            log.info "  Final checkpoint: ${data.final_checkpoint}"
            log.info "═══════════════════════════════════════════════════"
            log.info ""
        }
}
