#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CaDrA
// Performs both stepwise and backward heuristic search for candidate (epi)genetic drivers based on a b
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CaDrA/inst/doc/permutation_based_testing.R
// Upstream  : SummarizedExperiment, devtools, pheatmap
// Downstream: none
//
// Install: BiocManager::install("CaDrA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CADRA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cadra"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cadra:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cadra:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cadra_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cadra_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cadra_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CaDrA)
    library(jsonlite)

    # --- set.up [] ---
    # Key functions: load_all
    knitr::opts_chunk$set(message=FALSE, collapse = TRUE, comment="")
    library(devtools)
    load_all()
    # --- candidate_search [] ---
    # Key functions: candidate_search
    candidate_search_res <- CaDrA::candidate_search(
    # --- topn_best [] ---
    # Key functions: topn_best, meta_plot, CaDrA
    topn_best_meta <- CaDrA::topn_best(topn_list = candidate_search_res)
    CaDrA::meta_plot(topn_best_list = topn_best_meta)
    set.seed(123)
    # --- ks.permutation.plot [] ---
    # Key functions: permutation_plot
    permutation_plot(perm_res = perm_res)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cadra_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cadra_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cadra_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CADRA:", paste0("    cadra: ", packageVersion("CaDrA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cadra_results.csv
    touch ${prefix}_cadra_output.rds
    echo "BIOC_CADRA:" > versions.yml
    echo "    cadra: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CADRA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CADRA(ch_input)

    emit:
    results  = BIOC_CADRA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CADRA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CADRA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CADRA.out.versions  // channel: path(versions.yml)
}
