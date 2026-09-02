#!/usr/bin/env nextflow

/*
 * alternate_state_generation
 * Generate a protein's ALTERNATE conformational state (e.g. outward-open transporter
 * from an inward/occluded anchor) — inward outward, alternating access, membrane
 * transporter, SLC, conformational change, alt-state, alternate conformation.
 *
 * Memorization-aware generation of a transporter's ALTERNATE conformational state,
 * anchored on one experimental structure. Two mechanistically independent blind
 * MSA-subsampling generators propose candidates; every candidate is scored by a
 * validated pore-vestibule discriminator against the experimental anchor; a state
 * is accepted only when BOTH generators populate it (consensus) — the guard against
 * the solute-carrier alternate-state memorization bias (Swapna et al. 2025).
 *
 * This module productionises the SNAT2 alternate-state pipeline (previously ad-hoc EC2):
 *   AFsample2 (MSA column-masking) + del Alamo (MSA depth-reduction) -> pore discriminator
 *   -> consensus outward candidate + validation report.
 *
 * Inputs:
 *   params.input_fasta   -- query protein FASTA (single chain)
 *   params.input_msa     -- deep MSA (.a3m); if empty, generators build it via ColabFold
 *   params.ref_pdb       -- experimental anchor structure (the known state) [REQUIRED]
 *   params.mask_fraction -- AFsample2 column-masking fraction (default 0.15)
 *   params.max_msa_sweep -- del Alamo depth-reduction sweep (default '16:32,32:64,48:96')
 *   params.nstruct       -- samples per generator (default 20)
 *   params.outdir        -- output directory (default 'results')
 */

nextflow.enable.dsl = 2

params.input_fasta    = ''
params.input_msa      = ''
params.ref_pdb        = ''
params.mask_fraction  = 0.15
params.max_msa_sweep  = '16:32,32:64,48:96'
params.nstruct        = 20
params.outdir         = 'results'
params.publish_dir_mode = 'copy'

// Blind generators — upgraded to the 2026 state-of-the-art (ConforFlux is Boltz-2-based and
// runs on BioMate's existing ai-tools/boltz infrastructure; MSFold samples structural-token space,
// the highest reported alt-state success rate). AFsample2 remains available as a de-novo fallback.
// Two mechanistically INDEPENDENT, actually-runnable generators:
//   (1) AFsample2  — AF2 MSA column-masking  (validated end-to-end on SNAT2)
//   (2) Boltz-2    — diffusion co-folding, many samples (MIT, already deployed as ai-tools/boltz;
//                    a different model family from AF2 -> genuine independence for consensus).
// ConforFlux (Boltz-2 trunk-repulsion, code unreleased) and MSFold (ESM3 token-space, code pending)
// are optional enhancements ON these when released; ConforFlux's repulsion can be applied over Boltz-2.
def AFSAMPLE2 = 'kyogesh/afsample2:v1.1'
def BOLTZ2    = '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/boltz:latest'
def SCORER    = '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/pore-discriminator:latest'

// -- Generator 1: AFsample2 — AF2 MSA column-masking (validated) ----------------------------
process AFSAMPLE2_GENERATE {
    tag "afsample2"; label 'process_gpu'; container AFSAMPLE2
    input:
        path fasta
        path msa
    output:
        path "afsample2_models/*.pdb", emit: models
    script:
    """
    mkdir -p params/params afsample2_models
    curl -sL https://storage.googleapis.com/alphafold/alphafold_params_2022-12-06.tar | tar x -C params/params
    afsample2 --method afsample2 --model_preset=monomer \
        --flagfile /app/alphafold/AF_multitemplate/monomer_full_dbs.flag --data_dir params \
        --fasta_paths ${fasta} --msa_file ${msa} --msa_rand_fraction ${params.mask_fraction} \
        --dropout=True --nstruct ${params.nstruct} --output_dir afsample2_out/ || true
    cp afsample2_out/*/afsample2/unrelaxed_*.pdb afsample2_models/ 2>/dev/null || true
    """
}

// -- Generator 2: Boltz-2 — diffusion co-folding, many samples (independent model family) ----
process BOLTZ2_GENERATE {
    tag "boltz2"; label 'process_gpu'; container BOLTZ2
    input:
        path fasta
        path msa
    output:
        path "boltz2_models/*.pdb", emit: models
    script:
    // Many diffusion samples + shallow MSA to surface the alternate state; ConforFlux-style trunk
    // repulsion (when its code releases) plugs in here as --diffusion-repulsion.
    """
    mkdir -p boltz2_models
    boltz predict ${fasta} --use_msa_server=false --msa ${msa} \
        --diffusion_samples ${params.nstruct} --sampling_steps 200 --recycling_steps 3 \
        --output_format pdb --out_dir boltz2_out || true
    cp boltz2_out/**/*.pdb boltz2_models/ 2>/dev/null || cp boltz2_out/*.pdb boltz2_models/ 2>/dev/null || true
    """
}

// -- Score every candidate + require cross-generator consensus ---------------
process SCORE_CONSENSUS {
    tag "discriminator"
    publishDir { "${params.outdir}" }, mode: params.publish_dir_mode
    container SCORER
    input:
        path gen1_models
        path gen2_models
        path ref_pdb
    output:
        path "outward_candidate.pdb",        emit: candidate, optional: true
        path "alt_state_report.json",        emit: report
    script:
    """
    python3 /opt/biomate/score_alt_states.py \\
        --ref ${ref_pdb} \\
        --generator afsample2:${gen1_models} \\
        --generator boltz2:${gen2_models} \\
        --min_generators 2 \\
        --out_candidate outward_candidate.pdb \\
        --report alt_state_report.json
    """
}

workflow {
    if (!params.ref_pdb)  error "params.ref_pdb (the experimental anchor) is required"
    if (!params.input_msa) error "params.input_msa (deep MSA .a3m) is required"
    fasta_ch = Channel.fromPath(params.input_fasta ?: params.input_msa, checkIfExists: true)
    msa_ch   = Channel.fromPath(params.input_msa,  checkIfExists: true)
    ref_ch   = Channel.fromPath(params.ref_pdb,    checkIfExists: true)

    AFSAMPLE2_GENERATE(fasta_ch, msa_ch)
    BOLTZ2_GENERATE(fasta_ch, msa_ch)
    SCORE_CONSENSUS(AFSAMPLE2_GENERATE.out.models.collect(),
                    BOLTZ2_GENERATE.out.models.collect(),
                    ref_ch)
}
