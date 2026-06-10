#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: nebulosa — single_cell_experiment_density
// Perform gene-weighted density estimation and visualization on a SingleCellExperiment object.
// Input: pbmc3k_filtered_gene_bc_matrices.tar.gz
// Container: quay.io/biocontainers/bioconductor-nebulosa:1.20.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

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
    .bm_deps <- c("biocfilecache", "dropletutils", "ggplot2", "nebulosa", "patchwork", "scater", "scran", "seurat")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library("Nebulosa")
    library("scater")
    library("scran")
    library("DropletUtils")
    library("patchwork")
    library("ggplot2")
    
    # 1. Import 10X data into a SingleCellExperiment object
    # Read the local file from the working directory as specified
    untar("pbmc3k_filtered_gene_bc_matrices.tar.gz", exdir = tempdir())
    pbmc <- read10xCounts(file.path(tempdir(),
      "filtered_gene_bc_matrices",
      "hg19"
    ))
    
    rownames(pbmc) <- uniquifyFeatureNames(rowData(pbmc)[["ID"]],
                                           rowData(pbmc)[["Symbol"]])
    
    # 2. Pre-process and filter features and cells
    i <- rowSums(counts(pbmc) > 0)
    is_expressed <- i > 3
    pbmc <- pbmc[is_expressed, ]
    
    i <- colSums(counts(pbmc) > 0)
    is_expressed <- i > 200
    pbmc <- pbmc[,is_expressed]
    
    is_mito <- grepl("^MT-", rownames(pbmc))
    qcstats <- perCellQCMetrics(pbmc, subsets = list(Mito = is_mito))
    qcfilter <- quickPerCellQC(qcstats, percent_subsets = c("subsets_Mito_percent"))
    
    # 3. Normalize data using log-transformation
    logcounts(pbmc) <- log1p(counts(pbmc) / colSums(counts(pbmc)) * 1e4)
    
    # 4. Identify highly variable genes and perform PCA and UMAP dimensionality reduction
    dec <- modelGeneVar(pbmc)
    top_hvgs <- getTopHVGs(dec, n = 3000)
    
    set.seed(66)
    pbmc <- runPCA(pbmc, scale = TRUE, subset_row = top_hvgs)
    
    pbmc <- runUMAP(pbmc, dimred = "PCA")
    
    # 5. Cluster cells using SNN graph and Louvain clustering
    g <- buildSNNGraph(pbmc, k = 10, use.dimred = "PCA")
    clust <- igraph::cluster_louvain(g)\$membership
    colLabels(pbmc) <- factor(clust)
    
    # 6. Visualize single-gene density and multi-gene joint density using plot_density
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

    cat <<-END_VERSIONS > versions.yml
    "BIOC_NEBULOSA_SINGLE_CELL_EXPERIMENT_DENSITY":
        nebulosa: \$(Rscript -e 'cat(as.character(packageVersion("nebulosa")))')
    END_VERSIONS
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
