#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scrapper — modular_sc_rna_seq_analysis
// Run the single-cell analysis pipeline step-by-step using individual component functions for custom control over each stage.
// Input: sce.z
// Container: quay.io/biocontainers/bioconductor-scrapper:1.4.0--r45ha27e39d_0
// R packages: SingleCellExperiment, scrapper
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, scater, scrapper
// Visualizations: ordination plot, t-SNE plot, UMAP plot
// QC: cell QC metrics
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Quality control with quickRnaQc.se()
//  * 2. [Core Analysis] Filter cells
//  * 3. [Core Analysis] Normalize counts with normalizeRnaCounts.se()
//  * 4. [Core Analysis] Select highly variable genes with chooseRnaHvgs.se()
//  * 5. [Core Analysis] Run PCA with runPca.se()
//  * 6. [Input & Preparation] Build SNN graph and cluster with runAllNeighborSteps.se()
//  * 7. [Core Analysis] Score markers with scoreMarkers.se()

nextflow.enable.dsl = 2

process BIOC_SCRAPPER_MODULAR_SC_RNA_SEQ_ANALYSIS {
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
    .bm_deps <- c("SingleCellExperiment", "scrapper", "SummarizedExperiment")
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
       library(SummarizedExperiment)
 library(scrapper)
    
    # -----------------------------------------------------------------------------
    # 1. Read User Input
    # -----------------------------------------------------------------------------
    # The pipeline expects 'sce.z' (a SingleCellExperiment object) in the working directory.
    input_file <- "sce.z"
    if (!file.exists(input_file)) {
      stop(paste("Error: Input file", input_file, "not found in the working directory."))
    }
    
    message("Reading input SingleCellExperiment object...")
    sce.z <- readRDS(input_file)
    
    # -----------------------------------------------------------------------------
    # 2. Run Modular Single-Cell RNA-Seq Analysis Pipeline
    # -----------------------------------------------------------------------------
    message("Identifying mitochondrial genes...")
    is.mito <- grep("^mt-", rownames(sce.z), ignore.case = TRUE)
    
    message("Step 1: Quality control with quickRnaQc.se()...")
    test <- sce.z
    test <- quickRnaQc.se(test, subsets=list(mt=is.mito), num.threads=2)
    
    message("Step 2: Filtering cells...")
    test <- test[,test\$keep]
    
    message("Step 3: Normalizing counts with normalizeRnaCounts.se()...")
    test <- normalizeRnaCounts.se(test, size.factors=test\$sum)
    
    message("Step 4: Selecting highly variable genes with chooseRnaHvgs.se()...")
    test <- chooseRnaHvgs.se(test, num.threads=2)
    
    message("Step 5: Running PCA with runPca.se()...")
    test <- runPca.se(test, features=rowData(test)\$hvg, num.threads=2)
    
    message("Step 6: Building SNN graph and clustering with runAllNeighborSteps.se()...")
    test <- runAllNeighborSteps.se(test, num.threads=2)
    
    message("Step 7: Scoring markers with scoreMarkers.se()...")
    markers <- scoreMarkers.se(test, groups=test\$clusters, num.threads=2)
    
    # -----------------------------------------------------------------------------
    # 3. Save Outputs
    # -----------------------------------------------------------------------------
    message("Saving results...")
    
    # Save the fully analyzed SingleCellExperiment object
    saveRDS(test, file = "analyzed_sce.rds")
    
    # Save the raw markers list object
    saveRDS(markers, file = "markers.rds")
    
    # Export marker statistics for each cluster as CSV files
    if (!is.null(markers) && length(markers) > 0) {
      for (cluster_name in names(markers)) {
        marker_df <- as.data.frame(markers[[cluster_name]])
        # Clean up cluster name for filename safety
        safe_cluster_name <- gsub("[^[:alnum:]_]", "_", cluster_name)
        write.csv(marker_df, file = paste0("markers_cluster_", safe_cluster_name, ".csv"))
      }
    }
    
    # Generate and save diagnostic plots if scater is available
    if (requireNamespace("scater", quietly = TRUE)) {
      message("Generating t-SNE plot...")
      pdf("tsne_dimension_reduction.pdf", width = 7, height = 6)
      if ("TSNE" %in% reducedDimNames(test)) {
        print(scater::plotReducedDim(test, "TSNE", colour_by = "clusters"))
      } else {
        warning("TSNE representation not found in reduced dimensions.")
      }
      dev.off()
      
      message("Generating UMAP plot...")
      pdf("umap_dimension_reduction.pdf", width = 7, height = 6)
      if ("UMAP" %in% reducedDimNames(test)) {
        print(scater::plotReducedDim(test, "UMAP", colour_by = "clusters"))
      } else {
        warning("UMAP representation not found in reduced dimensions.")
      }
      dev.off()
    } else {
      message("Skipping PDF plot generation as 'scater' package is not installed.")
    }
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_SCRAPPER_MODULAR_SC_RNA_SEQ_ANALYSIS":',
        paste0('    scrapper: ', as.character(packageVersion('scrapper')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_modular_sc_rna_seq_analysis.csv versions.yml
    """
}

workflow BIOC_SCRAPPER_MODULAR_SC_RNA_SEQ_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce.z ] ]

    main:
    BIOC_SCRAPPER_MODULAR_SC_RNA_SEQ_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SCRAPPER_MODULAR_SC_RNA_SEQ_ANALYSIS.out.tables
    plots    = BIOC_SCRAPPER_MODULAR_SC_RNA_SEQ_ANALYSIS.out.plots
    objects  = BIOC_SCRAPPER_MODULAR_SC_RNA_SEQ_ANALYSIS.out.objects
    versions = BIOC_SCRAPPER_MODULAR_SC_RNA_SEQ_ANALYSIS.out.versions
}
