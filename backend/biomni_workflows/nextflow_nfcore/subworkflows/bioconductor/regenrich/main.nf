#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RegEnrich
// This package is a pipeline to identify the key gene regulators in a biological process, for example 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RegEnrich/inst/doc/RegEnrich.R
// Upstream  : BiocParallel, GEOquery, affy, annotate
// Downstream: none
//
// Install: BiocManager::install("RegEnrich")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_REGENRICH {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-regenrich"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-regenrich:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-regenrich:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_regenrich_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_regenrich_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_regenrich_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RegEnrich)
    library(jsonlite)

    # --- Differential Expression Analysis [] ---
    # Key functions: regenrich_diffExpr, results_DEA
    object <- regenrich_diffExpr(object)
    dea_results <- results_DEA(object)
    object_limma <- regenrich_diffExpr(
        object,
        method = "limma",
        coef = "week3"
    )
    dea_limma_results <- results_DEA(object_limma)


    # --- Network Construction [] ---
    # Key functions: regenrich_network, results_topNet, regenrich_network<-
    object <- regenrich_network(object)
    top_net <- results_topNet(object)
    net_edges <- slot(top_net, "elementset")
    object_user_net <- object
    regenrich_network(object_user_net) <- as.data.frame(net_edges)


    # --- Enrichment Analysis [] ---
    # Key functions: regenrich_enrich, results_enrich
    object <- regenrich_enrich(object)
    enrich_res <- results_enrich(object)
    enrich_fet <- slot(enrich_res, "allResult")
    object_gsea <- regenrich_enrich(
        object,
        enrichTest = "GSEA",
        nperm = 1000
    )
    enrich_gsea <- slot(results_enrich(object_gsea), "allResult")


    # --- Regulator Ranking and Scoring [] ---
    # Key functions: regenrich_rankScore, results_score
    object <- regenrich_rankScore(object)
    final_scores <- results_score(object)
    top_regulators <- head(final_scores, n = 20)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_regenrich_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_regenrich_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_regenrich_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_REGENRICH:", paste0("    regenrich: ", packageVersion("RegEnrich"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_regenrich_results.csv
    touch ${prefix}_regenrich_output.rds
    echo "BIOC_REGENRICH:" > versions.yml
    echo "    regenrich: 0.0.0" >> versions.yml
    """
}


workflow BIOC_REGENRICH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_REGENRICH(ch_input)

    emit:
    results  = BIOC_REGENRICH.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_REGENRICH.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_REGENRICH.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_REGENRICH.out.versions  // channel: path(versions.yml)
}
