#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: sigsquared
// By leveraging statistical properties (log-rank test for survival) of patient cohorts defined by bina
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/sigsquared/inst/doc/sigsquared.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("sigsquared")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SIGSQUARED {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sigsquared"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-sigsquared:1.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-sigsquared:1.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_sigsquared_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sigsquared_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sigsquared_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Surv)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    library(sigsquared)
    data(BrCa443)
    # --- Analysispipeline [] ---
    # Key functions: analysisPipeline
    gs <- analysisPipeline(dataSet=BrCa443, geneSig=gs, iterPerK=50, k=2, rand=FALSE)
    # --- Ensembleadjustable [] ---
    # Key functions: ensembleAdjustable, survfit, Surv, pData
    s <- ensembleAdjustable(dataSet=BrCa443, geneSig=gs)
    plot(survfit(Surv(MFS, met) ~ s, data=pData(BrCa443)))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_sigsquared_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_sigsquared_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_sigsquared_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SIGSQUARED:", paste0("    sigsquared: ", packageVersion("sigsquared"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sigsquared_results.csv
    touch ${prefix}_sigsquared_output.rds
    echo "BIOC_SIGSQUARED:" > versions.yml
    echo "    sigsquared: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SIGSQUARED_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SIGSQUARED(ch_input)

    emit:
    results  = BIOC_SIGSQUARED.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SIGSQUARED.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SIGSQUARED.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SIGSQUARED.out.versions  // channel: path(versions.yml)
}
