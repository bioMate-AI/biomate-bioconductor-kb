#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scone — psinorm_standalone_normalization
// Perform fast, scalable Pareto-based between-sample normalization on a SingleCellExperiment object (including HDF5-backed out-of-memory data) and optionally prep
// Input: raw_counts.h5
// Container: quay.io/biocontainers/bioconductor-scone:1.34.0--r45hdfd78af_0
// Requires: DelayedArray, HDF5Array, Seurat, SingleCellExperiment, rhdf5, scater, scone
// QC: cell QC metrics, count normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run PsiNorm on the SingleCellExperiment object to compute size factors. 2. Compute log-normalized counts using logNormCounts. 3. (

nextflow.enable.dsl = 2

process BIOC_SCONE_PSINORM_STANDALONE_NORMALIZATION {
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
    library(SingleCellExperiment)
    library(scone)
    library(scater)
    library(HDF5Array)
    library(DelayedArray)
    library(rhdf5)
    
    # 1. Read User Input
    if (file.exists("raw_counts.h5")) {
      message("Reading HDF5-backed raw counts...")
      h5_content <- h5ls("raw_counts.h5")
      dataset_idx <- which(h5_content\$otype == "H5I_DATASET")[1]
      if (length(dataset_idx) == 0 || is.na(dataset_idx)) {
        stop("No dataset found in raw_counts.h5")
      }
      dataset_name <- h5_content\$name[dataset_idx]
      group_name <- h5_content\$group[dataset_idx]
      full_path <- paste0(group_name, "/", dataset_name)
      full_path <- gsub("//", "/", full_path)
      
      counts_matrix <- HDF5Array("raw_counts.h5", full_path)
      sce <- SingleCellExperiment(assays = list(counts = counts_matrix))
    } else if (file.exists("raw_counts.csv")) {
      message("Reading in-memory raw counts from CSV...")
      counts_matrix <- as.matrix(read.csv("raw_counts.csv", row.names = 1, check.names = FALSE))
      sce <- SingleCellExperiment(assays = list(counts = counts_matrix))
    } else {
      stop("Required input file 'raw_counts.h5' or 'raw_counts.csv' not found in the working directory.")
    }
    
    # Ensure unique feature and cell names are present (required for Seurat conversion)
    if (is.null(rownames(sce))) {
      rownames(sce) <- paste0("Feature", seq_len(nrow(sce)))
    }
    if (is.null(colnames(sce))) {
      colnames(sce) <- paste0("Cell", seq_len(ncol(sce)))
    }
    
    # 2. Run PsiNorm and logNormCounts (Documented Code)
    message("Running PsiNorm...")
    sce<-PsiNorm(sce)
    message("Running logNormCounts...")
    sce<-logNormCounts(sce)
    message("Printing head of size factors:")
    head(sizeFactors(sce))
    
    # 3. Optional Seurat conversion (Documented Code)
    if (requireNamespace("Seurat", quietly = TRUE)) {
      message("Converting to Seurat object...")
      library(Seurat)
      seu <- as.Seurat(sce)
      # Save Seurat object
      saveRDS(seu, "normalized_seurat.rds")
      message("Saved Seurat object to 'normalized_seurat.rds'")
    } else {
      message("Seurat package not installed. Skipping Seurat conversion.")
    }
    
    # 4. Save Outputs
    sf <- sizeFactors(sce)
    cell_names <- names(sf)
    if (is.null(cell_names)) {
      cell_names <- paste0("Cell", seq_along(sf))
    }
    sf_df <- data.frame(Cell = cell_names, SizeFactor = sf)
    write.csv(sf_df, "size_factors.csv", row.names = FALSE)
    message("Saved size factors to 'size_factors.csv'")
    
    saveRDS(sce, "normalized_sce.rds")
    message("Saved SingleCellExperiment object to 'normalized_sce.rds'")

    writeLines(c(
        '"BIOC_SCONE_PSINORM_STANDALONE_NORMALIZATION":',
        paste0('    scone: ', as.character(packageVersion('scone')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_psinorm_standalone_normalization.csv versions.yml
    """
}

workflow BIOC_SCONE_PSINORM_STANDALONE_NORMALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ raw_counts.h5 ] ]

    main:
    BIOC_SCONE_PSINORM_STANDALONE_NORMALIZATION(ch_input)

    emit:
    tables   = BIOC_SCONE_PSINORM_STANDALONE_NORMALIZATION.out.tables
    plots    = BIOC_SCONE_PSINORM_STANDALONE_NORMALIZATION.out.plots
    objects  = BIOC_SCONE_PSINORM_STANDALONE_NORMALIZATION.out.objects
    versions = BIOC_SCONE_PSINORM_STANDALONE_NORMALIZATION.out.versions
}
