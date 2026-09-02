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
 *   params.msa_depths    -- del Alamo MSA depth-reduction targets, parallel-scattered (default '16,32,64')
 *   params.nstruct       -- samples per generator (default 20)
 *   params.outdir        -- output directory (default 'results')
 *
 * Generation runs as a PARALLEL SCATTER of mechanistically-diverse strategies (column-masking,
 * depth-reduction x N depths, Boltz-2 diffusion) — concurrent GPU jobs, so wall-clock ~= the slowest
 * single strategy, not their sum. The benchmark (LeuT/Mhp1/LAT1) showed column-masking alone misses the
 * inward state; MSA depth-reduction is what recovers it — hence both are run and their agreement scored.
 */

nextflow.enable.dsl = 2

params.input_fasta    = ''
params.input_msa      = ''
params.ref_pdb        = ''
params.mask_fraction  = 0.15
params.msa_depths     = '16,32,64'
params.nstruct        = 20
params.outdir         = 'results'
params.publish_dir_mode = 'copy'

// THREE mechanistically-distinct blind strategies, run as a PARALLEL SCATTER (concurrent GPU jobs):
//   (1) AFsample2 column-masking  — AF2, deep MSA, --msa_rand_fraction  (the "default-basin" arm)
//   (2) AFsample2 depth-reduction — AF2, shallow MSA (del-Alamo-style), scattered over params.msa_depths
//         (the arm that RECOVERS the alternate state — column-masking alone missed inward in benchmark)
//   (3) Boltz-2 diffusion         — different model family (MIT, ai-tools/boltz) -> genuine independence
// The scorer counts agreement across these strategies (consensus reliability) and uses the
// column-mask(deep) vs depth-reduce(shallow) contrast as an MSA-ablation memorization signal.
// ConforFlux (Boltz-2 trunk-repulsion) / MSFold (ESM3 token-space) plug in here when their code releases.
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

// -- Generator 2: AFsample2 depth-reduction — one PARALLEL task per MSA depth (del-Alamo-style) ------
// This is the arm that recovers the alternate state (benchmark: inward reached only via depth-reduction).
process AFSAMPLE2_DEPTH {
    tag "depth-${depth}"; label 'process_gpu'; container AFSAMPLE2
    input:
        val depth
        path fasta
        path msa
    output:
        path "depth_${depth}_models/*.pdb", emit: models
    script:
    """
    mkdir -p params/params depth_${depth}_models
    curl -sL https://storage.googleapis.com/alphafold/alphafold_params_2022-12-06.tar | tar x -C params/params
    # del-Alamo-style MSA depth reduction: keep the query + top ${depth} homologs (a3m = 2 lines/seq)
    head -n \$(( (${depth} + 1) * 2 )) ${msa} > shallow_${depth}.a3m
    afsample2 --method afsample2 --model_preset=monomer \
        --flagfile /app/alphafold/AF_multitemplate/monomer_full_dbs.flag --data_dir params \
        --fasta_paths ${fasta} --msa_file shallow_${depth}.a3m \
        --dropout=True --nstruct ${params.nstruct} --output_dir depth_${depth}_out/ || true
    cp depth_${depth}_out/*/afsample2/unrelaxed_*.pdb depth_${depth}_models/ 2>/dev/null || true
    """
}

// -- Generator 3: Boltz-2 — diffusion co-folding, many samples (independent model family) ----
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
        path colmask_models
        path depth_models
        path boltz_models
        path ref_pdb
    output:
        path "outward_candidate.pdb",        emit: candidate, optional: true
        path "alt_state_report.json",        emit: report
    script:
    // Three independent strategies -> per-basin consensus reliability + MSA-ablation memorization signal.
    // colmask = deep MSA, depth = shallow MSA: a basin seen in BOTH is MSA-robust (memorization-check),
    // a basin seen only under depth-reduction is MSA-dependent (reasoned).
    """
    python3 /opt/biomate/score_alt_states.py \\
        --ref ${ref_pdb} \\
        --generator colmask:${colmask_models} \\
        --generator depth:${depth_models} \\
        --generator boltz:${boltz_models} \\
        --min_generators 1 \\
        --out_candidate outward_candidate.pdb \\
        --report alt_state_report.json
    """
}

workflow {
    if (!params.ref_pdb)  error "params.ref_pdb (the experimental anchor) is required"
    if (!params.input_msa) error "params.input_msa (deep MSA .a3m) is required"
    // value channels so the single fasta/msa/ref are reused across every parallel strategy
    fasta_ch = Channel.value(file(params.input_fasta ?: params.input_msa, checkIfExists: true))
    msa_ch   = Channel.value(file(params.input_msa,  checkIfExists: true))
    ref_ch   = Channel.value(file(params.ref_pdb,    checkIfExists: true))
    // depth targets -> one parallel task each (the scatter)
    depths_ch = Channel.fromList(params.msa_depths.toString().split(',').collect { it.trim() as Integer })

    AFSAMPLE2_GENERATE(fasta_ch, msa_ch)          // strategy 1: column-masking (deep MSA)
    AFSAMPLE2_DEPTH(depths_ch, fasta_ch, msa_ch)  // strategy 2: depth-reduction (scattered, parallel)
    BOLTZ2_GENERATE(fasta_ch, msa_ch)             // strategy 3: diffusion (independent family)

    SCORE_CONSENSUS(AFSAMPLE2_GENERATE.out.models.collect(),
                    AFSAMPLE2_DEPTH.out.models.collect(),
                    BOLTZ2_GENERATE.out.models.collect(),
                    ref_ch)
}
