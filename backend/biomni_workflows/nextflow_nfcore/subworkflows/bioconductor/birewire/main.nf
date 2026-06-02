#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BiRewire
// Fast functions for bipartite network rewiring through N consecutive switching steps (See References)
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BiRewire/inst/doc/BiRewire.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("BiRewire")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIREWIRE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-birewire"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-birewire:3.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-birewire:3.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_birewire_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_birewire_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_birewire_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BiRewire)
    library(E)
    library(jsonlite)

    # --- Bipartite Rewiring and Analysis [] ---
    # Key functions: birewire.rewire.bipartite, birewire.analysis.bipartite
    data(BRCA_binary_matrix)
    m2 <- birewire.rewire.bipartite(BRCA_binary_matrix, verbose = FALSE)
    step <- 5000
    max_iter <- 100 * sum(BRCA_binary_matrix)
    scores <- birewire.analysis.bipartite(
        BRCA_binary_matrix,
        step,
        verbose = FALSE,
        max.iter = max_iter,
        n.networks = 5,
        display = FALSE
    )


    # --- Undirected Rewiring and Analysis [] ---
    # Key functions: birewire.rewire.undirected, birewire.analysis.undirected
    g_und <- igraph::erdos.renyi.game(
        directed = FALSE,
        loops = FALSE,
        n = 100,
        p.or.m = 0.1
    )
    m_und <- as.matrix(igraph::as_adjacency_matrix(g_und))
    m2_und <- birewire.rewire.undirected(m_und, verbose = FALSE)
    step <- 10
    max_iter <- 100 * length(igraph::E(g_und))
    scores_und <- birewire.analysis.undirected(
        m_und,
        step = step,
        verbose = FALSE,
        max.iter = max_iter,
        n.networks = 5
    )


    # --- Similarity Assessment [] ---
    # Key functions: birewire.similarity, birewire.rewire.bipartite
    data(BRCA_binary_matrix)
    m2 <- birewire.rewire.bipartite(BRCA_binary_matrix, verbose = FALSE)
    sc_direct <- birewire.similarity(BRCA_binary_matrix, m2)
    sc_transpose <- birewire.similarity(BRCA_binary_matrix, t(m2))


    # --- Projection Analysis [] ---
    # Key functions: birewire.rewire.bipartite.and.projections
    gg <- igraph::graph.bipartite(rep(0:1, length = 10), c(1:10))
    result <- birewire.rewire.bipartite.and.projections(
        gg,
        step = 10,
        max.iter = "n",
        accuracy = 0.00005,
        verbose = FALSE
    )


    # --- Visual Monitoring [] ---
    # Key functions: birewire.visual.monitoring.bipartite, birewire.visual.monitoring.undirected
    ggg <- igraph::graph.bipartite(rep(0:1, length = 10), c(1:10))
    tsne_bip <- birewire.visual.monitoring.bipartite(
        ggg,
        display = FALSE,
        n.networks = 10,
        perplexity = 2
    )
    g_und <- igraph::erdos.renyi.game(100, 0.1)
    tsne_und <- birewire.visual.monitoring.undirected(
        g_und,
        display = FALSE,
        n.networks = 10,
        perplexity = 2
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_birewire_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_birewire_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_birewire_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BIREWIRE:", paste0("    birewire: ", packageVersion("BiRewire"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_birewire_results.csv
    touch ${prefix}_birewire_output.rds
    echo "BIOC_BIREWIRE:" > versions.yml
    echo "    birewire: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BIREWIRE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BIREWIRE(ch_input)

    emit:
    results  = BIOC_BIREWIRE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BIREWIRE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BIREWIRE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BIREWIRE.out.versions  // channel: path(versions.yml)
}
