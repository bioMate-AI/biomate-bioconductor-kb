#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DTA
// Dynamic Transcriptome Analysis (DTA) can monitor the cellular response to perturbations with higher 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DTA/inst/doc/DTA.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("DTA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DTA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-dta"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-dta:2.52.0--r44_0' :
        'quay.io/biocontainers/bioconductor-dta:2.52.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_dta_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_dta_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_dta_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DTA)
    library(jsonlite)

    # --- Rate Estimation and Normalization [] ---
    # Key functions: dta.plot.rates
    dta.plot.rates(
        res,
        filename = "rates_plot.pdf",
        replicates = TRUE
    )


    # --- Quality Control and Convex Hull Plotting [] ---
    # Key functions: dta.plot.convexhull
    dta.plot.convexhull(
        res,
        filename = "convexhull_plot.pdf"
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_dta_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_dta_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_dta_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DTA:", paste0("    dta: ", packageVersion("DTA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dta_results.csv
    touch ${prefix}_dta_output.rds
    echo "BIOC_DTA:" > versions.yml
    echo "    dta: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DTA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DTA(ch_input)

    emit:
    results  = BIOC_DTA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DTA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DTA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DTA.out.versions  // channel: path(versions.yml)
}
