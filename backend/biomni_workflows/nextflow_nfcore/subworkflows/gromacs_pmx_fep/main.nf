#!/usr/bin/env nextflow
/*
 * drug_discovery/gromacs_pmx_fep  (EXECUTABLE promotion of the display-only stub
 * backend/biomni_workflows/nfcore/gromacs_pmx_fep/).
 *
 * REAL relative binding free energy (ΔΔG / FEP) for a RESIDUE-mutation / peptide /
 * cyclic-peptide edge, via GROMACS + pmx. This is the engine BioMate routes to for
 * "relative binding free energy for a single-residue change in a peptide binder"
 * (coldstart design-predict-filter-pep-3) — openfe_rbfe handles two-LIGAND RBFE;
 * this handles the residue/peptide alchemical ΔΔG openfe cannot.
 *
 * Placement note: this lives at nextflow_nfcore/subworkflows/gromacs_pmx_fep/ (flat,
 * no domain subdir) ON PURPOSE — the executor's _resolve_nextflow_path strips the
 * DB logical path "nfcore/gromacs_pmx_fep/main.nf" to "gromacs_pmx_fep/main.nf" and
 * searches the subworkflows base BEFORE the display-only stub tree. So this file wins
 * over the stub with the EXISTING catalog row — no DB repoint / BIOMATE_SYNC_DB=1
 * needed (the TODO's drug_discovery/ subdir would have required the DB change).
 *
 * The 7-step gate-enforced chain (define_edge → knowledge_liability_gate → fto_gate →
 * prepare → equilibrate → fep_production → analyze) is driven by the reviewed
 * entrypoint bin/run_gromacs_pmx_fep.py via --run-all. All physics + the honesty
 * contract live in that script, NOT in this .nf — so what runs on Batch is exactly
 * the reviewed engine. The engine threads its own state in one --outdir, so this is a
 * single process (no fragile cross-process staging); splitting CPU prep from the GPU
 * steps onto separate queues is a documented future cost optimisation (see the stub
 * nextflow.config withName routing it already carries).
 *
 * HONESTY CONTRACT — enforced in bin/run_gromacs_pmx_fep.py, not here: a real FEP edge
 * needs a GPU and hours of sampling. Without the tools/GPU the engine records
 * status 'requires_tools'/'requires_gpu' and writes ddg_kcal_per_mol=null; it NEVER
 * fabricates a ΔΔG. params.mode selects setup | smoke | production, and the spend
 * gates (equilibrate, fep_production) only run when cleared — a production launch on
 * the GPU queue IS the user's confirmed go.
 *
 * References:
 *   pmx:     Gapsys et al. J. Chem. Theory Comput. 2015, 11:2373
 *   GROMACS: Abraham et al. SoftwareX 2015, 1-2:19
 *   BAR:     Bennett J. Comput. Phys. 1976, 22:245
 */

nextflow.enable.dsl = 2

// ============================================================================
// Parameters (mirror the stub nextflow.config contract; every param is consumed
// by the script block below, as the promotion TODO requires).
// ============================================================================

params.outdir            = './results/gromacs_pmx_fep'
params.publish_dir_mode  = 'copy'

// Inputs. Default receptor = the bundled BCL-xL/BAK BH3 structure (1BXL) that the
// engine's built-in validation edge uses, so a request that omits a receptor still
// launches (addresses the pep-3 receptor-staging gap for the control edge).
params.receptor          = "${projectDir}/assets/1BXL.pdb"
// Default edge = the shipped control (BAK BH3 WT vs G1A against BCL-xL/1BXL), matching
// nextflow_schema.json, so a validation run executes a real, structurally-valid edge
// out of the box. A real user FEP request overrides edge_kind/edge_spec with its own.
params.edge_kind         = 'peptide_pair'       // residue_mutation | peptide_pair
params.edge_spec         = 'GQVGRQLAIIGDDINR|AQVGRQLAIIGDDINR'   // BAK BH3 WT | G1A
params.modality          = 'peptide'            // peptide | cyclic_peptide
params.metal_model       = 'none'               // none | cada:<ion>
params.legs              = 'complex,solvent'
params.force_field       = 'charmm36m-mut'

// Alchemical protocol
params.dt_fs             = 2.0
params.equil_ns          = 0.7
params.restraints        = 'backbone'           // none | backbone | heavy
params.lambda_windows    = 12
params.production_ns     = 5.0
params.protocol_repeats  = 3
params.temperature       = 298.15
params.control_edge_expected = ''               // kcal/mol; validates against a known edge

// Execution mode (honesty contract lives in bin/run_gromacs_pmx_fep.py)
//   setup       — define_edge + liability/FTO gates + prepare; HALTS before GPU (no ΔΔG)
//   smoke       — tiny λ/ns GPU probe to confirm launch/resolution (still honest ΔΔG|null)
//   production  — full GPU FEP → BAR ΔΔG ± SEM
params.mode              = 'setup'

// ============================================================================
// Container — ECR (AWS Batch AMD64 GPU) vs local dev. The gpu_batch profile in
// nextflow.config routes this process to the SPOT GPU queue with accelerator=1.
// ============================================================================

def _useAws = System.getenv('NEXTFLOW_USE_AWS') == 'true' || params.use_aws
def GROMACS_CONTAINER = _useAws
    ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/gromacs-cuda:2024-cu12'
    : 'biomate/gromacs-cuda:2024-cu12'

params.use_aws = false

// ============================================================================
// Process
// ============================================================================

