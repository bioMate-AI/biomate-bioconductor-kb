#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: nebulosa — single_cell_experiment_density
// Perform gene-weighted density estimation and visualization on a SingleCellExperiment object.
// Input: pbmc3k_filtered_gene_bc_matrices.tar.gz
// Container: quay.io/biocontainers/bioconductor-nebulosa:1.20.0--r45hdfd78af_0
// R packages: BiocFileCache, DropletUtils, ggplot2, Nebulosa, patchwork, scater, scran, Seurat
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: density plot
// QC: per-cell QC metrics, low-count filtering, cell QC metrics, highly-variable feature selection, clustering QC

nextflow.enable.dsl = 2

process BIOC_NEBULOSA_SINGLE_CELL_EXPERIMENT_DENSITY {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-nebulosa:1.20.0--r45hdfd78af_0"

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
    .bm_deps <- c("BiocFileCache", "DropletUtils", "ggplot2", "Nebulosa", "patchwork", "scater", "scran", "Seurat")
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
    library("Nebulosa")
    library("scater")
    library("scran")
    library("DropletUtils")
    library("patchwork")
    library("ggplot2")
    
    # --- Import 10X data into a SingleCellExperiment object ---
    # Read the local file from the working directory as specified
    untar("pbmc3k_filtered_gene_bc_matrices.tar.gz", exdir = tempdir())
    pbmc <- read10xCounts(file.path(tempdir(),
      "filtered_gene_bc_matrices",
      "hg19"
    ))
    
    rownames(pbmc) <- uniquifyFeatureNames(rowData(pbmc)[["ID"]],
                                           rowData(pbmc)[["Symbol"]])
    
    # --- Pre-process and filter features and cells ---
    i <- rowSums(counts(pbmc) > 0)
    is_expressed <- i > 3
    pbmc <- pbmc[is_expressed, ]
    
    i <- colSums(counts(pbmc) > 0)
    is_expressed <- i > 200
    pbmc <- pbmc[,is_expressed]
    
    is_mito <- grepl("^MT-", rownames(pbmc))
    qcstats <- perCellQCMetrics(pbmc, subsets = list(Mito = is_mito))
    qcfilter <- quickPerCellQC(qcstats, percent_subsets = c("subsets_Mito_percent"))
    
    # --- Normalize data using log-transformation ---
    logcounts(pbmc) <- log1p(counts(pbmc) / colSums(counts(pbmc)) * 1e4)
    
    # --- Identify highly variable genes and perform PCA and UMAP ---
    dec <- modelGeneVar(pbmc)
    top_hvgs <- getTopHVGs(dec, n = 3000)
    
    set.seed(66)
    pbmc <- runPCA(pbmc, scale = TRUE, subset_row = top_hvgs)
    
    pbmc <- runUMAP(pbmc, dimred = "PCA")
    
    # --- Cluster cells using SNN graph and Louvain clustering ---
    g <- buildSNNGraph(pbmc, k = 10, use.dimred = "PCA")
    clust <- igraph::cluster_louvain(g)\$membership
    colLabels(pbmc) <- factor(clust)
    
    # --- Visualize single-gene density and multi-gene joint ---
    # Plot 1: CD4 single-gene density
    p1 <- plot_density(pbmc, "CD4")
    ggsave("density_CD4.pdf", plot = p1, width = 8, height = 6)
    
    # Plot 2: CD8A and CCR7 density
    p3 <- plot_density(pbmc, c("CD8A", "CCR7"))
    p3_layout <- p3 + plot_layout(ncol = 1)
    ggsave("density_CD8A_CCR7.pdf", plot = p3_layout, width = 8, height = 10)
    
    # Plot 3: CD8A and CCR7 joint density
    p4 <- plot_density(pbmc, c("CD8A", "CCR7"), joint = TRUE)
    p4_layout <- p4 + plot_layout(ncol = 1)
    ggsave("density_CD8A_CCR7_joint.pdf", plot = p4_layout, width = 8, height = 14)
    
    # Plot 4: Extracting the joint density plot from the list
    p_list <- plot_density(pbmc, c("CD8A", "CCR7"), joint = TRUE, combine = FALSE)
    p_joint_single <- p_list[[length(p_list)]]
    ggsave("density_CD8A_CCR7_joint_single.pdf", plot = p_joint_single, width = 8, height = 6)
    
    # Save outputs
    # Save the processed SingleCellExperiment object
    saveRDS(pbmc, "pbmc_processed.rds")
    
    # Save cell metadata including cluster labels to CSV
    metadata_df <- as.data.frame(colData(pbmc))
    write.csv(metadata_df, "cell_metadata.csv", row.names = TRUE)
    
    # Save highly variable genes to CSV
    write.csv(data.frame(Gene = top_hvgs), "highly_variable_genes.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_NEBULOSA_SINGLE_CELL_EXPERIMENT_DENSITY":',
        paste0('        nebulosa: ', as.character(packageVersion("nebulosa")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_cell_experiment_density.csv versions.yml
    """
}

workflow BIOC_NEBULOSA_SINGLE_CELL_EXPERIMENT_DENSITY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pbmc3k_filtered_gene_bc_matrices.tar.gz ] ]

    main:
    BIOC_NEBULOSA_SINGLE_CELL_EXPERIMENT_DENSITY(ch_input)

    emit:
    tables   = BIOC_NEBULOSA_SINGLE_CELL_EXPERIMENT_DENSITY.out.tables
    plots    = BIOC_NEBULOSA_SINGLE_CELL_EXPERIMENT_DENSITY.out.plots
    objects  = BIOC_NEBULOSA_SINGLE_CELL_EXPERIMENT_DENSITY.out.objects
    versions = BIOC_NEBULOSA_SINGLE_CELL_EXPERIMENT_DENSITY.out.versions
}
