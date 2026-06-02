#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: parglms
// This package provides support for parallelized estimation of GLMs/GEEs, catering for dispersed data.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/parglms/inst/doc/parglms.R
// Upstream  : BatchJobs, GenomeInfoDb, GenomicRanges, MASS, gQTLBase
// Downstream: none
//
// Install: BiocManager::install("parglms")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PARGLMS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-parglms"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-parglms:1.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-parglms:1.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_parglms_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_parglms_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_parglms_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(parglms)
    library(jsonlite)

    # --- Job Execution [] ---
    # Key functions: submitJobs, waitForJobs, loadResult
    BatchJobs::submitJobs(
        reg = myr,
        progressbar = FALSE
    )
    BatchJobs::waitForJobs(reg = myr)
    res1 <- BatchJobs::loadResult(
        reg = myr,
        id = 1
    )


    # --- Parallel GLM Estimation [] ---
    # Key functions: parGLM
    pp <- parGLM(
        formula = Postwt ~ Treat + Prewt,
        registry = myr,
        family = gaussian,
        binit = c(0, 0, 0, 0),
        maxit = 10,
        tol = 0.001
    )
    coef_estimates <- pp$coef

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_parglms_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_parglms_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_parglms_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PARGLMS:", paste0("    parglms: ", packageVersion("parglms"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_parglms_results.csv
    touch ${prefix}_parglms_output.rds
    echo "BIOC_PARGLMS:" > versions.yml
    echo "    parglms: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PARGLMS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PARGLMS(ch_input)

    emit:
    results  = BIOC_PARGLMS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PARGLMS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PARGLMS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PARGLMS.out.versions  // channel: path(versions.yml)
}
