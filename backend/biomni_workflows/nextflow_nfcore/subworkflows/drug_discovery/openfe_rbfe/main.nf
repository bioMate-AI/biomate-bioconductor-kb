#!/usr/bin/env nextflow
/*
 * drug_discovery/openfe_rbfe
 *
 * REAL relative binding free energy (RBFE / FEP) for a congeneric ligand pair,
 * using OpenFE (openfe, MIT) — the field-standard open small-molecule RBFE
 * engine — on OpenMM 8. This replaces the bespoke FEP (deck slides 5/6/10)
 * that never converged; there was no small-molecule RBFE before this.
 *
 * The pipeline runs three phases:
 *   1. PREP           — RDKit standardise + ETKDG 3D conformers for both ligands.
 *   2. RBFE_SETUP     — REAL OpenFE: SmallMoleculeComponent / ProteinComponent /
 *                       SolventComponent; LOMAP atom-mapping; minimal-spanning
 *                       ligand network; RelativeHybridTopologyProtocol + DAG.
 *                       (--mode setup: constructs everything, emits NO ΔΔG.)
 *   3. OPENFE_ANALYSIS— REAL RBFE: openfe.execute_dag over the lambda windows
 *                       (GPU), then protocol.gather(...).get_estimate() /
 *                       get_uncertainty() → per-edge ΔΔG ± SEM via MBAR.
 *                       (--mode production; runs on the GPU Batch queue.)
 *
 * HONESTY CONTRACT — enforced in bin/run_openfe_rbfe.py, not here:
 *   A real RBFE edge needs a GPU and hours of sampling. Without a CUDA/OpenCL
 *   platform the script records status='requires_gpu' and writes
 *   ddg_kcal_per_mol=null. It NEVER fabricates a ΔΔG or a synthetic overlap
 *   matrix. `params.mode` selects setup | smoke | production.
 *
 * All the OpenFE logic lives in the reviewed entrypoint bin/run_openfe_rbfe.py
 * (mirrors the mpo_denovo_optimization pattern) — no free-energy logic in this
 * .nf, so what runs on Batch is exactly the reviewed script.
 *
 * Validation edge (built in): a known congeneric pair from the OpenFE tutorial
 * set (Tyk2 / CDK2). --validate <edge> compares the production ΔΔG against the
 * published experimental value; success = within ~1 kcal/mol with sane SEM.
 *
 * References:
 *   OpenFE:  Hahn et al. Living J. Comput. Mol. Sci. 2022, 4:1497
 *   LOMAP:   Liu et al. J. Comput.-Aided Mol. Des. 2013, 27:755
 *   MBAR:    Shirts & Chodera J. Chem. Phys. 2008, 129:124105
 *   Bench:   Schindler et al. J. Chem. Inf. Model. 2020, 60:5457
 *   QC gate: Mey et al. Living J. Comput. Mol. Sci. 2020, 2:18378 (cycle closure)
 */

nextflow.enable.dsl = 2

// ============================================================================
// Parameters
// ============================================================================

params.outdir            = './results/openfe_rbfe'
params.publish_dir_mode  = 'copy'

// Inputs
params.receptor          = null    // protein PDB (target)
params.ligand_a          = null    // reference ligand SDF
params.ligand_b          = null    // query ligand SDF

// Execution mode (honesty contract lives in bin/run_openfe_rbfe.py)
//   setup       — construct protocol + LOMAP mapping only (CPU, seconds, NO ΔΔG)
//   smoke       — setup + GPU-presence probe (still NO ΔΔG unless converged)
//   production  — real GPU RBFE → MBAR ΔΔG ± SEM
params.mode              = 'setup'

// Validation edge key, e.g. 'tyk2:ejm_31->ejm_42' (compares to published ΔΔG)
params.validate          = ''

// Alchemical protocol
params.temperature       = 298.15  // K
params.equilibration_ns  = 1.0     // ns
params.production_ns     = 5.0     // ns per lambda window
params.lambda_windows    = 11      // number of lambda states
params.protocol_repeats  = 3       // independent repeats (SEM)
params.max3d             = 1.0     // LOMAP 3D distance cutoff (Angstrom)

// ============================================================================
// Container — ECR switch (AWS Batch AMD64) vs local ARM dev, docking convention
// ============================================================================

