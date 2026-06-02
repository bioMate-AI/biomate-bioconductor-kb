#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: sccomp
// A robust and outlier-aware method for testing differential tissue composition from single-cell data.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/sccomp/inst/doc/introduction.R
// Upstream  : bayesplot, cmdstanr, dplyr, forcats, ggplot2
// Downstream: none
//
// Install: BiocManager::install("sccomp")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCCOMP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sccomp"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-sccomp:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-sccomp:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_sccomp_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sccomp_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sccomp_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(sccomp)
    library(jsonlite)


    # --- Eval = Instantiate::stan Cmdstan Exists() [] ---
    # Key functions: sccomp_estimate, as_tibble
    #  
    #  res =
    #      seurat_obj |>
    #      sccomp_estimate(
    #        formula_composition = ~ type + continuous_covariate,
    #        .sample = sample, .cell_group = cell_group,
    #        cores = 1, verbose=FALSE
    #      )
    #  
    #  res

    ## -----------------------------------------------------------------------------
    seurat_obj[[]] |> as_tibble()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_sccomp_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_sccomp_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_sccomp_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCCOMP:", paste0("    sccomp: ", packageVersion("sccomp"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sccomp_results.csv
    touch ${prefix}_sccomp_output.rds
    echo "BIOC_SCCOMP:" > versions.yml
    echo "    sccomp: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCCOMP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SCCOMP(ch_input)

    emit:
    results  = BIOC_SCCOMP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCCOMP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCCOMP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCCOMP.out.versions  // channel: path(versions.yml)
}
