#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Nebulosa — seurat_density
// Perform gene-weighted density estimation and visualization on a Seurat object.
// Input: pbmc3k_filtered_gene_bc_matrices.tar.gz
// Container: quay.io/biocontainers/bioconductor-nebulosa:1.20.0--r45hdfd78af_0
// Requires: BiocFileCache, Nebulosa, Seurat, patchwork
// Visualizations: UMAP/t-SNE plot, density plot
// QC: count normalization, clustering QC
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Download and import 10X data using Read10X
//  * 2. [Input & Preparation] Create a Seurat object and filter low-quality cells
//  * 3. [Core Analysis] Normalize data using SCTransform
//  * 4. [Core Analysis] Perform PCA and UMAP dimensionality reduction
//  * 5. [Core Analysis] Cluster cells using FindNeighbors and FindClusters
//  * 6. [Visualization & Output] Visualize single-gene density and multi-gene joint density using plot_density

nextflow.enable.dsl = 2

process BIOC_NEBULOSA_SEURAT_DENSITY {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required libraries
    library("Nebulosa")
    library("Seurat")
    library("BiocFileCache")
    library("patchwork")
    
    # 1. Import 10X data from local file
    data_file <- "pbmc3k_filtered_gene_bc_matrices.tar.gz"
    if (!file.exists(data_file)) {
      stop("Error: Input file 'pbmc3k_filtered_gene_bc_matrices.tar.gz' not found in the working directory.")
    }
    
    message("Extracting 10X Genomics data...")
    untar(data_file, exdir = tempdir())
    
    message("Reading 10X Genomics data...")
    data <- Read10X(data.dir = file.path(tempdir(),
      "filtered_gene_bc_matrices",
      "hg19"
    ))
    
    # 2. Create Seurat object and filter low-quality cells
    message("Creating Seurat object...")
    pbmc <- CreateSeuratObject(
      counts = data,
      project = "pbmc3k",
      min.cells = 3,
      min.features = 200
    )
    
    message("Performing quality control filtering...")
    pbmc[["percent.mt"]] <- PercentageFeatureSet(pbmc, pattern = "^MT-")
    pbmc <- subset(pbmc, subset = nFeature_RNA < 2500 & percent.mt < 5)
    
    # 3. Normalize data using SCTransform
    message("Running SCTransform...")
    pbmc <- SCTransform(pbmc, verbose = FALSE)
    
    # 4. Perform PCA and UMAP dimensionality reduction
    message("Running PCA...")
    pbmc <- RunPCA(pbmc)
    message("Running UMAP...")
    pbmc <- RunUMAP(pbmc, dims = 1:30)
    
    # 5. Cluster cells using FindNeighbors and FindClusters
    message("Finding neighbors...")
    pbmc <- FindNeighbors(pbmc, dims = 1:30)
    message("Finding clusters...")
    pbmc <- FindClusters(pbmc)
    
    # Save the processed Seurat object
    message("Saving processed Seurat object...")
    saveRDS(pbmc, file = "pbmc_processed.rds")
    
    # 6. Visualize single-gene density and multi-gene joint density using plot_density
    message("Generating plots...")
    pdf("nebulosa_density_plots.pdf", width = 8, height = 10)
    
    # Single-gene density plots
    p_cd4 <- plot_density(pbmc, "CD4")
    print(p_cd4)
    
    p_cd3d <- plot_density(pbmc, "CD3D")
    print(p_cd3d)
    
    # Multi-gene density plots
    p3 <- plot_density(pbmc, c("CD8A", "CCR7"))
    print(p3 + plot_layout(ncol = 1))
    
    p4_cd8_ccr7 <- plot_density(pbmc, c("CD8A", "CCR7"), joint = TRUE)
    print(p4_cd8_ccr7 + plot_layout(ncol = 1))
    
    p_list <- plot_density(pbmc, c("CD8A", "CCR7"), joint = TRUE, combine = FALSE)
    print(p_list[[length(p_list)]])
    
    p4_cd4_ccr7 <- plot_density(pbmc, c("CD4", "CCR7"), joint = TRUE)
    print(p4_cd4_ccr7 + plot_layout(ncol = 1))
    
    # Joint density with DimPlot
    p_joint_dim <- p4_cd4_ccr7[[3]] / DimPlot(pbmc, label = TRUE, repel = TRUE)
    print(p_joint_dim)
    
    dev.off()
    
    message("Pipeline completed successfully. Outputs saved to 'pbmc_processed.rds' and 'nebulosa_density_plots.pdf'.")

    writeLines(c(
        '"BIOC_NEBULOSA_SEURAT_DENSITY":',
        paste0('    Nebulosa: ', as.character(packageVersion('Nebulosa')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_seurat_density.csv versions.yml
    """
}

workflow BIOC_NEBULOSA_SEURAT_DENSITY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pbmc3k_filtered_gene_bc_matrices.tar.gz ] ]

    main:
    BIOC_NEBULOSA_SEURAT_DENSITY(ch_input)

    emit:
    tables   = BIOC_NEBULOSA_SEURAT_DENSITY.out.tables
    plots    = BIOC_NEBULOSA_SEURAT_DENSITY.out.plots
    objects  = BIOC_NEBULOSA_SEURAT_DENSITY.out.objects
    versions = BIOC_NEBULOSA_SEURAT_DENSITY.out.versions
}
