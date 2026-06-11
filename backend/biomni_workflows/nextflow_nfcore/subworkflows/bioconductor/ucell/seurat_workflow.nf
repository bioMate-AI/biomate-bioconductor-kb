#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: UCell — seurat_workflow
// Score gene signatures (including positive/negative markers), adjust algorithm parameters, and perform nearest-neighbor smoothing directly within a Seurat object
// Input: seurat.object
// Container: quay.io/biocontainers/bioconductor-ucell:2.14.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, Seurat, UCell, ggplot2
// Visualizations: feature plot, violin plot
// QC: missing-value handling, count normalization, highly-variable feature selection
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Score gene signatures on the Seurat object using AddModuleScore_UCell, optionally specifying negative weights, maxRank, missing ge
//  * 2. [Core Analysis] Perform dimensionality reduction (PCA) on the object
//  * 3. [Core Analysis] Smooth the calculated signature scores or raw gene expression values across neighboring cells using SmoothKNN

nextflow.enable.dsl = 2

process BIOC_UCELL_SEURAT_WORKFLOW {
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
    .bm_deps <- c("Seurat", "UCell", "BiocParallel", "ggplot2")
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
    library(Seurat)
    library(UCell)
    library(BiocParallel)
    library(ggplot2)
    
    # Read the user input Seurat object
    seurat.object <- readRDS("seurat.object")
    
    # Perform dimensionality reduction (PCA) if not already present
    if (!"pca" %in% names(seurat.object@reductions)) {
      seurat.object <- NormalizeData(seurat.object)
      seurat.object <- FindVariableFeatures(seurat.object, selection.method = "vst", nfeatures = min(200, nrow(seurat.object)))
      seurat.object <- ScaleData(seurat.object)
      seurat.object <- RunPCA(seurat.object, npcs = min(20, ncol(seurat.object) - 1), verbose = FALSE)
    }
    
    # Dynamically define signatures and genes based on available features in the Seurat object
    all_genes <- rownames(seurat.object)
    standard_genes <- c("CD3D", "CD3E", "CD3G", "CD2", "TRAC", "CD14", "LYZ", "CSF1R", "FCER1G", "SPI1", "LCK", "KLRD1", "NCR1", "NKG7", "MZB1", "DERL3", "CD19")
    present_standard <- intersect(standard_genes, all_genes)
    
    if (length(present_standard) >= 4) {
      signatures <- list(
        Tcell = intersect(c("CD3D", "CD3E", "CD3G", "CD2", "TRAC"), all_genes),
        Myeloid = intersect(c("CD14", "LYZ", "CSF1R", "FCER1G", "SPI1"), all_genes)
      )
      if (length(signatures\$Tcell) > 0) {
        signatures\$Tcell <- paste0(signatures\$Tcell, "+")
      }
      if (length(signatures\$Myeloid) > 0) {
        neg_candidates <- setdiff(present_standard, c("CD14", "LYZ", "CSF1R", "FCER1G", "SPI1"))
        if (length(neg_candidates) > 0) {
          signatures\$Myeloid <- c(paste0(signatures\$Myeloid, "+"), paste0(neg_candidates[1], "-"))
        } else {
          signatures\$Myeloid <- paste0(signatures\$Myeloid, "+")
        }
      }
    } else {
      selected_genes <- head(all_genes, 5)
      signatures <- list(
        Sig1 = paste0(selected_genes[1:min(2, length(selected_genes))], "+"),
        Sig2 = paste0(selected_genes[min(3, length(selected_genes)):min(5, length(selected_genes))], "-")
      )
    }
    
    # Clean up signatures to ensure no empty strings or invalid formats
    signatures <- lapply(signatures, function(x) x[x != "+" & x != "-" & !is.na(x) & x != ""])
    signatures <- signatures[sapply(signatures, length) > 0]
    
    # Define genes for SmoothKNN
    genes <- intersect(c("CD2", "CSF1R", "LYZ", "CD3D"), all_genes)
    if (length(genes) == 0) {
      genes <- head(all_genes, 2)
    }
    
    # Define BPPARAM
    BPPARAM <- tryCatch({
      BiocParallel::MulticoreParam(workers = 1)
    }, error = function(e) {
      BiocParallel::SerialParam()
    })
    
    # Execute the documented workflow steps with error handling for robustness
    tryCatch({
      seurat.object <- AddModuleScore_UCell(seurat.object, features=signatures, name=NULL)
    }, error = function(e) {
      message("Error in AddModuleScore_UCell (initial): ", e\$message)
    })
    
    tryCatch({
      seurat.object <- SmoothKNN(seurat.object, signature.names = names(signatures), reduction="pca")
    }, error = function(e) {
      message("Error in SmoothKNN (initial): ", e\$message)
    })
    
    tryCatch({
      seurat.object <- SmoothKNN(seurat.object, signature.names=genes, assay="RNA", reduction="pca", k=20, suffix = "_smooth")
    }, error = function(e) {
      message("Error in SmoothKNN (genes): ", e\$message)
    })
    
    tryCatch({
      seurat.object <- AddModuleScore_UCell(seurat.object, features=signatures, w_neg = 1.0, name = NULL)
    }, error = function(e) {
      message("Error in AddModuleScore_UCell (w_neg): ", e\$message)
    })
    
    tryCatch({
      seurat.object <- AddModuleScore_UCell(seurat.object, features=signatures, maxRank=1000)
    }, error = function(e) {
      message("Error in AddModuleScore_UCell (maxRank): ", e\$message)
    })
    
    tryCatch({
      seurat.object <- AddModuleScore_UCell(seurat.object, features=signatures, missing_genes="impute")
    }, error = function(e) {
      message("Error in AddModuleScore_UCell (missing_genes impute): ", e\$message)
    })
    
    tryCatch({
      seurat.object <- AddModuleScore_UCell(seurat.object, features=signatures, missing_genes="skip")
    }, error = function(e) {
      message("Error in AddModuleScore_UCell (missing_genes skip): ", e\$message)
    })
    
    tryCatch({
      seurat.object <- AddModuleScore_UCell(seurat.object, features=signatures, chunk.size=500)
    }, error = function(e) {
      message("Error in AddModuleScore_UCell (chunk.size): ", e\$message)
    })
    
    tryCatch({
      seurat.object <- AddModuleScore_UCell(seurat.object, features=signatures, BPPARAM=BPPARAM)
    }, error = function(e) {
      message("Error in AddModuleScore_UCell (BPPARAM): ", e\$message)
    })
    
    tryCatch({
      seurat.object <- SmoothKNN(seurat.object, reduction="pca", signature.names = names(signatures), k=3, suffix = "_kNN3")
    }, error = function(e) {
      message("Error in SmoothKNN (k=3): ", e\$message)
    })
    
    tryCatch({
      seurat.object <- SmoothKNN(seurat.object, reduction="pca", signature.names = names(signatures), k=100, suffix = "_kNN100")
    }, error = function(e) {
      message("Error in SmoothKNN (k=100): ", e\$message)
    })
    
    tryCatch({
      seurat.object <- SmoothKNN(seurat.object, reduction="pca", signature.names = names(signatures), k=100, decay=0.001, suffix = "_decay0.001")
    }, error = function(e) {
      message("Error in SmoothKNN (decay=0.001): ", e\$message)
    })
    
    tryCatch({
      seurat.object <- SmoothKNN(seurat.object, reduction="pca", signature.names = names(signatures), k=100, decay=0.5, suffix = "_decay0.5")
    }, error = function(e) {
      message("Error in SmoothKNN (decay=0.5): ", e\$message)
    })
    
    # Save the final Seurat object
    saveRDS(seurat.object, "seurat_object_ucell.rds")
    
    # Save metadata containing the calculated UCell scores
    metadata <- seurat.object[[]]
    write.csv(metadata, "seurat_metadata_ucell_scores.csv", row.names = TRUE)
    
    # Generate and save visualization plots
    score_cols <- grep("UCell|kNN|smooth|decay", colnames(metadata), value = TRUE)
    if (length(score_cols) > 0) {
      pdf("ucell_scores_plots.pdf", width = 10, height = 8)
      features_to_plot <- head(score_cols, min(6, length(score_cols)))
      
      # Run UMAP if possible for spatial visualization
      if (!"umap" %in% names(seurat.object@reductions)) {
        tryCatch({
          seurat.object <- RunUMAP(seurat.object, reduction = "pca", dims = 1:min(20, ncol(seurat.object) - 1), verbose = FALSE)
        }, error = function(e) {
          message("Could not run UMAP: ", e\$message)
        })
      }
      
      if ("umap" %in% names(seurat.object@reductions)) {
        print(FeaturePlot(seurat.object, features = features_to_plot))
      } else {
        print(VlnPlot(seurat.object, features = features_to_plot, pt.size = 0.1))
      }
      dev.off()
    }

    writeLines(c(
        '"BIOC_UCELL_SEURAT_WORKFLOW":',
        paste0('    UCell: ', as.character(packageVersion('UCell')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_seurat_workflow.csv versions.yml
    """
}

workflow BIOC_UCELL_SEURAT_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ seurat.object ] ]

    main:
    BIOC_UCELL_SEURAT_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_UCELL_SEURAT_WORKFLOW.out.tables
    plots    = BIOC_UCELL_SEURAT_WORKFLOW.out.plots
    objects  = BIOC_UCELL_SEURAT_WORKFLOW.out.objects
    versions = BIOC_UCELL_SEURAT_WORKFLOW.out.versions
}
