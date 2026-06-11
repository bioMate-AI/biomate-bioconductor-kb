#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: nebulosa — seurat_density
// Perform gene-weighted density estimation and visualization on a Seurat object.
// Input: pbmc3k_filtered_gene_bc_matrices.tar.gz
// Container: quay.io/biocontainers/bioconductor-nebulosa:1.20.0--r45hdfd78af_0
// R packages: Nebulosa, Seurat, patchwork
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NEBULOSA_SEURAT_DENSITY {
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
    .bm_deps <- c("Nebulosa", "Seurat", "patchwork")
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
    library("Seurat")
    library("patchwork")
    
    # Define the input file path (must be in the working directory)
    input_file <- "pbmc3k_filtered_gene_bc_matrices.tar.gz"
    
    if (!file.exists(input_file)) {
      stop(paste("Required input file missing:", input_file))
    }
    
    # Untar the input file to a temporary directory
    temp_dir <- tempdir()
    untar(input_file, exdir = temp_dir)
    
    # Read the 10X Genomics matrix
    data <- Read10X(data.dir = file.path(temp_dir, "filtered_gene_bc_matrices", "hg19"))
    
    # Create Seurat object
    pbmc <- CreateSeuratObject(
      counts = data,
      project = "pbmc3k",
      min.cells = 3,
      min.features = 200
    )
    
    # Quality control and filtering
    pbmc[["percent.mt"]] <- PercentageFeatureSet(pbmc, pattern = "^MT-")
    pbmc <- subset(pbmc, subset = nFeature_RNA < 2500 & percent.mt < 5)
    
    # Normalize data using SCTransform
    pbmc <- SCTransform(pbmc, verbose = FALSE)
    
    # Dimensionality reduction
    pbmc <- RunPCA(pbmc)
    pbmc <- RunUMAP(pbmc, dims = 1:30)
    
    # Clustering
    pbmc <- FindNeighbors(pbmc, dims = 1:30)
    pbmc <- FindClusters(pbmc)
    
    # Save processed Seurat object and metadata
    saveRDS(pbmc, file = "pbmc_processed.rds")
    write.csv(pbmc@meta.data, file = "pbmc_metadata.csv", row.names = TRUE)
    
    # Generate and save density plots
    pdf("nebulosa_density_plots.pdf", width = 8, height = 11)
    
    # 1. Single-gene density plot for CD4
    p1 <- plot_density(pbmc, "CD4")
    print(p1)
    
    # 2. Multi-gene density plot for CD8A and CCR7
    p3 <- plot_density(pbmc, c("CD8A", "CCR7"))
    print(p3 + plot_layout(ncol = 1))
    
    # 3. Joint density plot for CD8A and CCR7
    p4 <- plot_density(pbmc, c("CD8A", "CCR7"), joint = TRUE)
    print(p4 + plot_layout(ncol = 1))
    
    # 4. Joint density plot with combine = FALSE (extracting the joint plot only)
    p_list <- plot_density(pbmc, c("CD8A", "CCR7"), joint = TRUE, combine = FALSE)
    print(p_list[[length(p_list)]])
    
    dev.off()

    writeLines(c(
        '"BIOC_NEBULOSA_SEURAT_DENSITY":',
        paste0('        nebulosa: ', as.character(packageVersion("nebulosa")))
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
