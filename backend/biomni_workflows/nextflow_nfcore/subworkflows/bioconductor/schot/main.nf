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

    # --- Global Higher-Order Calculation [] ---
    # Key functions: scHOT_calculateGlobalHigherOrderFunction, scHOT_setPermutationScaffold
    scHOT_traj <- scHOT_calculateGlobalHigherOrderFunction(
        scHOT_traj,
        higherOrderFunction = matrixStats::weightedVar,
        higherOrderFunctionType = "weighted"
    )
    scHOT_traj <- scHOT_setPermutationScaffold(
        scHOT_traj,
        numberPermutations = c(20, 50, 20),
        storePermutations = c(TRUE, FALSE, TRUE)
    )


    # --- Permutation Testing [] ---
    # Key functions: scHOT_calculateHigherOrderTestStatistics, scHOT_performPermutationTest, scHOT_estimatePvalues
    scHOT_traj <- scHOT_calculateHigherOrderTestStatistics(
        scHOT_traj,
        higherOrderSummaryFunction = sd
    )
    scHOT_traj <- scHOT_performPermutationTest(
        scHOT_traj,
        verbose = FALSE,
        parallel = FALSE
    )
    scHOT_traj <- scHOT_estimatePvalues(
        scHOT_traj,
        nperm_estimate = 10000,
        maxDist = 5
    )


    # --- Visualisation [] ---
    # Key functions: plotHigherOrderSequence, plotOrderedExpression
    gene_to_test <- as.matrix(c("Birc5", "H2afz", "Tacc3"))
    p1 <- plotHigherOrderSequence(scHOT_traj, gene_to_test)
    p2 <- plotOrderedExpression(scHOT_traj, gene_to_test)

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
