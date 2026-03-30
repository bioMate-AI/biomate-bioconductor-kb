#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: biocroxytest
// This package provides a roclet for roxygen2 that identifies and processes code blocks in your docume
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/biocroxytest/inst/doc/biocroxytest.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("biocroxytest")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIOCROXYTEST {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-biocroxytest"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-biocroxytest:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-biocroxytest:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_biocroxytest_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_biocroxytest_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_biocroxytest_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(biocroxytest)
    library(jsonlite)

    # --- Use Longtests [] ---
    # Key functions: use_longtests
    ---------------------------------------------------------------------
    # Create the longtests directory and .BBSoptions file
    biocroxytest::use_longtests()
    # --- Expect Equal [] ---
    # Key functions: expect_equal, foo, expect_error
    ---------------------------------------------------------------------
    #' A function to do x
    #'
    #' @param x A number
    #'

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_biocroxytest_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_biocroxytest_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_biocroxytest_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BIOCROXYTEST:", paste0("    biocroxytest: ", packageVersion("biocroxytest"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biocroxytest_results.csv
    touch ${prefix}_biocroxytest_output.rds
    echo "BIOC_BIOCROXYTEST:" > versions.yml
    echo "    biocroxytest: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BIOCROXYTEST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BIOCROXYTEST(ch_input)

    emit:
    results  = BIOC_BIOCROXYTEST.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BIOCROXYTEST.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BIOCROXYTEST.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BIOCROXYTEST.out.versions  // channel: path(versions.yml)
}
