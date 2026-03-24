#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DepInfeR
// DepInfeR integrates two experimentally accessible input data matrices: the drug sensitivity profiles
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DepInfeR/inst/doc/vignette.R
// Upstream  : BiocParallel, RColorBrewer, dplyr, ggbeeswarm, ggplot2
// Downstream: none
//
// Install: BiocManager::install("DepInfeR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DEPINFER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-depinfer"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-depinfer:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-depinfer:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_depinfer_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_depinfer_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_depinfer_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DepInfeR)
    library(jsonlite)

    # --- pivot_wider [] ---
    # Key functions: pivot_wider, remove_rownames, column_to_rownames, processTarget
    if (!requireNamespace("BiocManager", quietly = TRUE)) {
    install.packages("BiocManager")
    BiocManager::install("DepInfeR")
    # --- Analysis of variance (ANOVA) [] ---
    # Key functions: rename, anova
    select(-missing_value_perc) %>%
    rename(cancer_type = TCGA.classification) %>%
    filter(rownames(mutation_GDSC) %in% colnames(importanceTab))
    # --- gdsc t [] ---
    # Key functions: diffImportance, rownames_to_column, gather, group_by, arrange
    testRes <- diffImportance(importanceTab, cell_anno_final)
    filter(mutName == "cancer_type") %>%
    filter(p.adj < 0.05, FC > 0.1)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_depinfer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_depinfer_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_depinfer_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DEPINFER:", paste0("    depinfer: ", packageVersion("DepInfeR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_depinfer_results.csv
    touch ${prefix}_depinfer_output.rds
    echo "BIOC_DEPINFER:" > versions.yml
    echo "    depinfer: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DEPINFER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DEPINFER(ch_input)

    emit:
    results  = BIOC_DEPINFER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DEPINFER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DEPINFER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DEPINFER.out.versions  // channel: path(versions.yml)
}
