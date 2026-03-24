#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: famat
// Famat is made to collect data about lists of genes and metabolites provided by user, and to visualiz
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/famat/inst/doc/famat.R
// Upstream  : mgcv
// Downstream: none
//
// Install: BiocManager::install("famat")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FAMAT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-famat"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-famat:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-famat:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_famat_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_famat_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_famat_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(famat)
    library(jsonlite)

    # --- compl_data [] ---
    # Key functions: compl_data
    data(interactions_result)
    compl_data_result <- compl_data(interactions_result)
    # --- path_enrich [] ---
    # Key functions: path_enrich, interactions, compl_data, rshiny
    data(genes)
    data(meta)
    listk <- path_enrich("KEGG", meta, genes)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_famat_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_famat_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_famat_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FAMAT:", paste0("    famat: ", packageVersion("famat"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_famat_results.csv
    touch ${prefix}_famat_output.rds
    echo "BIOC_FAMAT:" > versions.yml
    echo "    famat: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FAMAT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FAMAT(ch_input)

    emit:
    results  = BIOC_FAMAT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FAMAT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FAMAT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FAMAT.out.versions  // channel: path(versions.yml)
}
