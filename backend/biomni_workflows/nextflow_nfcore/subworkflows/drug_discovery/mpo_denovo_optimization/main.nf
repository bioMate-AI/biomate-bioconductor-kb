#!/usr/bin/env nextflow
/*
 * drug_discovery/mpo_denovo_optimization
 *
 * Runs the CLOSED multi-objective (MPO / GP-Pareto) de-novo loop on AWS Batch:
 *
 *     generate  (generators.Generator.propose)          -> candidate SMILES
 *       -> predict   (real RDKit objective predictors)   -> per-objective scores
 *       -> score+select (bayesian_optimizer GP + EHVI)   -> next batch
 *       -> rank                                          -> ranked Pareto shortlist
 *
 * This is the Batch wrapper that was MISSING. The GP surrogate / expected-
 * hypervolume-improvement acquisition / Tanimoto diversity all come from the
 * UNCHANGED, unit-tested optimizer:
 *   backend/lib/galaxy/ai/drug_discovery/bayesian_optimizer.py
 *   backend/lib/galaxy/ai/drug_discovery/denovo_pipeline.py
 *   backend/lib/galaxy/ai/drug_discovery/generators.py
 * baked into the drug-discovery image at /opt/biomate/drug_discovery
 * (PYTHONPATH=/opt/biomate). The MPO_ROUND process just invokes the entrypoint
 * bin/run_mpo_round.py — no optimisation logic lives in this .nf.
 *
 * Generator is a SWAP-POINT (params.generator):
 *   brics           — RDKit BRICS enumeration (deterministic; always in-container)
 *   bionemo_genmol  — learned NVIDIA BioNeMo GenMol NIM (needs NVIDIA_API_KEY)
 *   bionemo_molmim  — learned NVIDIA BioNeMo MolMIM NIM (needs NVIDIA_API_KEY)
 * With no reachable NIM the learned generators return ZERO molecules and the
 * step exits 3 (honesty contract) rather than fabricating a run.
 *
 * Objectives are REAL RDKit-computable models (params.objectives), NOT stubs.
 * A learned ADMET / docking predictor (other fixes) drops into the same
 * --objectives registry in bin/run_mpo_round.py as one more callable.
 *
 * Outputs:
 *   mpo_ranked.csv    — ranked multi-objective candidate set (rank, smiles,
 *                       mean_score, <objective columns>, acquisition)
 *   mpo_pareto.csv    — training-set Pareto front the proposal advanced
 *   mpo_summary.json  — provenance + hypervolume-improvement evidence
 */

nextflow.enable.dsl = 2

// ============================================================================
// Parameters
// ============================================================================

params.outdir            = './results/mpo_denovo_optimization'
params.publish_dir_mode  = 'copy'

// Generation
params.seed_smiles       = 'c1ccc2c(c1)ccc(=O)o2'   // coumarin scaffold (default)
params.generator         = 'brics'                  // brics | bionemo_genmol | bionemo_molmim
params.n_generate        = 200                       // virtual library size to score

// Training seed set the GP is fit on. Either an inline comma list OR an s3://
// path to a file with one SMILES per line, staged as `train_smiles.txt`.
params.train_smiles      = 'CCO,CCN,CCC,c1ccccc1,c1ccncc1,CC(=O)O,CC(=O)N,CCOC,CCCO,CCCN'

// Multi-objective spec: comma list of name[:direction]; >=2 required.
// Available: qed, sa, logp, mw, herg_proxy (see bin/run_mpo_round.py).
params.objectives        = 'qed:maximize,sa:minimize'

// BO / selection
params.n_propose         = 10
params.n_initial         = 8
params.diversity_weight  = 0.2
params.campaign_id       = 'mpo_denovo_campaign'

// ============================================================================
// Container — same image family as reinvent4_lead_design (baked-in package)
// ============================================================================

// local (ARM dev): biomate/biomni-drug-discovery-nf:latest
// aws batch (AMD64 ECR): 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-drug-discovery-nf:x86
def _useAws = System.getenv('NEXTFLOW_USE_AWS') == 'true'
def MPO_CONTAINER = _useAws
    ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-drug-discovery-nf:x86'
    : 'biomate/biomni-drug-discovery-nf:latest'

// ============================================================================
// Processes
// ============================================================================

process STAGE_TRAIN_SMILES {
    /*
     * Materialise the training seed set as train_smiles.txt (one SMILES/line).
     * Accepts an inline comma list in params.train_smiles.
     */
    tag "stage_train"
    container MPO_CONTAINER
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

process MPO_ROUND {
    /*
     * The closed generate -> predict -> GP/EHVI select -> rank round.
     * Delegates entirely to the Batch entrypoint; the GP + hypervolume logic is
     * the unchanged bayesian_optimizer.py reached via PYTHONPATH=/opt/biomate.
     */
    tag "mpo_round"
    container MPO_CONTAINER
    publishDir "${params.outdir}", mode: params.publish_dir_mode

    input:
    path train_smiles
    path run_mpo_round   // bin/run_mpo_round.py, staged via projectDir

    output:
    path "mpo_ranked.csv",   emit: ranked
    path "mpo_pareto.csv",   emit: pareto
    path "mpo_summary.json", emit: summary

    script:
    def seed_escaped = params.seed_smiles.replace("'", "'\\''")
    """
    export PYTHONPATH="/opt/biomate:\${PYTHONPATH:-}"
    python3 ${run_mpo_round} \\
        --campaign-id '${params.campaign_id}' \\
        --generator '${params.generator}' \\
        --seed-smiles '${seed_escaped}' \\
        --train-smiles ${train_smiles} \\
        --objectives '${params.objectives}' \\
        --n-generate ${params.n_generate} \\
        --n-propose ${params.n_propose} \\
        --n-initial ${params.n_initial} \\
        --diversity-weight ${params.diversity_weight} \\
        --db-path mpo_campaign.db
    """
}

// ============================================================================
// Workflow
// ============================================================================

workflow {

    if (!params.seed_smiles) {
        error "ERROR: --seed_smiles is required (SMILES of the seed/scaffold molecule)"
    }

    // Ship the entrypoint from this workflow's bin/ into the task work dir so the
    // Batch task runs the exact reviewed script (not an image-baked copy).
    ch_entrypoint = Channel.fromPath("${projectDir}/bin/run_mpo_round.py")

    STAGE_TRAIN_SMILES()

    MPO_ROUND(
        STAGE_TRAIN_SMILES.out.train,
        ch_entrypoint
    )

    MPO_ROUND.out.summary
        .view { summary ->
            def data = new groovy.json.JsonSlurper().parseText(summary.text)
            log.info ""
            log.info "═══════════════════════════════════════════════════"
            log.info "  MPO / GP-Pareto De-Novo Round — Results Summary"
            log.info "═══════════════════════════════════════════════════"
            log.info "  Generator:      ${data.generator} (learned=${data.generator_is_learned})"
            log.info "  Objectives:     ${data.objectives}"
            log.info "  Generated:      ${data.n_generated}  ->  proposed ${data.n_scored}"
            log.info "  Pareto front:   ${data.n_pareto_front} compounds"
            log.info "  Diversity:      ${data.diversity_score}"
            if (data.top_candidate) {
                log.info "  Top candidate:  ${data.top_candidate.smiles}"
                log.info "    mean_score=${data.top_candidate.mean_score}  rank=${data.top_candidate.rank}"
            }
            log.info "═══════════════════════════════════════════════════"
            log.info ""
        }
}