process FEP_PRODUCTION {
    /*
     * Runs the reviewed gromacs/pmx engine end-to-end (--run-all) in one --outdir.
     * Named FEP_PRODUCTION so the gpu_batch profile's withName:'EQUILIBRATE|FEP_PRODUCTION'
     * routing (SPOT GPU queue + accelerator=1 + 16 CPU / 64 GB) applies. In setup mode
     * the chain halts at the first spend gate (equilibrate) and no GPU work runs.
     */
    tag "fep:${params.edge_kind}:${params.mode}"
    container GROMACS_CONTAINER
    publishDir "${params.outdir}", mode: params.publish_dir_mode

    accelerator params.mode == 'setup' ? 0 : 1

    input:
    path receptor_file
    path entrypoint          // bin/run_gromacs_pmx_fep.py, staged from projectDir

    output:
    path 'results/**',                 emit: results,  optional: true
    path 'ddg_summary.json',           emit: summary,  optional: true
    path 'run_manifest.json',          emit: manifest

    script:
    // Clear the two cheap CPU QC gates so the chain reaches 'prepare'. In setup mode
    // the spend gates stay un-cleared → it halts before any GPU spend. In smoke/
    // production the GPU-Batch launch is the user's confirmed go, so clear them too.
    def gates = params.mode == 'setup'
        ? 'knowledge_liability_gate fto_gate'
        : 'knowledge_liability_gate fto_gate equilibrate fep_production analyze'
    def edge_spec_arg = params.edge_spec            ? "--edge-spec '${params.edge_spec}'" : ''
    def ctrl_arg      = params.control_edge_expected ? "--control-edge-expected ${params.control_edge_expected}" : ''
    """
    set -euo pipefail
    mkdir -p results
    python3 ${entrypoint} \\
        --run-all \\
        --gates-cleared ${gates} \\
        --mode ${params.mode} \\
        --receptor ${receptor_file} \\
        --edge-kind ${params.edge_kind} \\
        ${edge_spec_arg} \\
        --modality ${params.modality} \\
        --metal-model ${params.metal_model} \\
        --legs '${params.legs}' \\
        --force-field ${params.force_field} \\
        --dt-fs ${params.dt_fs} \\
        --equil-ns ${params.equil_ns} \\
        --restraints ${params.restraints} \\
        --lambda-windows ${params.lambda_windows} \\
        --production-ns ${params.production_ns} \\
        --protocol-repeats ${params.protocol_repeats} \\
        --temperature ${params.temperature} \\
        ${ctrl_arg} \\
        --outdir results \\
        | tee run_manifest.json

    # Surface the engine's ddg_summary.json to the top level if the chain produced one.
    if [ -f results/ddg_summary.json ]; then cp results/ddg_summary.json ddg_summary.json; fi
    """

    stub:
    """
    mkdir -p results
    echo '{"run_all": true, "mode": "${params.mode}", "steps": [], "status": "stub"}' > run_manifest.json
    echo '{"mode": "${params.mode}", "ddg_kcal_per_mol": null, "status": "stub (no fabricated ΔΔG)"}' > ddg_summary.json
    """
}

// ============================================================================
// Workflow
// ============================================================================

// Map catalog/coldstart receptor values to the bundled asset (ported from the stub):
// bare "1BXL.pdb" / empty / an unexpanded ${projectDir} CLI echo must resolve to the
// workflow asset, NOT a CWD-relative miss that fails Channel.fromPath on Batch.
def _resolveReceptor(raw) {
    def bundled = "${projectDir}/assets/1BXL.pdb"
    def s = (raw == null) ? '' : raw.toString().trim()
    if (!s || s.equalsIgnoreCase('null') || s.equalsIgnoreCase('none')) return bundled
    if (s.contains('${projectDir}') || s.contains('sample_data/peptides/1BXL')) return bundled
    if (s.equalsIgnoreCase('1BXL.pdb') || s.equalsIgnoreCase('1BXL')) return bundled
    if (!s.contains('/') && !s.contains('\\') && s.toLowerCase().endsWith('.pdb')) {
        def cand = file("${projectDir}/assets/${s}")
        if (cand.exists()) return cand.toString()
    }
    return s
}

workflow {
    def receptor_path = _resolveReceptor(params.receptor)
    ch_receptor   = Channel.fromPath(receptor_path, checkIfExists: true)
    ch_entrypoint = Channel.fromPath("${projectDir}/bin/run_gromacs_pmx_fep.py", checkIfExists: true)

    FEP_PRODUCTION(ch_receptor, ch_entrypoint)

    FEP_PRODUCTION.out.summary
        .ifEmpty { file('NO_SUMMARY') }
        .view { f ->
            if (f.name == 'NO_SUMMARY') {
                log.info ""
                log.info "  gromacs_pmx_fep — ${params.mode} mode: chain halted before analyze "
                log.info "  (no ΔΔG yet — honest; see run_manifest.json for the gate record)."
                log.info ""
                return
            }
            def d = new groovy.json.JsonSlurper().parseText(f.text)
            log.info ""
            log.info "══════════════════════════════════════════════════════"
            log.info "  gromacs_pmx_fep — ${params.mode} mode"
            log.info "  status: ${d.status}"
            if (d.ddg_kcal_per_mol != null) {
                log.info "  ΔΔG = ${d.ddg_kcal_per_mol} ± ${d.ddg_sem_kcal_per_mol ?: '?'} kcal/mol"
            } else {
                log.info "  ΔΔG = (withheld — see status; no fabrication)"
            }
            log.info "══════════════════════════════════════════════════════"
            log.info ""
        }
}
