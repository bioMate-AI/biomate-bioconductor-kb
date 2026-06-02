#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: muscat
// `muscat` provides various methods and visualization tools for DS analysis in multi-sample, multi-gro
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/muscat/inst/doc/analysis.R
// Upstream  : BiocStyle, DESeq2, ExperimentHub, SingleCellExperiment, UpSetR
// Downstream: none
//
// Install: BiocManager::install("muscat")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MUSCAT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-muscat"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-muscat:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-muscat:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_muscat_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_muscat_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_muscat_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ExperimentHub)
    library(jsonlite)

    # --- Access ExperimentHub data [] ---
    # Key functions: ExperimentHub, query
    library(ExperimentHub)
    eh <- ExperimentHub()
    query(eh, "Kang")
    # --- Compute per-cell QC metrics [] ---
    # Key functions: perCellQCMetrics, isOutlier
    calculate per-cell quality control (QC) metrics
    library(scater)
    qc <- perCellQCMetrics(sce)
    # --- Log-normalize count data [] ---
    # Key functions: computeLibraryFactors, logNormCounts
    sce <- computeLibraryFactors(sce)
    sce <- logNormCounts(sce)
    # --- Run UMAP embedding [] ---
    # Key functions: runUMAP, plotReducedDim, guides, theme_minimal
    sce <- runUMAP(sce, pca = 20)
    .plot_dr <- function(sce, dr, col)
    plotReducedDim(sce, dimred = dr, colour_by = col) +
    # --- Assay listing [] ---
    # Key functions: assays, split, unlist, sample, aggregateData, assayNames, mmDS, arrange


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_muscat_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_muscat_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_muscat_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MUSCAT:", paste0("    muscat: ", packageVersion("muscat"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_muscat_results.csv
    touch ${prefix}_muscat_output.rds
    echo "BIOC_MUSCAT:" > versions.yml
    echo "    muscat: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MUSCAT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MUSCAT(ch_input)

    emit:
    results  = BIOC_MUSCAT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MUSCAT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MUSCAT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MUSCAT.out.versions  // channel: path(versions.yml)
}
