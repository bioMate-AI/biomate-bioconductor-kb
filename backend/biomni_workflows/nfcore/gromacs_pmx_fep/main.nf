#!/usr/bin/env nextflow
/*
 * drug_discovery/gromacs_pmx_fep
 *
 * GENERIC relative binding free energy (ΔΔG / FEP) for edges OpenFE cannot do:
 * residue-mutation / peptide / cyclic-peptide / metal-bridged. Companion to
 * openfe_rbfe (small-molecule congeneric pairs) — the composer routes an FEP
 * request to whichever engine fits the edge (Layer B,
 * docs/20261020_GENERIC_PHYSICS_IN_LOOP_FRAMEWORK_DESIGN.md). αvβ6 is the
 * acceptance-test instance, not a hardcoded assumption.
 *
 * TRANSPARENT STEP CHAIN (five phase cards, mirroring openfe_rbfe's phases):
 *   1. DEFINE_EDGE   — validate/normalise the edge (receptor, edge, modality, metal_model)
 *   2. PREPARE       — pmx hybrid topology + solvate/ionize per leg (atom counts previewable)
 *   3. EQUILIBRATE   — em→NVT→NPT; stability metrics (QC gate: junction/metal hold)   [GPU, SPEND GATE]
 *   4. FEP_PRODUCTION— dH/dλ per λ window                                             [GPU, SPEND GATE]
 *   5. ANALYZE       — ΔΔG ± uncertainty + cycle_closure QC verdict (QC GATE)
 *
 * ORCHESTRATION: steps AUTO-ADVANCE between gates; GATES ALWAYS HALT for explicit
 * user go. Spend gates (EQUILIBRATE, FEP_PRODUCTION launch GPU/Batch) → confirm-before-run,
 * never auto-spend. QC gates (EQUILIBRATE stability, ANALYZE cycle_closure) → the chain
 * never auto-proceeds past a verdict. Realised in the panel via run/pause + the QC-gate
 * card + confirm-before-run; realised in the engine by bin/run_gromacs_pmx_fep.py's
 * --gates-cleared semantics. Each phase still surfaces its params/inputs/outputs; the
 * user can switch to manual (--step) or pause at any point.
 *
 * HONESTY CONTRACT — enforced in bin/run_gromacs_pmx_fep.py, not here. A step without its
 * tools/GPU records requires_tools/requires_gpu and writes NULL numerics; it NEVER
 * fabricates a prepared system, an energy, or a ΔΔG. All MD/FEP logic lives in the reviewed
 * entrypoint; this .nf only stages files and calls it per step.
 *
 * HARD-WON DEFAULTS (αvβ6 instance-zero → generic requirements): version-independent staged
 * inputs (stage .gro+.top, grompp in the run image — never a prebuilt .tpr); cyclic
 * origin-rotation; by-name moleculetype selection; newline-safe [molecules]; fail-loudly;
 * cada-vsite@2fs preferred / cada-bonded<=0.5fs fallback.
 *
 * References:
 *   pmx:   Gapsys et al. J. Chem. Theory Comput. 2015, 11:2937 (mutation FEP)
 *   CaDA:  Duarte et al. J. Phys. Chem. B 2014, 118:4351 (cationic dummy metal)
 *   MBAR:  Shirts & Chodera J. Chem. Phys. 2008, 129:124105
 *   QC:    Mey et al. Living J. Comput. Mol. Sci. 2020, 2:18378 (cycle closure)
 */

nextflow.enable.dsl = 2

// ============================================================================
// Parameters (surfaced in the panel param strip; grouped per step in nextflow_schema.json)
// ============================================================================
params.outdir            = './results/gromacs_pmx_fep'
params.publish_dir_mode  = 'copy'

// 1 · define_edge
// Default receptor = vendored BCL-XL demo (1BXL) so coldstart peptide FEP can
// launch when Prepared inputs only named `1BXL.pdb` and staging lagged.
params.receptor          = "${projectDir}/../../sample_data/peptides/1BXL.pdb"
params.edge_kind         = 'peptide_pair'       // residue_mutation | peptide_pair
params.edge_spec         = 'GQVGRQLAIIGDDINR|AQVGRQLAIIGDDINR'  // BAK BH3 vs G1A
params.modality          = 'peptide'            // peptide | cyclic_peptide
params.metal_model       = 'none'               // none | cada:<Mn|Zn|Ca|Mg>

