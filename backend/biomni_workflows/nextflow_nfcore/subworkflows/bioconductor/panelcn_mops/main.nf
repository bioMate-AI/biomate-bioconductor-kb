#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: panelcn.mops
// CNV detection tool for targeted NGS panel data. Extension of the cn.mops package.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/panelcn.mops/inst/doc/panelcn.mops.R
// Upstream  : knitr
// Downstream: none
//
// Install: BiocManager::install("panelcn.mops")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PANELCN_MOPS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-panelcn_mops"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-panelcn.mops:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-panelcn.mops:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_panelcn_mops_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_panelcn_mops_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_panelcn_mops_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(panelcn.mops)
    library(jsonlite)

    # --- Colnames [] ---
    # Key functions: elementMetadata, createResultTable
    ------------------------------------------------------
    sampleNames <- colnames(elementMetadata(test))
    # --- Integercopynumber [] ---
    # Key functions: integerCopyNumber
    ------------------------------------------------------
    integerCopyNumber(resultlist[[1]])[1:5]
    # --- Colnames [] ---
    # Key functions: elementMetadata, createResultTable
    ------------------------------------------------------
    sampleNames <- colnames(elementMetadata(test))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_panelcn_mops_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_panelcn_mops_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_panelcn_mops_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PANELCN_MOPS:", paste0("    panelcn_mops: ", packageVersion("panelcn.mops"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_panelcn_mops_results.csv
    touch ${prefix}_panelcn_mops_output.rds
    echo "BIOC_PANELCN_MOPS:" > versions.yml
    echo "    panelcn_mops: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PANELCN_MOPS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PANELCN_MOPS(ch_input)

    emit:
    results  = BIOC_PANELCN_MOPS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PANELCN_MOPS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PANELCN_MOPS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PANELCN_MOPS.out.versions  // channel: path(versions.yml)
}
