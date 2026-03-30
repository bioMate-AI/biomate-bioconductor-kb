#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: flowMeans
// Identifies cell populations in Flow Cytometry data using non-parametric clustering and segmented-reg
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/flowMeans/inst/doc/flowMeans.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("flowMeans")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FLOWMEANS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-flowmeans"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-flowmeans:1.66.0--r44_0' :
        'quay.io/biocontainers/bioconductor-flowmeans:1.66.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_flowmeans_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_flowmeans_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_flowmeans_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(flowMeans)
    library(jsonlite)

    # --- Stage1 [] ---
    # Key functions: flowMeans
    data(x)
    res <- flowMeans(x, varNames=c("FL1.H", "FL2.H", "FL3.H", "FL4.H"),
                     MaxN=10)
    # --- Stage4 [] ---
    # Key functions: changepointDetection
    plot(res@Mins, xlab=' ', ylab=' ', xlim=c(1, res@MaxN),
         ylim=c(0, max(res@Mins)))
    ft<-changepointDetection(res@Mins)
    abline(ft$l1)
    abline(ft$l2);

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_flowmeans_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_flowmeans_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_flowmeans_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FLOWMEANS:", paste0("    flowmeans: ", packageVersion("flowMeans"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_flowmeans_results.csv
    touch ${prefix}_flowmeans_output.rds
    echo "BIOC_FLOWMEANS:" > versions.yml
    echo "    flowmeans: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FLOWMEANS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FLOWMEANS(ch_input)

    emit:
    results  = BIOC_FLOWMEANS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FLOWMEANS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FLOWMEANS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FLOWMEANS.out.versions  // channel: path(versions.yml)
}
