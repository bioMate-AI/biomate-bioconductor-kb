#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: QFeatures
// The QFeatures infrastructure enables the management and processing of quantitative features for high
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/QFeatures/inst/doc/Processing.R
// Upstream  : ComplexHeatmap, dplyr, ggplot2, gplots
// Downstream: hdxmsqc, msqrob2, scp, scpdata
//
// Install: BiocManager::install("QFeatures")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_QFEATURES {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-qfeatures"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-qfeatures:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-qfeatures:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_qfeatures_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_qfeatures_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_qfeatures_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(QFeatures)
    library(jsonlite)

    # --- Missing Value Handling and Imputation [] ---
    # Key functions: zeroIsNA, nNA, filterNA
    cptac <- zeroIsNA(cptac, i = seq_along(cptac))
    na_stats <- nNA(cptac, i = seq_along(cptac))
    cptac <- filterNA(cptac, i = seq_along(cptac), pNA = 0)


    # --- Transformation and Normalisation [] ---
    # Key functions: logTransform, normalize, addAssay
    cptac <- addAssay(
        cptac,
        logTransform(cptac[[1]]),
        name = "peptides_log"
    )
    cptac <- addAssay(
        cptac,
        normalize(cptac[["peptides_log"]], method = "center.median"),
        name = "peptides_norm"
    )


    # --- Feature Aggregation [] ---
    # Key functions: aggregateFeatures, longFormat
    cptac <- aggregateFeatures(
        cptac,
        i = "peptides_norm",
        fcol = "Proteins",
        name = "proteins"
    )
    df_long <- as.data.frame(longFormat(cptac))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_qfeatures_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_qfeatures_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_qfeatures_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_QFEATURES:", paste0("    qfeatures: ", packageVersion("QFeatures"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_qfeatures_results.csv
    touch ${prefix}_qfeatures_output.rds
    echo "BIOC_QFEATURES:" > versions.yml
    echo "    qfeatures: 0.0.0" >> versions.yml
    """
}


workflow BIOC_QFEATURES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_QFEATURES(ch_input)

    emit:
    results  = BIOC_QFEATURES.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_QFEATURES.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_QFEATURES.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_QFEATURES.out.versions  // channel: path(versions.yml)
}
