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

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    tuple val(meta), path("qc_metrics.json"), emit: qc_metrics
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
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # cell QC metrics — defensive cell-count + per-cell summary from any
    # matrix artifact. Pass when columns (cells) ≥ 50 and rows (features) ≥ 200
    # (Luecken & Theis 2019 single-cell QC floor).
    .cqc_ncells <- NA_real_; .cqc_nfeats <- NA_real_; .cqc_files <- character(0)
    for (.cqc_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .cqc_obj <- tryCatch(readRDS(.cqc_rds), error = function(e) NULL)
      .cqc_mat <- if (is.matrix(.cqc_obj) || is.data.frame(.cqc_obj)) .cqc_obj else NULL
      if (!is.null(.cqc_mat) && nrow(.cqc_mat) > 100) {
        .cqc_ncells <- ncol(.cqc_mat); .cqc_nfeats <- nrow(.cqc_mat)
        .cqc_files <- c(.cqc_files, .cqc_rds); break
      }
    }
    .gates_by_label[["cell QC metrics"]] <- list(
      gate_row = "bioc_cell_qc_metrics",
      metric_name = "n_cells",
      metric_value = .cqc_ncells,
      passes = isTRUE(is.finite(.cqc_ncells) && .cqc_ncells >= 50 && .cqc_nfeats >= 200),
      status = if (is.finite(.cqc_ncells)) paste0("computed (cells=", .cqc_ncells, ", features=", .cqc_nfeats, "; proxy gate)")
               else "not_computed (no scRNA matrix .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_SCRAPPER_MODULAR_SC_RNA_SEQ_ANALYSIS",
      domain  = "bioconductor",
      declared_qc_steps = c("cell QC metrics"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



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
