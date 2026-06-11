#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scRNAseqApp — scrnaseq_app_deployment
// Prepare and deploy a single-cell RNA-seq dataset for interactive visualization using scRNAseqApp.
// Input: counts.csv, coldata.csv
// Container: 1.10.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Seurat, scRNAseqApp
// QC: count normalization, highly-variable feature selection
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCRNASEQAPP_SCRNASEQ_APP_DEPLOYMENT {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("scRNAseqApp", "Seurat")
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
    library(scRNAseqApp)
    library(Seurat)
    
    # --- Read and preprocess input files ---
    message("Reading input files...")
    counts_data <- read.csv("counts.csv", check.names = FALSE)
    if ("gene_id" %in% colnames(counts_data)) {
      rownames(counts_data) <- counts_data\$gene_id
      counts_matrix <- as.matrix(counts_data[, colnames(counts_data) != "gene_id"])
    } else {
      rownames(counts_data) <- counts_data[, 1]
      counts_matrix <- as.matrix(counts_data[, -1])
    }
    
    coldata <- read.csv("coldata.csv", check.names = FALSE)
    if ("sample" %in% colnames(coldata)) {
      rownames(coldata) <- coldata\$sample
    } else {
      rownames(coldata) <- coldata[, 1]
    }
    
    # Align samples between counts and metadata
    common_samples <- intersect(colnames(counts_matrix), rownames(coldata))
    if (length(common_samples) == 0) {
      stop("Error: No common samples found between counts.csv and coldata.csv!")
    }
    counts_matrix <- counts_matrix[, common_samples, drop = FALSE]
    coldata <- coldata[common_samples, , drop = FALSE]
    
    # Ensure counts are numeric/integer
    counts_matrix <- apply(counts_matrix, 2, as.integer)
    rownames(counts_matrix) <- rownames(counts_data)
    
    # --- Create and process Seurat object ---
    message("Creating Seurat object...")
    seurat_obj <- CreateSeuratObject(counts = counts_matrix, meta.data = coldata)
    
    # Standard Seurat processing pipeline to generate required dimensional reductions
    seurat_obj <- NormalizeData(seurat_obj, normalization.method = "LogNormalize", scale.factor = 10000, verbose = FALSE)
    seurat_obj <- FindVariableFeatures(seurat_obj, selection.method = "vst", nfeatures = min(200, nrow(seurat_obj)), verbose = FALSE)
    seurat_obj <- ScaleData(seurat_obj, verbose = FALSE)
    
    # Determine appropriate number of PCs
    npcs <- min(50, ncol(seurat_obj) - 1, nrow(seurat_obj) - 1)
    if (npcs < 2) npcs <- 2
    seurat_obj <- RunPCA(seurat_obj, npcs = npcs, verbose = FALSE)
    
    # Run t-SNE safely based on cell count
    perplexity <- min(30, floor((ncol(seurat_obj) - 1) / 3))
    if (perplexity < 1) perplexity <- 1
    seurat_obj <- RunTSNE(seurat_obj, dims = 1:min(10, npcs), perplexity = perplexity, check_duplicates = FALSE, verbose = FALSE)
    
    # --- Initialize scRNAseqApp database ---
    message("Initializing scRNAseqApp database...")
    publish_folder <- "scRNAseq_shiny_app"
    if (!dir.exists(publish_folder)) {
      dir.create(publish_folder, recursive = TRUE)
    }
    scInit(app_path = publish_folder)
    
    # --- Create App Configuration and Dataset ---
    message("Creating app configuration...")
    appconf <- createAppConfig(
      title = "scRNAseq_User_Dataset",
      destinationFolder = "user_dataset",
      species = "Homo sapiens",
      doi = "N/A",
      datatype = "scRNAseq",
      abstract = "Interactive visualization of user-provided single-cell RNA-seq dataset."
    )
    
    message("Creating dataset files for the Shiny app...")
    createDataSet(
      appconf,
      seurat_obj,
      datafolder = file.path(publish_folder, "data")
    )
    
    # --- Verify and write outputs ---
    message("Verifying output files...")
    created_files <- list.files(file.path(publish_folder, "data", "user_dataset"), recursive = TRUE)
    
    # Write a summary of the deployment
    summary_df <- data.frame(
      Parameter = c("AppPath", "DatasetName", "NumCells", "NumGenes", "FilesCreated"),
      Value = c(
        publish_folder,
        "user_dataset",
        ncol(seurat_obj),
        nrow(seurat_obj),
        length(created_files)
      )
    )
    write.csv(summary_df, "app_deployment_summary.csv", row.names = FALSE)
    
    # Save a list of the created files
    write.csv(data.frame(File = created_files), "app_created_files.csv", row.names = FALSE)
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_SCRNASEQAPP_SCRNASEQ_APP_DEPLOYMENT":',
        paste0('    scRNAseqApp: ', as.character(packageVersion('scRNAseqApp')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scrnaseq_app_deployment.csv versions.yml
    """
}

workflow BIOC_SCRNASEQAPP_SCRNASEQ_APP_DEPLOYMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_SCRNASEQAPP_SCRNASEQ_APP_DEPLOYMENT(ch_input)

    emit:
    tables   = BIOC_SCRNASEQAPP_SCRNASEQ_APP_DEPLOYMENT.out.tables
    plots    = BIOC_SCRNASEQAPP_SCRNASEQ_APP_DEPLOYMENT.out.plots
    objects  = BIOC_SCRNASEQAPP_SCRNASEQ_APP_DEPLOYMENT.out.objects
    versions = BIOC_SCRNASEQAPP_SCRNASEQ_APP_DEPLOYMENT.out.versions
}
