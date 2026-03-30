#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: phenopath
// PhenoPath infers genomic trajectories (pseudotimes) in the presence of heterogeneous genetic and env
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/phenopath/inst/doc/introduction_to_phenopath.R
// Upstream  : SummarizedExperiment, dplyr, forcats, ggplot2, tidyr
// Downstream: none
//
// Install: BiocManager::install("phenopath")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PHENOPATH {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-phenopath"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-phenopath:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-phenopath:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_phenopath_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_phenopath_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_phenopath_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SummarizedExperiment)
    library(jsonlite)

    # --- Create SummarizedExperiment [] ---
    # Key functions: SummarizedExperiment
    suppressPackageStartupMessages(library(SummarizedExperiment))
    exprs_mat <- t(sim$y)
    pdata <- data.frame(x = sim$x)
    # --- Custom ggplot2 visualization [] ---
    # Key functions: as_tibble, gather, ggplot, geom_point, facet_wrap, data_frame, geom_errorbar, theme
    genes_to_extract <- c(1,3,11,13,21,23,31,33)
    expression_df <- as.data.frame(sim$y[,genes_to_extract])
    names(expression_df) <- paste0("gene_", genes_to_extract)
    # --- Simulate phenopath analysis [] ---
    # Key functions: simulate_phenopath, phenopath, qplot, xlab
    fit <- phenopath(sim$y, sim$x, z_init = 1) # 1, initialise to first principal component
    fit <- phenopath(sim$y, sim$x, z_init = sim$z) # 2, initialise to true values
    fit <- phenopath(sim$y, sim$x, z_init = "random") # 3, random initialisation

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_phenopath_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_phenopath_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_phenopath_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PHENOPATH:", paste0("    phenopath: ", packageVersion("phenopath"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_phenopath_results.csv
    touch ${prefix}_phenopath_output.rds
    echo "BIOC_PHENOPATH:" > versions.yml
    echo "    phenopath: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PHENOPATH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PHENOPATH(ch_input)

    emit:
    results  = BIOC_PHENOPATH.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PHENOPATH.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PHENOPATH.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PHENOPATH.out.versions  // channel: path(versions.yml)
}