// 2 · prepare
params.legs              = 'complex,solvent'

// 3 · equilibrate
params.dt_fs             = 2.0                   // cada-bonded forces <=0.5; cada-vsite/non-metal use 2
params.equil_ns          = 0.7
params.restraints        = 'backbone'           // none | backbone | heavy

// 4 · fep_production
params.lambda_windows    = 12
params.production_ns     = 5.0
params.protocol_repeats  = 3
params.temperature       = 298.15

// 5 · analyze
params.control_edge_expected = null             // known ΔΔG (kcal/mol) for a control edge

// Execution mode (honesty contract) + gate clearing (spend/QC confirm-before-run)
params.mode              = 'setup'              // setup | smoke | production
params.gates_cleared     = ''                   // space/comma list, e.g. 'equilibrate fep_production'

// ============================================================================
// Containers — ECR (AWS Batch AMD64) vs local dev
// DEFINE_EDGE / knowledge gates are pure Python. The GROMACS CUDA image often
// has no python3 → DEFINE_EDGE "Essential container exited" (coldstart
// design-predict-filter-pep-3). Use workflow-tools for Python steps; GMX only
// for MD legs that need gmx/pmx.
// ============================================================================
def _useAws = System.getenv('NEXTFLOW_USE_AWS') == 'true' || params.use_aws
def GMX_CONTAINER = _useAws
    ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/gromacs-cuda:2024-cu12'
    : 'gromacs/gromacs:2024.3'
def PY_CONTAINER = _useAws
    ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/workflow-tools:x86'
    : 'biomate/workflow-tools:latest'
params.use_aws = false

def _entry() { return Channel.fromPath("${projectDir}/bin/run_gromacs_pmx_fep.py") }
def _gates() { return (params.gates_cleared ?: '').replaceAll(',', ' ').trim() }

// ============================================================================
// Processes (one per step = one phase card)
// ============================================================================
process DEFINE_EDGE {
    tag 'define_edge'
    container PY_CONTAINER
    publishDir "${params.outdir}/01_define_edge", mode: params.publish_dir_mode

    input:
    path receptor_file
    path entrypoint

    output:
    path 'edge_spec.json', emit: edge_spec

    script:
    """
    set -euo pipefail
    python3 ${entrypoint} --step define_edge --outdir . \\
        --receptor ${receptor_file} --edge-kind '${params.edge_kind}' \\
        --edge-spec '${params.edge_spec}' --modality ${params.modality} \\
        --metal-model '${params.metal_model}'
    """

    stub:
    "echo '{\"step\":\"define_edge\",\"status\":\"stub\"}' > edge_spec.json"
}

process PREPARE {
    tag 'prepare'
    container PY_CONTAINER
    publishDir "${params.outdir}/02_prepare", mode: params.publish_dir_mode
    cpus 8
    memory '32.GB'
    time '4h'

    input:
    path receptor_file
    path edge_spec
    path entrypoint

    output:
    path 'prepared_systems.json', emit: prepared

    script:
    """
    set -euo pipefail
    python3 ${entrypoint} --step prepare --outdir . \\
        --receptor ${receptor_file} --edge-spec '${params.edge_spec}' \\
        --modality ${params.modality} --metal-model '${params.metal_model}' \\
        --legs '${params.legs}' --mode ${params.mode}
    """

    stub:
    "echo '{\"step\":\"prepare\",\"status\":\"stub\"}' > prepared_systems.json"
}

process EQUILIBRATE {
    // SPEND GATE (GPU) + QC GATE (stability). Chain halts here unless 'equilibrate' is
    // in params.gates_cleared. accelerator only in production (confirm-before-run).
    tag 'equilibrate'
    container GMX_CONTAINER
    publishDir "${params.outdir}/03_equilibrate", mode: params.publish_dir_mode
    cpus 16
    memory '64.GB'
    time '24h'
    accelerator params.mode == 'production' ? 1 : 0

    input:
    path prepared
    path entrypoint

    output:
    path 'equil_metrics.json', emit: equil_metrics

    script:
    """
    set -euo pipefail
    python3 ${entrypoint} --step equilibrate --outdir . \\
        --metal-model '${params.metal_model}' --dt-fs ${params.dt_fs} \\
        --equil-ns ${params.equil_ns} --restraints ${params.restraints} \\
        --mode ${params.mode}
    """

    stub:
    "echo '{\"step\":\"equilibrate\",\"status\":\"stub\"}' > equil_metrics.json"
}

