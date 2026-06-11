#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: spatialHeatmap — coexpression_clustering_network
// Identify and visualize groups of biomolecules sharing similar abundance profiles using hierarchical clustering and co-expression networks.
// Input: filtered_expression.rds
// Container: quay.io/biocontainers/bioconductor-spatialheatmap:2.16.3--r45hdfd78af_0
// R packages: SummarizedExperiment, spatialHeatmap
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPATIALHEATMAP_COEXPRESSION_CLUSTERING_NETWORK {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-spatialheatmap:2.16.3--r45hdfd78af_0"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("SummarizedExperiment", "spatialHeatmap")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }

    # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
    for (.bm_d in list.files(".", full.names = TRUE)) {
      if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
        for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
          if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
        }
      }
    }
    
    # Load required libraries
    library(spatialHeatmap)
    library(SummarizedExperiment)
    
    # 1. Read user input
    input_file <- "filtered_expression.rds"
    if (!file.exists(input_file)) {
      stop(paste("Required input file missing:", input_file))
    }
    se.fil.mus <- readRDS(input_file)
    
    # Stage 1: Identify biomolecules with similar profiles to a query gene using submatrix
    sub.mat <- submatrix(data=se.fil.mus, ID='Kif5c', p=0.15)
    saveRDS(sub.mat, "submatrix_results.rds")
    write.csv(as.matrix(assay(sub.mat)), "submatrix_assay.csv", row.names = TRUE)
    
    # Stage 2: Perform hierarchical clustering and plot a matrix heatmap using matrix_hm
    pdf("matrix_heatmap.pdf", width = 10, height = 10)
    res.hc <- matrix_hm(ID=c('Kif5c'), data=sub.mat, angleCol=60, angleRow=60, cexRow=0.8, cexCol=0.8, margin=c(10, 6), static=TRUE, arg.lis1=list(offsetRow=0.01, offsetCol=0.01))
    dev.off()
    saveRDS(res.hc, "matrix_hm_results.rds")
    
    # Stage 3: Extract specific clusters from the dendrogram using cut_dendro
    cut.genes <- cut_dendro(res.hc\$rowDendrogram, h=15, 'Kif5c')
    writeLines(cut.genes, "dendrogram_cut_genes.txt")
    
    # Stage 4: Construct an adjacency matrix and identify network modules using adj_mod
    adj.mod <- adj_mod(data=sub.mat)
    saveRDS(adj.mod, "adjacency_modules.rds")
    
    # Stage 5: Visualize the co-expression network module using network
    pdf("coexpression_network.pdf", width = 10, height = 10)
    network(ID="Kif5c", data=sub.mat, adj.mod=adj.mod, adj.min=0, vertex.label.cex=1.2, vertex.cex=3, edge.cex=3, mar.key=c(3, 10, 1, 10), static=TRUE)
    dev.off()

    writeLines(c(
        '"BIOC_SPATIALHEATMAP_COEXPRESSION_CLUSTERING_NETWORK":',
        paste0('        spatialHeatmap: ', as.character(packageVersion("spatialHeatmap")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_coexpression_clustering_network.csv versions.yml
    """
}

workflow BIOC_SPATIALHEATMAP_COEXPRESSION_CLUSTERING_NETWORK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ filtered_expression.rds ] ]

    main:
    BIOC_SPATIALHEATMAP_COEXPRESSION_CLUSTERING_NETWORK(ch_input)

    emit:
    tables   = BIOC_SPATIALHEATMAP_COEXPRESSION_CLUSTERING_NETWORK.out.tables
    plots    = BIOC_SPATIALHEATMAP_COEXPRESSION_CLUSTERING_NETWORK.out.plots
    objects  = BIOC_SPATIALHEATMAP_COEXPRESSION_CLUSTERING_NETWORK.out.objects
    versions = BIOC_SPATIALHEATMAP_COEXPRESSION_CLUSTERING_NETWORK.out.versions
}
