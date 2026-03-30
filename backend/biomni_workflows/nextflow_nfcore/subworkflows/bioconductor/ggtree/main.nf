#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ggtree
// 'ggtree' extends the 'ggplot2' plotting system which implemented the grammar of graphics. 'ggtree' i
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ggtree/inst/doc/ggtree.R
// Upstream  : none
// Downstream: ggtreeDendro, tanggle
//
// Install: BiocManager::install("ggtree")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GGTREE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ggtree"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ggtree:3.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ggtree:3.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ggtree_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ggtree_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ggtree_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ggtree)
    library(jsonlite)

    # --- kable [] ---
    # Key functions: kable
    treeman <- matrix(c(
    treeman <- as.data.frame(treeman)
    colnames(treeman) <- c("Function", "Descriptiotn")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ggtree_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ggtree_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ggtree_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GGTREE:", paste0("    ggtree: ", packageVersion("ggtree"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ggtree_results.csv
    touch ${prefix}_ggtree_output.rds
    echo "BIOC_GGTREE:" > versions.yml
    echo "    ggtree: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GGTREE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GGTREE(ch_input)

    emit:
    results  = BIOC_GGTREE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GGTREE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GGTREE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GGTREE.out.versions  // channel: path(versions.yml)
}
