#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: mia
// mia implements tools for microbiome analysis based on the SummarizedExperiment, SingleCellExperiment
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/mia/inst/doc/mia.R
// Upstream  : MultiAssayExperiment, phyloseq, scater
// Downstream: miaViz
//
// Install: BiocManager::install("mia")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MIA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mia"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mia:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mia:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mia_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mia_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mia_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(mia)
    library(jsonlite)


    # --- Eval=false [] ---
    # Key functions: requireNamespace, install, rowData, mia
    #  if (!requireNamespace("BiocManager", quietly = TRUE))
    #      install.packages("BiocManager")
    #  BiocManager::install("mia")

    ## ----load-packages, message=FALSE, warning=FALSE------------------------------
    library("mia")

    ## -----------------------------------------------------------------------------
    data(GlobalPatterns, package = "mia")
    tse <- GlobalPatterns
    tse

    ## -----------------------------------------------------------------------------
    # print the available taxonomic ranks
    colnames(rowData(tse))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mia_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mia_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mia_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MIA:", paste0("    mia: ", packageVersion("mia"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mia_results.csv
    touch ${prefix}_mia_output.rds
    echo "BIOC_MIA:" > versions.yml
    echo "    mia: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MIA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MIA(ch_input)

    emit:
    results  = BIOC_MIA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MIA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MIA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MIA.out.versions  // channel: path(versions.yml)
}
