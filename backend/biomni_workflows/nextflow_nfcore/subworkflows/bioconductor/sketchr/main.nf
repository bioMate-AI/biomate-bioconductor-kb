#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: sketchR
// Provides an R interface for various subsampling algorithms implemented in python packages. Currently
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/sketchR/inst/doc/sketchR.R
// Upstream  : BiocStyle
// Downstream: none
//
// Install: BiocManager::install("sketchR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SKETCHR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sketchr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-sketchr:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-sketchr:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(plot_object)

    output:
    tuple val(meta), path("${meta.id}_sketchr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sketchr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sketchr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(TENxPBMCData)
    library(jsonlite)

    # --- Tenxpbmcdata [] ---
    # Key functions: TENxPBMCData, uniquifyFeatureNames, rowData
    ---------------------------------------------------------------------
    ## Load data
    pbmc3k <- TENxPBMCData::TENxPBMCData(dataset = "pbmc3k")
    ## Set row and column names
    colnames(pbmc3k) <- paste0("Cell", seq_len(ncol(pbmc3k)))
    # --- Geosketch [] ---
    # Key functions: geosketch, reducedDim
    ---------------------------------------------------------------------
    idx800gs <- geosketch(SingleCellExperiment::reducedDim(pbmc3k, "PCA"),
                          N = 800, seed = 123)
    head(idx800gs)
    length(idx800gs)
    # --- Scsampler [] ---
    # Key functions: scsampler, reducedDim
    ---------------------------------------------------------------------
    idx800scs <- scsampler(SingleCellExperiment::reducedDim(pbmc3k, "PCA"),
                           N = 800, seed = 123)
    head(idx800scs)
    length(idx800scs)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_sketchr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_sketchr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_sketchr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SKETCHR:", paste0("    sketchr: ", packageVersion("sketchR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sketchr_results.csv
    touch ${prefix}_sketchr_output.rds
    echo "BIOC_SKETCHR:" > versions.yml
    echo "    sketchr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SKETCHR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(plot_object) ]

    main:
    BIOC_SKETCHR(ch_input)

    emit:
    results  = BIOC_SKETCHR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SKETCHR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SKETCHR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SKETCHR.out.versions  // channel: path(versions.yml)
}
