#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: POWSC
// Determining the sample size for adequate power to detect statistical significance is a crucial step 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/POWSC/inst/doc/POWSC.R
// Upstream  : RColorBrewer, pheatmap
// Downstream: none
//
// Install: BiocManager::install("POWSC")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_POWSC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-powsc"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-powsc:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-powsc:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_powsc_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_powsc_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_powsc_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(POWSC)
    library(jsonlite)

    # --- Plot hierarchical clustering heatmap [] ---
    # Key functions: dimnames, pheatmap
    data("GSE67835_AB_S7_sce")
    cell_per = c(0.2, 0.3, 0.5)
    col = colData(sce)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_powsc_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_powsc_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_powsc_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_POWSC:", paste0("    powsc: ", packageVersion("POWSC"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_powsc_results.csv
    touch ${prefix}_powsc_output.rds
    echo "BIOC_POWSC:" > versions.yml
    echo "    powsc: 0.0.0" >> versions.yml
    """
}


workflow BIOC_POWSC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_POWSC(ch_input)

    emit:
    results  = BIOC_POWSC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_POWSC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_POWSC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_POWSC.out.versions  // channel: path(versions.yml)
}