// aws batch (AMD64): openfe-rbfe ECR image (openfe + openmm + lomap + cinnabar)
// local dev:         official OpenFE image (CPU; setup/smoke only)
def _useAws = System.getenv('NEXTFLOW_USE_AWS') == 'true' || params.use_aws
def OPENFE_CONTAINER = _useAws
    ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/openfe-rbfe:1.0'
    : 'ghcr.io/openfreeenergy/openfe:1.2.0'

params.use_aws = false

// ============================================================================
// Processes
// ============================================================================

process PREP {
    /*
     * Standardise both ligands and generate ETKDG 3D conformers (RDKit).
     * Protein is passed through as-is; PDBFixer prep happens inside OpenFE's
     * protein handling during RBFE_SETUP.
     */
    tag 'prep'
    container OPENFE_CONTAINER
    publishDir "${params.outdir}/prep", mode: params.publish_dir_mode

    input:
    path ligand_a_file
    path ligand_b_file

    output:
    path 'ligand_a_prepped.sdf', emit: ligand_a
    path 'ligand_b_prepped.sdf', emit: ligand_b

    script:
    """
    set -euo pipefail
    python3 - <<'PYEOF'
from rdkit import Chem
from rdkit.Chem import AllChem

def prep(inp, outp):
    supp = Chem.SDMolSupplier(inp, removeHs=False)
    mol = next(m for m in supp if m is not None)
    mol = Chem.AddHs(mol)
    p = AllChem.ETKDGv3(); p.randomSeed = 42
    if AllChem.EmbedMolecule(mol, p) == -1:
        AllChem.EmbedMolecule(mol, AllChem.ETKDG())
    AllChem.MMFFOptimizeMolecule(mol)
    w = Chem.SDWriter(outp); w.write(mol); w.close()
    print(f"{inp} -> {outp}: {mol.GetNumHeavyAtoms()} heavy atoms")

prep('${ligand_a_file}', 'ligand_a_prepped.sdf')
prep('${ligand_b_file}', 'ligand_b_prepped.sdf')
PYEOF
    """

    stub:
    """
    cp ${ligand_a_file} ligand_a_prepped.sdf
    cp ${ligand_b_file} ligand_b_prepped.sdf
    """
}

process RBFE_SETUP {
    /*
     * Real OpenFE setup: LOMAP atom-mapping + minimal-spanning ligand network +
     * RelativeHybridTopologyProtocol + DAG construction. Emits the network JSON
     * and (in setup mode) NO ΔΔG. Delegates to the reviewed entrypoint.
     */
    tag 'rbfe_setup'
    container OPENFE_CONTAINER
    publishDir "${params.outdir}/setup", mode: params.publish_dir_mode

    input:
    path receptor_file
    path ligand_a_file
    path ligand_b_file
    path entrypoint          // bin/run_openfe_rbfe.py, staged from projectDir

    output:
    path 'rbfe_network.json', emit: network
    path 'ddg_summary.json',  emit: setup_summary
    path 'qc_metrics.json',   emit: qc_metrics
    path 'run_log.txt',       emit: log

    script:
    def validate_arg = params.validate ? "--validate '${params.validate}'" : ''
    """
    set -euo pipefail
    python3 ${entrypoint} \\
        --mode setup \\
        --receptor ${receptor_file} \\
        --ligand-a ${ligand_a_file} \\
        --ligand-b ${ligand_b_file} \\
        --temperature ${params.temperature} \\
        --equilibration-ns ${params.equilibration_ns} \\
        --production-ns ${params.production_ns} \\
        --lambda-windows ${params.lambda_windows} \\
        --protocol-repeats ${params.protocol_repeats} \\
        --max3d ${params.max3d} \\
        ${validate_arg}
    """

    stub:
    """
    echo '{"n_mapped_atoms": null, "note": "stub"}' > rbfe_network.json
    echo '{"mode": "setup", "ddg_kcal_per_mol": null, "status": "stub"}' > ddg_summary.json
    echo '{"process": "OPENFE_ANALYSIS", "domain": "drug_discovery", "cycle_closure_kcal_per_mol": null, "openfe_cycle_closure_status": "stub"}' > qc_metrics.json
    echo 'stub' > run_log.txt
    """
}

