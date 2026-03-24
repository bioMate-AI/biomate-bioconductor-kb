#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: reconsi
// Improves simultaneous inference under dependence of tests by estimating a collapsed null distributio
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/reconsi/inst/doc/reconsiVignette.R
// Upstream  : BiocManager, devtools
// Downstream: none
//
// Install: BiocManager::install("reconsi")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RECONSI {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-reconsi"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-reconsi:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-reconsi:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_reconsi_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_reconsi_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_reconsi_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(reconsi)
    library(jsonlite)

    # --- plot Approx Covar [] ---
    # Key functions: plotApproxCovar
    plotApproxCovar(fdrRes)
    # --- plot Covar [] ---
    # Key functions: plotCovar
    matBlock[x==0,] = matBlock[x==0,] + rep(c(-1,2), each = n*p/4)
    fdrResBlock = reconsi(matBlock, x)
    plotCovar(fdrResBlock)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_reconsi_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_reconsi_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_reconsi_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RECONSI:", paste0("    reconsi: ", packageVersion("reconsi"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_reconsi_results.csv
    touch ${prefix}_reconsi_output.rds
    echo "BIOC_RECONSI:" > versions.yml
    echo "    reconsi: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RECONSI_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RECONSI(ch_input)

    emit:
    results  = BIOC_RECONSI.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RECONSI.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RECONSI.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RECONSI.out.versions  // channel: path(versions.yml)
}
