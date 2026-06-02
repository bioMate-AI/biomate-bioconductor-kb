#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: scHOT
// Single cell Higher Order Testing (scHOT) is an R package that facilitates testing changes in higher 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/scHOT/inst/doc/scHOT.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("scHOT")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCHOT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-schot"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-schot:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-schot:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_schot_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_schot_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_schot_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(scHOT)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data(liver)
    liver_pseudotime_hep <- liver$liver_pseudotime_hep
    liver_branch_hep <- liver$liver_branch_hep
    first_branch_cells <- liver$first_branch_cells
    # --- Schot Buildfrommatrix [] ---
    # Key functions: scHOT_buildFromMatrix
    ---------------------------------------------------------------------
    # --- Plotexpression [] ---
    # Key functions: plotExpression
    ---------------------------------------------------------------------
    scater::plotExpression(scHOT_traj, c("Sall4"),
                           exprs_values = "expression", x = "pseudotime")
    # --- Schot [] ---
    # Key functions: scHOT
    ---------------------------------------------------------------------
    # --- Slot [] ---
    # Key functions: slot, plotHigherOrderSequence, plotOrderedExpression, facet_wrap
    ---------------------------------------------------------------------
    slot(scHOT_traj_wrap, "scHOT_output")
    scHOT_traj_wrap@scHOT_output
    slot(scHOT_traj_wrap, "scHOT_output")$higherOrderSequence
    plotHigherOrderSequence(scHOT_traj_wrap, gene_to_test)
    # --- Schot Addtestingscaffold [] ---
    # Key functions: scHOT_addTestingScaffold
    ---------------------------------------------------------------------
    scHOT_traj@testingScaffold
    scHOT_traj <- scHOT_addTestingScaffold(scHOT_traj, gene_to_test)
    scHOT_traj@testingScaffold
    # --- Schot Setweightmatrix [] ---
    # Key functions: scHOT_setWeightMatrix
    ---------------------------------------------------------------------
    scHOT_traj@weightMatrix
    # --- Schot Calculateglobalhigherorderfunction [] ---
    # Key functions: scHOT_calculateGlobalHigherOrderFunction, slot, assay
    ---------------------------------------------------------------------
    scHOT_traj <- scHOT_calculateGlobalHigherOrderFunction(
      scHOT_traj,
      higherOrderFunction = matrixStats::weightedVar,
      higherOrderFunctionType = "weighted")
    # --- Schot Setpermutationscaffold [] ---
    # Key functions: scHOT_setPermutationScaffold, slot
    ---------------------------------------------------------------------
    scHOT_traj <- scHOT_setPermutationScaffold(scHOT_traj,
                                               numberPermutations = c(20,50,20),
                                               storePermutations = c(TRUE, FALSE, TRUE))
    slot(scHOT_traj, "scHOT_output")
    # --- Schot Calculatehigherorderteststatistics [] ---
    # Key functions: scHOT_calculateHigherOrderTestStatistics, slot
    ---------------------------------------------------------------------
    scHOT_traj <- scHOT_calculateHigherOrderTestStatistics(
      scHOT_traj,
      higherOrderSummaryFunction = sd)
    slot(scHOT_traj, "scHOT_output")
    # --- Time [] ---
    # Key functions: time, scHOT_performPermutationTest, slot
    ---------------------------------------------------------------------
    system.time(scHOT_traj <- scHOT_performPermutationTest(
      scHOT_traj,
      verbose = TRUE,
      parallel = FALSE))
    # --- Schot Estimatepvalues [] ---
    # Key functions: scHOT_estimatePvalues, slot
    ---------------------------------------------------------------------
    scHOT_traj <- scHOT_estimatePvalues(scHOT_traj,
                                        nperm_estimate = 10000,
                                        maxDist = 5)
    slot(scHOT_traj, "scHOT_output")
    # --- Plothigherordersequence [] ---
    # Key functions: plotHigherOrderSequence
    ---------------------------------------------------------------------
    plotHigherOrderSequence(scHOT_traj, gene_to_test)
    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data(MOB_subset)
    sce_MOB_subset <- MOB_subset$sce_MOB_subset
    sce_MOB_subset
    # --- Schot Buildfromsce [] ---
    # Key functions: scHOT_buildFromSCE
    ---------------------------------------------------------------------
    scHOT_spatial <- scHOT_buildFromSCE(sce_MOB_subset,
                                        assayName = "logcounts",
                                        positionType = "spatial",
                                        positionColData = c("x", "y"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_schot_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_schot_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_schot_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCHOT:", paste0("    schot: ", packageVersion("scHOT"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_schot_results.csv
    touch ${prefix}_schot_output.rds
    echo "BIOC_SCHOT:" > versions.yml
    echo "    schot: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCHOT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SCHOT(ch_input)

    emit:
    results  = BIOC_SCHOT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCHOT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCHOT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCHOT.out.versions  // channel: path(versions.yml)
}
