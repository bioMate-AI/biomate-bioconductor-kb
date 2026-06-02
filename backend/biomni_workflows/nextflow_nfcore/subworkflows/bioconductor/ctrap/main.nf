#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: cTRAP
// Compare differential gene expression results with those from known cellular perturbations (such as g
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/cTRAP/inst/doc/cTRAP.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("cTRAP")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CTRAP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ctrap"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ctrap:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ctrap:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ctrap_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ctrap_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ctrap_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(cTRAP)
    library(jsonlite)

    # --- Rank Similar Perturbations [] ---
    # Key functions: rankSimilarPerturbations
    compareKD <- rankSimilarPerturbations(
        diffExprStat,
        cmapPerturbationsKD
    )
    compareCompounds <- rankSimilarPerturbations(
        diffExprStat,
        cmapPerturbationsCompounds
    )
    plot(compareKD, "spearman", n=c(10, 3))
    kd_table <- as.table(compareKD)


    # --- Predict Targeting Drugs [] ---
    # Key functions: listExpressionDrugSensitivityAssociation, loadExpressionDrugSensitivityAssociation, predictTargetingDrugs
    ctrp <- listExpressionDrugSensitivityAssociation()[[2]]
    assoc <- loadExpressionDrugSensitivityAssociation(ctrp)
    predicted <- predictTargetingDrugs(diffExprStat, assoc)
    plot(predicted, method="rankProduct")
    plot(predicted, predicted[[1, 1]], method="spearman")


    # --- Compare Drug Predictions and Perturbations [] ---
    # Key functions: plotTargetingDrugsVSsimilarPerturbations
    plotTargetingDrugsVSsimilarPerturbations(
        predicted,
        compareCompounds,
        column="spearman_rank"
    )
    plotTargetingDrugsVSsimilarPerturbations(
        predicted,
        compareCompounds,
        column="spearman_rank",
        labelBy="target"
    )


    # --- Drug Set Enrichment Analysis [] ---
    # Key functions: loadDrugDescriptors, prepareDrugSets, analyseDrugSetEnrichment, plotDrugSetEnrichment
    descriptors <- loadDrugDescriptors("CMap", "2D")
    drugSets <- prepareDrugSets(descriptors)
    dsea <- analyseDrugSetEnrichment(drugSets, predicted)
    plotDrugSetEnrichment(
        drugSets,
        predicted,
        selectedSets=head(dsea$descriptor, 6)
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ctrap_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ctrap_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ctrap_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CTRAP:", paste0("    ctrap: ", packageVersion("cTRAP"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ctrap_results.csv
    touch ${prefix}_ctrap_output.rds
    echo "BIOC_CTRAP:" > versions.yml
    echo "    ctrap: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CTRAP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CTRAP(ch_input)

    emit:
    results  = BIOC_CTRAP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CTRAP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CTRAP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CTRAP.out.versions  // channel: path(versions.yml)
}
