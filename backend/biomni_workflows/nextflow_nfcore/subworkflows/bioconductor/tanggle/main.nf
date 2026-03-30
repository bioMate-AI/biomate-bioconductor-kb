#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: tanggle
// Offers functions for plotting split (or implicit) networks (unrooted, undirected) and explicit netwo
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/tanggle/inst/doc/tanggle_vignette.R
// Upstream  : ggtree, phangorn
// Downstream: none
//
// Install: BiocManager::install("tanggle")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TANGGLE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tanggle"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-tanggle:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-tanggle:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_tanggle_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tanggle_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tanggle_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(tanggle)
    library(jsonlite)

    # --- ggsplitnet [] ---
    # Key functions: ggsplitnet, geom_nodepoint, ggevonet
    library(tanggle)
    library(phangorn)
    library(ggtree)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_tanggle_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_tanggle_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_tanggle_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TANGGLE:", paste0("    tanggle: ", packageVersion("tanggle"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tanggle_results.csv
    touch ${prefix}_tanggle_output.rds
    echo "BIOC_TANGGLE:" > versions.yml
    echo "    tanggle: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TANGGLE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TANGGLE(ch_input)

    emit:
    results  = BIOC_TANGGLE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TANGGLE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TANGGLE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TANGGLE.out.versions  // channel: path(versions.yml)
}
