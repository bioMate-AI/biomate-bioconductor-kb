#!/usr/bin/env nextflow
// ============================================================
// rnaseq_patient_stratification — End-to-end patient stratification
//
// Pipeline:
//   1. BIOC_CONSENSUSCLUSTERPLUS — unsupervised molecular subtype discovery
//      (consensus clustering on expression matrix)
//   2. CRAN_SURVIVAL_KAPLANMEIER — Kaplan-Meier curves per subtype
//   3. CRAN_SURVIVAL_COX         — Cox PH regression with subtypes + covariates
//
// Input channels:
//   ch_expr_matrix  : [ val(meta), path(expr_matrix.rds) ]
//                    — RDS numeric matrix (genes x samples, raw or normalised)
//   ch_clinical     : [ val(meta), path(clinical.csv) ]
//                    — Clinical data CSV with time, event, and covariate columns
//
// Parameters:
//   --max_k        Maximum clusters to test (default: 8)
//   --n_reps       Consensus clustering iterations (default: 500)
//   --time_col     Name of time-to-event column in clinical CSV
//   --event_col    Name of event indicator column (0=censored, 1=event)
//   --group_col    Name of cluster assignment column for KM grouping (default: 'cluster')
//   --covariates   Comma-separated covariate columns for Cox model (e.g. "age,stage")
//   --outdir       Output directory (default: 'results')
//
// Usage:
//   nextflow run rnaseq_patient_stratification/main.nf \
//     --expr_matrix  expr_matrix.rds \
//     --clinical     clinical.csv \
//     --time_col     OS_days \
//     --event_col    OS_event \
//     --covariates   "age,stage" \
//     --max_k        8 \
//     --outdir       results/
//
// Reference:
//   Monti S et al. (2003) J Classification 20:107-136.
//   DOI: 10.1023/A:1023949509487
//   Therneau TM (2024). A Package for Survival Analysis in R.
// ============================================================

nextflow.enable.dsl = 2

include { BIOC_CONSENSUSCLUSTERPLUS_WORKFLOW } from '../../subworkflows/bioconductor/consensusclusterplus/main.nf'
include { CRAN_SURVIVAL_KAPLANMEIER          } from '../../subworkflows/bioconductor/survival/main.nf'
include { CRAN_SURVIVAL_COX                  } from '../../subworkflows/bioconductor/survival/main.nf'

params.expr_matrix  = null
params.clinical     = null
params.max_k        = 8
params.n_reps       = 500
params.time_col     = 'time'
params.event_col    = 'event'
params.group_col    = 'cluster'
params.covariates   = 'cluster'
params.outdir       = 'results'

workflow RNASEQ_PATIENT_STRATIFICATION {

    take:
    ch_expr_matrix  // channel: [ val(meta), path(expr_matrix.rds) ]
    ch_clinical     // channel: [ val(meta), path(clinical.csv) ]

    main:
    ch_versions = Channel.empty()

    // -------------------------------------------------------------------------
    // Step 1: Consensus clustering → molecular subtypes
    // -------------------------------------------------------------------------
    BIOC_CONSENSUSCLUSTERPLUS_WORKFLOW(
        ch_expr_matrix,
        params.max_k,
        params.n_reps
    )
    ch_versions = ch_versions.mix(BIOC_CONSENSUSCLUSTERPLUS_WORKFLOW.out.versions)

    // -------------------------------------------------------------------------
    // Step 2: Kaplan-Meier survival curves per molecular subtype
    // The clinical CSV must contain a 'cluster' column (merged from step 1 output)
    // or the user provides pre-stratified clinical data.
    // -------------------------------------------------------------------------
    CRAN_SURVIVAL_KAPLANMEIER(
        ch_clinical,
        params.time_col,
        params.event_col,
        params.group_col
    )
    ch_versions = ch_versions.mix(CRAN_SURVIVAL_KAPLANMEIER.out.versions)

    // -------------------------------------------------------------------------
    // Step 3: Cox PH regression with subtypes + clinical covariates
    // -------------------------------------------------------------------------
    CRAN_SURVIVAL_COX(
        ch_clinical,
        params.time_col,
        params.event_col,
        params.covariates
    )
    ch_versions = ch_versions.mix(CRAN_SURVIVAL_COX.out.versions)

    emit:
    cluster_assignments = BIOC_CONSENSUSCLUSTERPLUS_WORKFLOW.out.assignments  // [ meta, cluster_assignments.csv ]
    optimal_k           = BIOC_CONSENSUSCLUSTERPLUS_WORKFLOW.out.optimal_k    // [ meta, optimal_k.txt ]
    consensus_plots     = BIOC_CONSENSUSCLUSTERPLUS_WORKFLOW.out.plots        // [ meta, consensus_plots.pdf ]
    icl_scores          = BIOC_CONSENSUSCLUSTERPLUS_WORKFLOW.out.icl_scores   // [ meta, icl_scores.csv ]
    km_summary          = CRAN_SURVIVAL_KAPLANMEIER.out.km_summary            // [ meta, km_summary.csv ]
    logrank_pval        = CRAN_SURVIVAL_KAPLANMEIER.out.logrank_pval          // [ meta, logrank_pvalue.txt ]
    km_fit              = CRAN_SURVIVAL_KAPLANMEIER.out.km_fit                // [ meta, km_fit.rds ]
    cox_results         = CRAN_SURVIVAL_COX.out.cox_results                   // [ meta, cox_results.csv ]
    cox_model           = CRAN_SURVIVAL_COX.out.cox_model                     // [ meta, cox_model.rds ]
    versions            = ch_versions
}

// ---------------------------------------------------------------------------
// Entry point (standalone run)
// ---------------------------------------------------------------------------
workflow {
    if (params.mock_mode || params.test_mode) {
        // Test/mock mode: supply placeholder files (stub blocks handle actual output)
        def test_meta = [id: 'patient_stratification']
        ch_expr     = Channel.of([test_meta, file('NO_FILE')])
        ch_clinical = Channel.of([test_meta, file('NO_CLINICAL_FILE')])
        RNASEQ_PATIENT_STRATIFICATION(ch_expr, ch_clinical)
    } else {
        if (!params.expr_matrix || !params.clinical) {
            error "Usage: nextflow run main.nf --expr_matrix <rds> --clinical <csv> --time_col <col> --event_col <col>"
        }
        def run_meta = [id: 'patient_stratification']
        ch_expr     = Channel.of([run_meta, file(params.expr_matrix)])
        ch_clinical = Channel.of([run_meta, file(params.clinical)])
        RNASEQ_PATIENT_STRATIFICATION(ch_expr, ch_clinical)
    }
}
