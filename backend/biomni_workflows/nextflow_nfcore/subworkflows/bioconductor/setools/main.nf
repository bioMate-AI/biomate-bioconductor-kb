#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SEtools
// This includes a set of convenience functions for working with the SummarizedExperiment class. Note t
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SEtools/inst/doc/SEtools.R
// Upstream  : SummarizedExperiment
// Downstream: none
//
// Install: BiocManager::install("SEtools")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SETOOLS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-setools"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-setools:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-setools:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_setools_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_setools_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_setools_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SEtools)
    library(jsonlite)

    # --- row Data [] ---
    # Key functions: rowData, mergeSEs, sechm
    rowData(se1)$metafeature <- sample(LETTERS,nrow(se1),replace = TRUE)
    rowData(se2)$metafeature <- sample(LETTERS,nrow(se2),replace = TRUE)
    se3 <- mergeSEs( list(se1=se1, se2=se2), do.scale=FALSE, mergeBy="metafeature", aggFun=median)
    # --- agg S E [] ---
    # Key functions: aggSE, log2FC
    se1b <- aggSE(se1, by = "metafeature")
    SE <- log2FC(SE, fromAssay="logcpm", controls=SE$Condition=="Homecage")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_setools_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_setools_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_setools_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SETOOLS:", paste0("    setools: ", packageVersion("SEtools"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_setools_results.csv
    touch ${prefix}_setools_output.rds
    echo "BIOC_SETOOLS:" > versions.yml
    echo "    setools: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SETOOLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SETOOLS(ch_input)

    emit:
    results  = BIOC_SETOOLS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SETOOLS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SETOOLS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SETOOLS.out.versions  // channel: path(versions.yml)
}
