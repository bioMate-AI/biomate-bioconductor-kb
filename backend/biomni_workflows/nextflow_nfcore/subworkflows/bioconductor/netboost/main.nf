#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: netboost
// Boosting supported network analysis for high-dimensional omics applications. This package comes bund
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/netboost/inst/doc/netboost.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("netboost")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NETBOOST {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-netboost"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-netboost:2.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-netboost:2.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_netboost_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_netboost_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_netboost_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(netboost)
    library(jsonlite)

    # --- netboost [] ---
    # Key functions: netboost
    results <- netboost(datan = tcga_aml_meth_rna_chr18, stepno = 20L,
    # --- nb_plot_dendro [] ---
    # Key functions: nb_plot_dendro
    set.seed(123)
    nb_plot_dendro(nb_summary = results, labels = FALSE, colorsrandom = TRUE)
    # --- nb_transfer [] ---
    # Key functions: nb_transfer, all
    ME_transfer <- nb_transfer(nb_summary = results,
    all(round(results$MEs, 10) == round(ME_transfer, 10))
    # --- robust netboost run [] ---
    # Key functions: netboost
    results <- netboost(datan = tcga_aml_meth_rna_chr18,cores=10L,

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_netboost_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_netboost_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_netboost_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_NETBOOST:", paste0("    netboost: ", packageVersion("netboost"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_netboost_results.csv
    touch ${prefix}_netboost_output.rds
    echo "BIOC_NETBOOST:" > versions.yml
    echo "    netboost: 0.0.0" >> versions.yml
    """
}


workflow BIOC_NETBOOST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_NETBOOST(ch_input)

    emit:
    results  = BIOC_NETBOOST.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_NETBOOST.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_NETBOOST.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_NETBOOST.out.versions  // channel: path(versions.yml)
}