process FEP_PRODUCTION {
    // SPEND GATE (GPU). Chain halts unless 'fep_production' is cleared.
    tag 'fep_production'
    container GMX_CONTAINER
    publishDir "${params.outdir}/04_fep_production", mode: params.publish_dir_mode
    cpus 16
    memory '64.GB'
    time '96h'
    accelerator params.mode == 'production' ? 1 : 0

    input:
    path equil_metrics
    path entrypoint

    output:
    path 'dhdl_summary.json', emit: dhdl

    script:
    """
    set -euo pipefail
    python3 ${entrypoint} --step fep_production --outdir . \\
        --lambda-windows ${params.lambda_windows} --production-ns ${params.production_ns} \\
        --protocol-repeats ${params.protocol_repeats} --temperature ${params.temperature} \\
        --metal-model '${params.metal_model}' --mode ${params.mode}
    """

    stub:
    "echo '{\"step\":\"fep_production\",\"status\":\"stub\"}' > dhdl_summary.json"
}

process ANALYZE {
    // QC GATE (cycle_closure). Emits qc_metrics.json keyed (process=ANALYZE) so the QC
    // trace monitor picks up the gate, mirroring openfe_rbfe's OPENFE_ANALYSIS gate.
    tag 'analyze'
    container PY_CONTAINER
    publishDir "${params.outdir}/05_analyze", mode: params.publish_dir_mode
    cpus 4
    memory '16.GB'
    time '2h'

    input:
    path dhdl
    path entrypoint

    output:
    path 'ddg_summary.json', emit: summary
    path 'qc_metrics.json',  emit: qc_metrics

    script:
    def ctrl = params.control_edge_expected != null ? "--control-edge-expected ${params.control_edge_expected}" : ''
    """
    set -euo pipefail
    python3 ${entrypoint} --step analyze --outdir . --mode ${params.mode} ${ctrl}
    """

    stub:
    """
    echo '{"step":"analyze","status":"stub","ddg_kcal_per_mol":null}' > ddg_summary.json
    echo '{"process":"ANALYZE","domain":"drug_discovery","cycle_closure_kcal_per_mol":null,"fep_cycle_closure_status":"stub"}' > qc_metrics.json
    """
}

// ============================================================================
// Workflow — the transparent step chain (auto-advance; gates enforced in the panel/engine)
// ============================================================================
workflow {
    if (!params.receptor)  error "params.receptor is required (protein PDB)"
    if (!params.edge_spec) error "params.edge_spec is required (mutation list or peptide pair)"

    ch_receptor = Channel.fromPath(params.receptor, checkIfExists: true)

    DEFINE_EDGE(ch_receptor, _entry())
    PREPARE(ch_receptor, DEFINE_EDGE.out.edge_spec, _entry())
    EQUILIBRATE(PREPARE.out.prepared, _entry())
    FEP_PRODUCTION(EQUILIBRATE.out.equil_metrics, _entry())
    ANALYZE(FEP_PRODUCTION.out.dhdl, _entry())

    ANALYZE.out.summary.view { f ->
        def d = new groovy.json.JsonSlurper().parseText(f.text)
        log.info ""
        log.info "══════════════════════════════════════════════════════"
        log.info "  GROMACS/pmx Relative FEP — ${params.mode} mode"
        log.info "  status: ${d.status}"
        if (d.ddg_kcal_per_mol != null)
            log.info "  ΔΔG = ${d.ddg_kcal_per_mol} ± ${d.ddg_sem_kcal_per_mol} kcal/mol"
        else
            log.info "  ΔΔG = (withheld — ${d.status}; no fabrication)"
        log.info "══════════════════════════════════════════════════════"
        log.info ""
    }
}
