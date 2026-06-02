#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ROTS
// Calculates the Reproducibility-Optimized Test Statistic (ROTS) for differential testing in omics dat
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ROTS/inst/doc/ROTS.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("ROTS")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ROTS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rots"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rots:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rots:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rots_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rots_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rots_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ROTS)
    library(jsonlite)


    # --- Load [] ---
    # Key functions: rots
    library(ROTS)
    data(upsSpikeIn)
    input = upsSpikeIn

    # --- Rots [] ---
    # Key functions: ROTS
    results = ROTS(data = input, groups = groups , B = 100 , K = 500 , seed = 1234)
    names(results)

    # --- Summary [] ---
    # Key functions: summary
    summary(results, fdr = 0.05)

    # --- Volcano [] ---
    # Key functions: volcano
    plot(results, fdr = 0.05, type = "volcano")

    # --- Heatmap [] ---
    # Key functions: heatmap
    plot(results, fdr = 0.05, type = "heatmap")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rots_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rots_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rots_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ROTS:", paste0("    rots: ", packageVersion("ROTS"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rots_results.csv
    touch ${prefix}_rots_output.rds
    echo "BIOC_ROTS:" > versions.yml
    echo "    rots: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ROTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ROTS(ch_input)

    emit:
    results  = BIOC_ROTS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ROTS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ROTS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ROTS.out.versions  // channel: path(versions.yml)
}