process OPENFE_ANALYSIS {
    /*
     * Real RBFE production: execute the DAG over the lambda windows (GPU) and
     * MBAR-gather the per-edge ΔΔG ± SEM. Emits ddg_summary.json (real number
     * or an honest null + status) and the openfe_cycle_closure QC gate row.
     *
     * Process name kept as OPENFE_ANALYSIS because the QC trace monitor keys
     * the cycle_closure gate off ("OPENFE_ANALYSIS", "*", "qc_metrics.json").
     */
    tag 'openfe_analysis'
    container OPENFE_CONTAINER
    publishDir "${params.outdir}/analysis", mode: params.publish_dir_mode

    cpus   16
    memory '64.GB'
    time   '96h'
    accelerator params.mode == 'production' ? 1 : 0

    input:
    path receptor_file
    path ligand_a_file
    path ligand_b_file
    path entrypoint

    output:
    path 'ddg_summary.json', emit: summary
    path 'qc_metrics.json',  emit: qc_metrics
    path 'rbfe_network.json',emit: network
    path 'run_log.txt',      emit: log

    script:
    def validate_arg = params.validate ? "--validate '${params.validate}'" : ''
    """
    set -euo pipefail
    python3 ${entrypoint} \\
        --mode ${params.mode} \\
        --receptor ${receptor_file} \\
        --ligand-a ${ligand_a_file} \\
        --ligand-b ${ligand_b_file} \\
        --temperature ${params.temperature} \\
        --equilibration-ns ${params.equilibration_ns} \\
        --production-ns ${params.production_ns} \\
        --lambda-windows ${params.lambda_windows} \\
        --protocol-repeats ${params.protocol_repeats} \\
        --max3d ${params.max3d} \\
        ${validate_arg}
    """

    stub:
    """
    echo '{"mode": "${params.mode}", "ddg_kcal_per_mol": null, "status": "stub (no fabricated ΔΔG)"}' > ddg_summary.json
    echo '{"process": "OPENFE_ANALYSIS", "domain": "drug_discovery", "cycle_closure_kcal_per_mol": null, "openfe_cycle_closure_status": "stub"}' > qc_metrics.json
    echo '{"note": "stub"}' > rbfe_network.json
    echo 'stub' > run_log.txt
    """
}

// ============================================================================
// Workflow
// ============================================================================

workflow {
    if (!params.receptor) error "params.receptor is required (protein PDB file)"
    if (!params.ligand_a) error "params.ligand_a is required (reference ligand SDF)"
    if (!params.ligand_b) error "params.ligand_b is required (query ligand SDF)"

    ch_receptor   = Channel.fromPath(params.receptor, checkIfExists: true)
    ch_ligand_a   = Channel.fromPath(params.ligand_a, checkIfExists: true)
    ch_ligand_b   = Channel.fromPath(params.ligand_b, checkIfExists: true)
    // Ship the exact reviewed entrypoint into each task's work dir.
    ch_entrypoint = Channel.fromPath("${projectDir}/bin/run_openfe_rbfe.py")

    PREP(ch_ligand_a, ch_ligand_b)

    RBFE_SETUP(
        ch_receptor,
        PREP.out.ligand_a,
        PREP.out.ligand_b,
        ch_entrypoint
    )

    // In setup/smoke mode this still runs the reviewed script honestly (no ΔΔG
    // unless a real MBAR estimate exists). In production mode it computes the
    // real ΔΔG on the GPU queue.
    OPENFE_ANALYSIS(
        ch_receptor,
        PREP.out.ligand_a,
        PREP.out.ligand_b,
        ch_entrypoint
    )

    OPENFE_ANALYSIS.out.summary
        .view { f ->
            def d = new groovy.json.JsonSlurper().parseText(f.text)
            log.info ""
            log.info "══════════════════════════════════════════════════════"
            log.info "  OpenFE RBFE — ${d.mode} mode"
            log.info "  status: ${d.status}"
            if (d.ddg_kcal_per_mol != null) {
                log.info "  ΔΔG = ${d.ddg_kcal_per_mol} ± ${d.ddg_sem_kcal_per_mol} kcal/mol"
            } else {
                log.info "  ΔΔG = (withheld — see status; no fabrication)"
            }
            if (d.validation) { log.info "  validation: ${d.validation}" }
            log.info "══════════════════════════════════════════════════════"
            log.info ""
        }
}
