#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: weaver
// This package provides enhancements on the Sweave() function in the base package.  In particular a fa
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/weaver/inst/doc/weaver_howTo.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("weaver")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_WEAVER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-weaver"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-weaver:1.72.0--r44_0' :
        'quay.io/biocontainers/bioconductor-weaver:1.72.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_weaver_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_weaver_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_weaver_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Sweave)
    library(jsonlite)

    # --- Basicproc [] ---
    # Key functions: tempdir, output, Sweave, weaver
    library("weaver")
    testDocPath <- system.file("extdata/doc1.Rnw", package="weaver")
    curDir <- getwd()
    setwd(tempdir())
    z <- capture.output(Sweave(testDocPath, driver=weaver()),
    # --- Another [] ---
    # Key functions: tempdir, output, Sweave, weaver, tempfile
    testDocPath <- system.file("extdata/doc2.Rnw", package="weaver")
    curDir <- getwd()
    setwd(tempdir())
    z <- capture.output(Sweave(testDocPath, driver=weaver()),
                        file=tempfile())
    # --- Again [] ---
    # Key functions: tempdir, output, Sweave, weaver, tempfile
    testDocPath <- system.file("extdata/doc1.Rnw", package="weaver")
    curDir <- getwd()
    setwd(tempdir())
    z <- capture.output(Sweave(testDocPath, driver=weaver()),
                        file=tempfile())

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_weaver_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_weaver_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_weaver_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_WEAVER:", paste0("    weaver: ", packageVersion("weaver"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_weaver_results.csv
    touch ${prefix}_weaver_output.rds
    echo "BIOC_WEAVER:" > versions.yml
    echo "    weaver: 0.0.0" >> versions.yml
    """
}


workflow BIOC_WEAVER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_WEAVER(ch_input)

    emit:
    results  = BIOC_WEAVER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_WEAVER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_WEAVER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_WEAVER.out.versions  // channel: path(versions.yml)
}
