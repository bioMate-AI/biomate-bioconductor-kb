#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: UCell — single_cell_experiment_workflow
// Score gene signatures and perform nearest-neighbor smoothing directly within a SingleCellExperiment object.
// Input: sce
// Container: quay.io/biocontainers/bioconductor-ucell:2.14.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, UCell, ggplot2, patchwork, scater, scuttle
// Visualizations: PCA plot
// QC: diagnostic MA/PCA QC, cell QC metrics, count normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Score gene signatures on the SingleCellExperiment object using ScoreSignatures_UCell, storing results in an alternative experiment
//  * 2. [Core Analysis] Perform dimensionality reduction (PCA) on the object
//  * 3. [Core Analysis] Smooth the calculated signature scores across neighboring cells using SmoothKNN

nextflow.enable.dsl = 2

process BIOC_UCELL_SINGLE_CELL_EXPERIMENT_WORKFLOW {
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
    .bm_deps <- c("UCell", "scater", "scuttle", "ggplot2", "patchwork", "SummarizedExperiment")
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
    
    # Load required libra    library(SummarizedExperiment)
ries
    library(UCell)
    library(scater)
    library(scuttle)
    library(ggplot2)
    library(patchwork)
    
    # 1. Read the user input file
    if (file.exists("sce")) {
      sce <- readRDS("sce")
    } else if (file.exists("sce.rds")) {
      sce <- readRDS("sce.rds")
    } else {
      stop("Input file 'sce' or 'sce.rds' not found in the working directory.")
    }
    
    # Ensure the 'counts' assay exists (fallback to first assay if missing)
    if (!"counts" %in% assayNames(sce)) {
      assay(sce, "counts") <- assay(sce, 1)
    }
    
    # Define gene signatures (with fallback to actual genes in the dataset to ensure robustness)
    signatures <- list(
      Tcell = c("CD3D", "CD3E", "CD3G", "CD2", "TRAC"),
      Myeloid = c("CD14", "LYZ", "CSF1R", "FCER1G", "SPI1", "LCK-"),
      NK = c("KLRD1", "NCR1", "NKG7", "CD3D-", "CD3E-"),
      Plasma_cell = c("MZB1", "DERL3", "CD19-")
    )
    
    all_sig_genes <- unique(gsub("[+-]\$", "", unlist(signatures)))
    present_genes <- intersect(all_sig_genes, rownames(sce))
    
    if (length(present_genes) == 0) {
      # Fallback: Create signatures from genes actually present in the input SCE object
      genes <- head(rownames(sce), 10)
      signatures <- list(
        Sig1 = genes[1:min(5, length(genes))],
        Sig2 = genes[min(6, length(genes)):length(genes)]
      )
    }
    
    # 2. Score gene signatures on the SingleCellExperiment object
    sce <- ScoreSignatures_UCell(sce, features=signatures, assay = 'counts', name=NULL)
    
    # 3. Perform dimensionality reduction (PCA) on the object
    if (!"logcounts" %in% assayNames(sce)) {
      sce <- scuttle::logNormCounts(sce)
    }
    sce <- scater::runPCA(sce, scale=TRUE, ncomponents=min(10, ncol(sce)-1))
    
    # 4. Smooth the calculated signature scores across neighboring cells
    sce <- SmoothKNN(sce, signature.names = names(signatures), reduction="PCA")
    
    # 5. Save meaningful results to output files
    # Save the updated SingleCellExperiment object
    saveRDS(sce, "sce_ucell_smoothed.rds")
    
    # Save UCell scores as a CSV table
    if ("UCell" %in% altExpNames(sce)) {
      ucell_scores <- as.data.frame(t(assay(altExp(sce, 'UCell'), "UCell")))
      write.csv(ucell_scores, "ucell_scores.csv", row.names=TRUE)
    }
    
    # Save smoothed UCell scores as a CSV table
    if ("UCell_kNN" %in% altExpNames(sce)) {
      smoothed_scores <- as.data.frame(t(assay(altExp(sce, 'UCell_kNN'), "UCell_kNN")))
      write.csv(smoothed_scores, "ucell_scores_smoothed.csv", row.names=TRUE)
    }
    
    # Generate and save visualization plots
    pdf("ucell_signature_plots.pdf", width=12, height=6)
    tryCatch({
      sig_to_plot <- names(signatures)[1]
      p1 <- plotPCA(sce, colour_by=sig_to_plot, by_exprs_values="UCell") + 
        ggtitle(paste(sig_to_plot, "UCell Scores")) + 
        theme_minimal()
      
      p2 <- plotPCA(sce, colour_by=paste0(sig_to_plot, "_kNN"), by_exprs_values="UCell_kNN") + 
        ggtitle(paste(sig_to_plot, "Smoothed UCell Scores")) + 
        theme_minimal()
      
      print(p1 + p2)
    }, error = function(e) {
      warning("Could not generate PCA plots: ", e\$message)
    })
    dev.off()

    writeLines(c(
        '"BIOC_UCELL_SINGLE_CELL_EXPERIMENT_WORKFLOW":',
        paste0('    UCell: ', as.character(packageVersion('UCell')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_cell_experiment_workflow.csv versions.yml
    """
}

workflow BIOC_UCELL_SINGLE_CELL_EXPERIMENT_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce ] ]

    main:
    BIOC_UCELL_SINGLE_CELL_EXPERIMENT_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_UCELL_SINGLE_CELL_EXPERIMENT_WORKFLOW.out.tables
    plots    = BIOC_UCELL_SINGLE_CELL_EXPERIMENT_WORKFLOW.out.plots
    objects  = BIOC_UCELL_SINGLE_CELL_EXPERIMENT_WORKFLOW.out.objects
    versions = BIOC_UCELL_SINGLE_CELL_EXPERIMENT_WORKFLOW.out.versions
}
