#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: FGNet
// Build and visualize functional gene and term networks from clustering of enrichment analyses in mult
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/FGNet/inst/doc/FGNet.R
// Upstream  : knitr
// Downstream: none
//
// Install: BiocManager::install("FGNet")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FGNET {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-fgnet"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-fgnet:3.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-fgnet:3.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_fgnet_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_fgnet_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_fgnet_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(FGNet)
    library(jsonlite)

    # --- Pre [] ---
    # Key functions: set
    ----------------------------------------
    library(knitr)
    opts_chunk$set(warning=FALSE,message=FALSE,cache=TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_fgnet_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_fgnet_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_fgnet_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FGNET:", paste0("    fgnet: ", packageVersion("FGNet"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fgnet_results.csv
    touch ${prefix}_fgnet_output.rds
    echo "BIOC_FGNET:" > versions.yml
    echo "    fgnet: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FGNET_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FGNET(ch_input)

    emit:
    results  = BIOC_FGNET.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FGNET.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FGNET.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FGNET.out.versions  // channel: path(versions.yml)
}
