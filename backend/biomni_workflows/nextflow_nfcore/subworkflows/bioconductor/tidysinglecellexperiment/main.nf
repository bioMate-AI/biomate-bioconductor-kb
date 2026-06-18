#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: tidySingleCellExperiment
// 'tidySingleCellExperiment' is an adapter that abstracts the 'SingleCellExperiment' container in the 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/tidySingleCellExperiment/inst/doc/introduction.R
// Upstream  : GGally, Matrix, SingleCellSignalR, SingleR, celldex
// Downstream: tidySpatialExperiment
//
// Install: BiocManager::install("tidySingleCellExperiment")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_TIDYSINGLECELLEXPERIMENT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tidysinglecellexperiment"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_tidysinglecellexperiment_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tidysinglecellexperiment_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tidysinglecellexperiment_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("tidySingleCellExperiment", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }
    library(tidySingleCellExperiment)
    library(jsonlite)

    # --- Custom ggplot2 visualization [] ---
    # Key functions: ggplot, geom_histogram
    ggplot(aes(nFeature_RNA, fill=groups)) +
    geom_histogram() +
    # --- Custom ggplot2 visualization [] ---
    # Key functions: ggplot, geom_boxplot, geom_jitter, join_features, scale_y_log10
    ggplot(aes(groups, nCount_RNA, fill=groups)) +
    geom_boxplot(outlier.shape=NA) +
    geom_jitter(width=0.1) +
    # --- Run PCA [] ---
    # Key functions: modelGeneVar, getTopHVGs, runPCA
    modelGeneVar() %>%
    getTopHVGs(prop=0.1)
    runPCA(subset_row=variable_genes)
    # --- as_tibble [] ---
    # Key functions: as_tibble, ggpairs
    as_tibble() %>%
    select(contains("PC"), everything()) %>%
    GGally::ggpairs(columns=1:5, aes(colour=groups)) +
    # --- Build SNN graph for clustering [] ---
    # Key functions: colLabels, buildSNNGraph, cluster_walktrap
    colLabels(pbmc_small_cluster) <-
    buildSNNGraph(use.dimred="PCA") %>%
    igraph::cluster_walktrap() %\$%
    # --- count [] ---
    # Key functions: count, findMarkers, map, unlist, join_features
    count(groups, label)
    findMarkers(groups=pbmc_small_cluster\$label) %>%
    as.list() %>%
    # --- Run UMAP embedding [] ---
    # Key functions: runUMAP
    runUMAP(ncomponents=3)

    # --- Save outputs ---
    .objs <- setdiff(ls(), c("args", "prefix", ".objs"))
    .cells <- function(v) { x <- tryCatch(get(v), error = function(e) NULL)
                            if (is.data.frame(x) || is.matrix(x)) prod(dim(x)) else -1 }
    .dfs  <- Filter(function(v) is.data.frame(tryCatch(get(v), error = function(e) NULL)), .objs)
    .tabs <- Filter(function(v) { x <- tryCatch(get(v), error = function(e) NULL)
                                  is.data.frame(x) || is.matrix(x) }, .objs)
    .cand <- if (length(.dfs) > 0) .dfs else .tabs
    if (length(.cand) > 0) {
        .main <- get(.cand[[ which.max(sapply(.cand, .cells)) ]])
        write.csv(as.data.frame(.main), "${prefix}_tidysinglecellexperiment_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_tidysinglecellexperiment_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_tidysinglecellexperiment_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_TIDYSINGLECELLEXPERIMENT:", paste0("    tidysinglecellexperiment: ", as.character(packageVersion("tidySingleCellExperiment")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tidysinglecellexperiment_results.csv
    touch ${prefix}_tidysinglecellexperiment_output.rds
    echo "BIOC_TIDYSINGLECELLEXPERIMENT:" > versions.yml
    echo "    tidysinglecellexperiment: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TIDYSINGLECELLEXPERIMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TIDYSINGLECELLEXPERIMENT(ch_input)

    emit:
    results  = BIOC_TIDYSINGLECELLEXPERIMENT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TIDYSINGLECELLEXPERIMENT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TIDYSINGLECELLEXPERIMENT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TIDYSINGLECELLEXPERIMENT.out.versions  // channel: path(versions.yml)
}
