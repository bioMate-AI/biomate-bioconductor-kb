#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Harman
// Harman is a PCA and constrained optimisation based technique that maximises the removal of batch eff
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Harman/inst/doc/IntroductionToHarman.R
// Upstream  : HarmanData, RColorBrewer, bladderbatch, limma, msmsEDA
// Downstream: none
//
// Install: BiocManager::install("Harman")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HARMAN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-harman"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-harman:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-harman:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_harman_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_harman_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_harman_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Harman)
    library(jsonlite)

    # --- Visualisation of Correction [] ---
    # Key functions: arrowPlot, pcaPlot
    arrowPlot(olf.harman, main = "Arrowplot of correction")
    arrowPlot(olf.harman, 1, 8)
    pcaPlot(olf.harman, colBy = "batch", pchBy = "expt")


    # --- Data Reconstruction [] ---
    # Key functions: reconstructData
    olf.data.corrected <- reconstructData(olf.harman)
    olf.data.remade <- reconstructData(olf.harman, this = "original")


    # --- PCA Plotting [] ---
    # Key functions: prcompPlot
    prcompPlot(
        imr90.pca,
        pc_x = 1,
        pc_y = 2,
        colFactor = imr90.info$Batch,
        pchFactor = imr90.info$Treatment,
        main = "IMR90, PC1 v PC2"
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_harman_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_harman_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_harman_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HARMAN:", paste0("    harman: ", packageVersion("Harman"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_harman_results.csv
    touch ${prefix}_harman_output.rds
    echo "BIOC_HARMAN:" > versions.yml
    echo "    harman: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HARMAN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HARMAN(ch_input)

    emit:
    results  = BIOC_HARMAN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HARMAN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HARMAN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HARMAN.out.versions  // channel: path(versions.yml)
}
