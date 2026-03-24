#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MBAmethyl
// This package provides a function for reconstructing DNA methylation values from raw measurements. It
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MBAmethyl/inst/doc/MBAmethyl.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("MBAmethyl")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MBAMETHYL {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mbamethyl"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mbamethyl:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mbamethyl:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(plot_object)

    output:
    tuple val(meta), path("${meta.id}_mbamethyl_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mbamethyl_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mbamethyl_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MBAmethyl)
    library(jsonlite)

    # --- Numeric [] ---
    # Key functions: runif
    p <- 80
      n <- 40
      K <- 2
      k <- K - 1
      cp <- numeric()
    # --- Mbamethyl [] ---
    # Key functions: MBAmethyl
    library(MBAmethyl)
     fit <- MBAmethyl(Y, steps = 30)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mbamethyl_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mbamethyl_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mbamethyl_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MBAMETHYL:", paste0("    mbamethyl: ", packageVersion("MBAmethyl"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mbamethyl_results.csv
    touch ${prefix}_mbamethyl_output.rds
    echo "BIOC_MBAMETHYL:" > versions.yml
    echo "    mbamethyl: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MBAMETHYL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(plot_object) ]

    main:
    BIOC_MBAMETHYL(ch_input)

    emit:
    results  = BIOC_MBAMETHYL.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MBAMETHYL.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MBAMETHYL.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MBAMETHYL.out.versions  // channel: path(versions.yml)
}
