#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MetNet
// MetNet contains functionality to infer metabolic network topologies from quantitative data and high-
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MetNet/inst/doc/MetNet.R
// Upstream  : MsCoreUtils, Spectra, knitr
// Downstream: none
//
// Install: BiocManager::install("MetNet")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METNET {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-metnet"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-metnet:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-metnet:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_metnet_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_metnet_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_metnet_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MetNet)
    library(jsonlite)


    # --- Env [] ---
    # Key functions: set, suppressPackageStartupMessages, x_test, Hydroxylation, group, ribose, Rhamnose, Monosaccharide
    library("knitr")
    opts_chunk$set(stop_on_error = 1L)
    suppressPackageStartupMessages(library("MetNet"))
    data("x_test", package = "MetNet")
    x_test <- as.matrix(x_test)
    ## define the search space for biochemical transformation 
    # --- Structure [] ---
    # Key functions: structural, group, formula, mass, graph_from_adjacency_matrix, assay, binary, directed
    struct_adj <- structural(x = x_test, transformation = transformations, 
        var = c("group", "formula", "mass"), ppm = 10)
    struct_adj_dir <- structural(x = x_test, transformation = transformations, 
        var = c("group", "formula", "mass"), ppm = 10, directed = TRUE)
    g_undirected <- igraph::graph_from_adjacency_matrix(
        assay(struct_adj, "binary"), mode = "directed", weighted = NULL)
    plot(g_undirected, edge.width = 1, edge.arrow.size = 0.5,
         vertex.label.cex = 0.5, edge.color = "grey")
    g_directed <- igraph::graph_from_adjacency_matrix(
        assay(struct_adj_dir, "binary"), mode = "directed", weighted = NULL)
    plot(g_directed, edge.width = 1, edge.arrow.size = 0.5,
         vertex.label.cex = 0.5, edge.color = "grey")

    # --- Rt Correction [] ---
    # Key functions: rtCorrection, group, mz_summary, mz_vis
    struct_adj <- rtCorrection(am = struct_adj, x = x_test, 
        transformation = transformations, var = "group")
    struct_df <- as.data.frame(struct_adj)
    struct_df <- struct_df[struct_df$binary == 1, ]
    mz_sum <- mz_summary(struct_adj, var = "group")
    mz_vis(mz_sum, var = "group")

    # --- Mz Summary Filter [] ---
    # Key functions: mz_summary, rowData, x_annotation, x1856, readRDS, compareSpectra, addSpectralSimilarity, ndotproduct
    mz_summary(struct_adj, filter = 4)
    mz_summary(struct_adj, filter = 5)
    data("x_annotation", package = "MetNet")
    x_annotation <- as.data.frame(x_annotation)

    ## add annotations to the structural AdjacencyMatrix object
    rowData(struct_adj) <- x_annotation

    ## display annotation for the feature "1856"
    rowData(struct_adj)["x1856", ]
    # required for ndotproduct calculus
    library(MsCoreUtils)
    library(Spectra)

    ## create spectral similarity matrix
    f <- system.file("spectra_matrix/ms2_test.RDS", package = "MetNet")
    sps_sub <- readRDS(f)

    adj_spec <- Spectra::compareSpectra(sps_sub, FUN = ndotproduct)
    colnames(adj_spec) <- sps_sub$id

    # --- Threshold Structural [] ---
    # Key functions: assayNames, threshold, statistical, pearson, spearman, top1, top2
    ## the assayNames in spect_adj are used to define the filter criteria
    assayNames(spect_adj)

    ## return edges with normalized dotproduct > 0.10
    args_thr <- list(filter = "ndotproduct > 0.1")

    ## return edges with normalized dotproduct > 0.10, even if no mass-difference 
    ## was detected between pairs of features
    args_thr <- list(filter = "ndotproduct > 0.1 | binary == 1 & is.na(ndotproduct)")

    x_int <- x_test[, 3:ncol(x_test)] |>
        as.matrix()
    stat_adj <- statistical(x_int, model = c("pearson", "spearman"))
    ## type = "threshold" 

    ## the assayNames in stat_adj are used to define the filter criteria
    assayNames(stat_adj)

    ## return edges with positive Pearson correlation coefficients > 0.95
    args_thr <- list(filter = "pearson_coef > 0.95")

    # --- Combine [] ---
    # Key functions: combine, assay, graph_from_adjacency_matrix, combine_binary, undirected, grey
    comb_adj <- combine(am_structural = struct_adj, am_statistical = stat_adj_mean)
    comb_spect_adj <- combine(am_structural = spect_adj_thr, 
                              am_statistical = stat_adj_mean)
    adj <- assay(comb_adj, "combine_binary")
    g <- igraph::graph_from_adjacency_matrix(adj, mode = "undirected")
    plot(g, edge.width = 2, vertex.label.cex = 0.5, edge.color = "grey")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_metnet_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_metnet_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_metnet_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_METNET:", paste0("    metnet: ", packageVersion("MetNet"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_metnet_results.csv
    touch ${prefix}_metnet_output.rds
    echo "BIOC_METNET:" > versions.yml
    echo "    metnet: 0.0.0" >> versions.yml
    """
}


workflow BIOC_METNET_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_METNET(ch_input)

    emit:
    results  = BIOC_METNET.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_METNET.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_METNET.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_METNET.out.versions  // channel: path(versions.yml)
}
