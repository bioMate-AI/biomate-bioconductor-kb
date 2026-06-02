#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SANTA
// This package provides methods for measuring the strength of association between a network and a phen
//
// Source : https://bioconductor.org/packages/3.20/bioc/https://bioconductor.org/packages/3.20/bioc/vignettes/SANTA/inst/doc/SANTA-vignette.html
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("SANTA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SANTA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-santa"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-santa:2.42.0--r44_0' :
        'quay.io/biocontainers/bioconductor-santa:2.42.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_santa_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_santa_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_santa_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SANTA)
    library(BinGraph)
    library(DistGraph)
    library(Knet)
    library(jsonlite)

    # --- Spatial Binning [] ---
    # Key functions: DistGraph, BinGraph
    g <- igraph::make_ring(50)
    igraph::V(g)$name <- as.character(1:50)
    D <- DistGraph(g, dist.method="shortest.paths", verbose=FALSE)
    B <- BinGraph(D, verbose=FALSE)


    # --- Gene Set Clustering Analysis [] ---
    # Key functions: Knet
    g <- igraph::make_ring(50)
    igraph::V(g)$name <- as.character(1:50)
    igraph::V(g)$phenotype <- rnorm(50)
    res <- Knet(g, nperm=100, dist.method="shortest.paths",
                vertex.attr="phenotype", verbose=FALSE)
    p_val <- res$pval


    # --- Differential Clustering Analysis [] ---
    # Key functions: Knet
    g1 <- igraph::make_ring(50)
    igraph::V(g1)$name <- as.character(1:50)
    igraph::V(g1)$phenotype <- rnorm(50)
    g2 <- igraph::make_ring(50)
    igraph::V(g2)$name <- as.character(1:50)
    igraph::V(g2)$phenotype <- rnorm(50)
    networks <- list(net1=g1, net2=g2)
    results <- sapply(networks, function(g) {
        Knet(g, nperm=50, dist.method="shortest.paths",
             vertex.attr="phenotype", verbose=FALSE)
    }, simplify=FALSE)
    p.values <- sapply(results, function(res) res$pval)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_santa_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_santa_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_santa_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SANTA:", paste0("    santa: ", packageVersion("SANTA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_santa_results.csv
    touch ${prefix}_santa_output.rds
    echo "BIOC_SANTA:" > versions.yml
    echo "    santa: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SANTA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SANTA(ch_input)

    emit:
    results  = BIOC_SANTA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SANTA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SANTA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SANTA.out.versions  // channel: path(versions.yml)
}
