#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MetCirc
// MetCirc comprises a workflow to interactively explore high-resolution MS/MS metabolomics data. MetCi
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MetCirc/inst/doc/MetCirc.R
// Upstream  : MsCoreUtils, knitr
// Downstream: none
//
// Install: BiocManager::install("MetCirc")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METCIRC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-metcirc"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-metcirc:1.36.0--r44_0' :
        'quay.io/biocontainers/bioconductor-metcirc:1.36.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_metcirc_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_metcirc_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_metcirc_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MetCirc)
    library(jsonlite)

    # --- hcluster [] ---
    # Key functions: hcluster
    hClustMSP <- hcluster(similarityMat, method="spearman")
    plot(hClustMSP, labels = FALSE, xlab="", sub="")
    # --- cutree [] ---
    # Key functions: cutree
    cutTreeMSP <- cutree(hClustMSP, k = 3)
    module1 <- names(cutTreeMSP)[as.vector(cutTreeMSP) == "1"]
    # --- order Similarity Matrix [] ---
    # Key functions: orderSimilarityMatrix, createLinkDf
    condition <- c("SPL", "LIM", "ANT", "STY")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_metcirc_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_metcirc_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_metcirc_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_METCIRC:", paste0("    metcirc: ", packageVersion("MetCirc"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_metcirc_results.csv
    touch ${prefix}_metcirc_output.rds
    echo "BIOC_METCIRC:" > versions.yml
    echo "    metcirc: 0.0.0" >> versions.yml
    """
}


workflow BIOC_METCIRC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_METCIRC(ch_input)

    emit:
    results  = BIOC_METCIRC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_METCIRC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_METCIRC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_METCIRC.out.versions  // channel: path(versions.yml)
}
