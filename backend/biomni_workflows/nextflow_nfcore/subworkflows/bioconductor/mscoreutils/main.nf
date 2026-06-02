#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MsCoreUtils
// MsCoreUtils defines low-level functions for mass spectrometry data and is independent of any high-le
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MsCoreUtils/inst/doc/MsCoreUtils.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("MsCoreUtils")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MSCOREUTILS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mscoreutils"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mscoreutils:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mscoreutils:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mscoreutils_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mscoreutils_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mscoreutils_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MsCoreUtils)
    library(jsonlite)


    # --- Block 1 [] ---
    # Key functions: mscoreutils
    library("MsCoreUtils")
    ls(pos = "package:MsCoreUtils")

    # --- Block 3 [] ---
    # Key functions: rnorm
    x <- matrix(rnorm(30), nrow = 3)
    colnames(x) <- letters[1:10]
    rownames(x) <- LETTERS[1:3]
    x

    # --- Block 5 [] ---
    # Key functions: robustSummary
    robustSummary(x)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mscoreutils_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mscoreutils_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mscoreutils_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MSCOREUTILS:", paste0("    mscoreutils: ", packageVersion("MsCoreUtils"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mscoreutils_results.csv
    touch ${prefix}_mscoreutils_output.rds
    echo "BIOC_MSCOREUTILS:" > versions.yml
    echo "    mscoreutils: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MSCOREUTILS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MSCOREUTILS(ch_input)

    emit:
    results  = BIOC_MSCOREUTILS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MSCOREUTILS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MSCOREUTILS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MSCOREUTILS.out.versions  // channel: path(versions.yml)
}
