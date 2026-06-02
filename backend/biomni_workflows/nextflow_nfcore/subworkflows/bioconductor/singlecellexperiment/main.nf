#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SingleCellExperiment
// Defines a S4 class for storing data from single-cell experiments. This includes specialized methods 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SingleCellExperiment/inst/doc/devel.R
// Upstream  : scRNAseq, Rtsne
// Downstream: alabaster.sce, BASiCS, batchelor, BayesSpace, CATALYST
//
// Install: BiocManager::install("SingleCellExperiment")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SINGLECELLEXPERIMENT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-singlecellexperiment"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-singlecellexperiment:1.28.1--r44_0' :
        'quay.io/biocontainers/bioconductor-singlecellexperiment:1.28.1--r44_0'}"

    input:
    tuple val(meta), path(singlecellexperiment)

    output:
    tuple val(meta), path("${meta.id}_singlecellexperiment_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_singlecellexperiment_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_singlecellexperiment_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SingleCellExperiment)
    library(jsonlite)


    # --- Construct [] ---
    # Key functions: rpois, SingleCellExperiment, function, int_colData, runif, sample
    library(SingleCellExperiment)
    counts <- matrix(rpois(100, lambda = 10), ncol=10, nrow=10)
    sce <- SingleCellExperiment(assays = list(counts = counts))
    sce

    ## -----------------------------------------------------------------------------
    # Function in package A:
    AsetX <- function(sce) {
        int_colData(sce)$X <- runif(ncol(sce))
        sce
    }

    # Function in package B:

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_singlecellexperiment_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_singlecellexperiment_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_singlecellexperiment_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SINGLECELLEXPERIMENT:", paste0("    singlecellexperiment: ", packageVersion("SingleCellExperiment"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_singlecellexperiment_results.csv
    touch ${prefix}_singlecellexperiment_output.rds
    echo "BIOC_SINGLECELLEXPERIMENT:" > versions.yml
    echo "    singlecellexperiment: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SINGLECELLEXPERIMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(singlecellexperiment) ]

    main:
    BIOC_SINGLECELLEXPERIMENT(ch_input)

    emit:
    results  = BIOC_SINGLECELLEXPERIMENT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SINGLECELLEXPERIMENT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SINGLECELLEXPERIMENT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SINGLECELLEXPERIMENT.out.versions  // channel: path(versions.yml)
}
