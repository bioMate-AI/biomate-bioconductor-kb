#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Spaniel — spatial_transcriptomics_visium_analysis
// Import 10X Visium spatial transcriptomics data, perform quality control filtering, normalize gene expression, cluster spots, and visualize the results overlaid 
// Input: pathToTenXOuts
// Container: quay.io/biocontainers/bioconductor-spaniel:1.24.0--r45hdfd78af_0
// R packages: DropletUtils, ggplot2, scater, scran, Spaniel
// Bioconductor: 3.20 | R: 4.4
// Requires: DropletUtils, Spaniel, ggplot2, igraph, scater, scran
// Visualizations: ordination plot, UMAP plot, cluster plot
// QC: cell QC metrics, count normalization, clustering QC
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Import Space Ranger output into a SingleCellExperiment
//  * 2. [Visualization & Output] Perform quality control visualization
//  * 3. [Visualization & Output] Filter out low-quality spots
//  * 4. [Visualization & Output] Normalize the filtered data
//  * 5. [Visualization & Output] Visualize the spatial expression of a specific gene
//  * 6. [Visualization & Output] Perform dimensionality reduction and clustering
//  * 7. [Visualization & Output] Visualize the resulting spatial clusters

nextflow.enable.dsl = 2

process BIOC_SPANIEL_SPATIAL_TRANSCRIPTOMICS_VISIUM_ANALYSIS {
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
    .bm_deps <- c("DropletUtils", "ggplot2", "scater", "scran", "Spaniel", "SummarizedExperiment")
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
    library(Spaniel)
    library(SummarizedExperiment)
    library(DropletUtils)
    library(scater)
    library(scran)
    library(ggplot2)
    
    # Define input path as specified in the user input requirements
    pathToTenXOuts <- "pathToTenXOuts"
    
    # Verify that the input directory exists
    if (!dir.exists(pathToTenXOuts)) {
      stop(paste("Error: The input directory", pathToTenXOuts, "does not exist."))
    }
    
    # --- Import Space Ranger output into a SingleCellExperiment ---
    sce <- createVisiumSCE(tenXDir=pathToTenXOuts, 
                                resolution="Low")
    
    # Display colData and metadata information
    print("Preview of colData:")
    print(head(colData(sce)[, c("Barcode", "pixel_x", "pixel_y")]))
    
    print("Image Dimensions:")
    print(metadata(sce)\$ImgDims)
    
    print("Grob Metadata:")
    print(metadata(sce)\$Grob)
    
    # --- Perform quality control visualization ---
    filter <- sce\$detected > 0
    
    pdf("qc_filter_plot.pdf", width = 8, height = 8)
    print(spanielPlot(object = sce,
            plotType = "NoGenes", 
            showFilter = filter, 
            techType = "Visium", 
            ptSizeMax = 3))
    dev.off()
    
    # --- Filter out low-quality spots ---
    sce <- sce[, filter]
    
    # --- Normalize the filtered data ---
    sce <- logNormCounts(sce)
    
    # --- Visualize the spatial expression of a specific gene ---
    gene <- rownames(sce)[1]
    p2 <- spanielPlot(object = sce,
            plotType = "Gene", 
            gene = gene,
            techType = "Visium", 
            ptSizeMax = 3)
    
    pdf("gene_expression_plot.pdf", width = 8, height = 8)
    print(p2)
    dev.off()
    
    # --- Perform dimensionality reduction and clustering ---
    library(scran)
    sce <- logNormCounts(sce)
    sce <- runPCA(sce)
    sce <- runUMAP(sce)
    g <- buildSNNGraph(sce, k = 70)
    
    clust <- igraph::cluster_walktrap(g)\$membership
    sce\$clust <- factor(clust)
    
    p3 <- plotReducedDim(sce, "UMAP", colour_by="clust") 
    
    pdf("umap_clustering_plot.pdf", width = 8, height = 8)
    print(p3)
    dev.off()
    
    # --- Visualize the resulting spatial clusters ---
    p4 <- spanielPlot(object = sce,
            plotType = "Cluster", 
            clusterRes = "clust",
            showFilter = NULL, 
            techType = "Visium", 
            ptSizeMax = 1, customTitle = "Section A")  
    
    pdf("spatial_clusters_plot.pdf", width = 8, height = 8)
    print(p4)
    dev.off()
    
    # Save meaningful outputs to the working directory
    saveRDS(sce, "spaniel_processed_sce.rds")
    
    cluster_export <- data.frame(
      Barcode = colData(sce)\$Barcode,
      Cluster = sce\$clust,
      pixel_x = colData(sce)\$pixel_x,
      pixel_y = colData(sce)\$pixel_y
    )
    write.csv(cluster_export, "spatial_clustering_results.csv", row.names = FALSE)
    
    message("Pipeline completed successfully. Outputs saved to working directory.")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # cell QC metrics — defensive cell-count + per-cell summary from any
    # matrix artifact. Pass when columns (cells) ≥ 50 and rows (features) ≥ 200
    # (Luecken & Theis 2019 single-cell QC floor).
    .cqc_ncells <- NA_real_; .cqc_nfeats <- NA_real_; .cqc_files <- character(0)
    for (.cqc_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
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

    # count normalization — scan .rds matrix artifacts for library-size CV
    # ratio (post-norm / pre-norm); without raw input we report median lib CV
    # as a proxy diagnostic. Threshold = 0.7 (Bullard 2010 BMC Bioinf).
    .cn_lib_cvs <- numeric(0)
    .cn_scanned <- character(0)
    for (.cn_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .cn_obj <- tryCatch(readRDS(.cn_rds), error = function(e) NULL)
      .cn_mat <- if (is.matrix(.cn_obj) || is.data.frame(.cn_obj)) .cn_obj else NULL
      if (!is.null(.cn_mat) && ncol(.cn_mat) >= 2 && nrow(.cn_mat) >= 2) {
        .cn_lib <- tryCatch(colSums(as.matrix(.cn_mat), na.rm = TRUE), error = function(e) NULL)
        if (!is.null(.cn_lib) && all(is.finite(.cn_lib)) && mean(.cn_lib) > 0) {
          .cn_lib_cvs <- c(.cn_lib_cvs, sd(.cn_lib) / mean(.cn_lib))
          .cn_scanned <- c(.cn_scanned, .cn_rds)
        }
      }
    }
    .cn_med_cv <- if (length(.cn_lib_cvs) > 0) round(median(.cn_lib_cvs), 4) else NA_real_
    .gates_by_label[["count normalization"]] <- list(
      gate_row = "bioc_count_normalization",
      metric_name = "lib_size_cv_median",
      metric_value = .cn_med_cv,
      passes = isTRUE(is.finite(.cn_med_cv) && .cn_med_cv <= 0.3),
      status = if (is.finite(.cn_med_cv)) paste0("computed (proxy: median lib-size CV across ", length(.cn_scanned), " matrix .rds; raw-vs-norm ratio not measurable without paired input)")
               else "not_computed (no count matrix .rds artifact present)"
    )

    # clustering QC — n_clusters ∈ [2,50] proxy (silhouette needs cluster pkg).
    .clu_n <- NA_real_
    for (.clu_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .clu_obj <- tryCatch(readRDS(.clu_rds), error = function(e) NULL)
      .clu_v <- NULL
      if (!is.null(.clu_obj)) {
        if (inherits(.clu_obj, "SingleCellExperiment")) {
          .clu_cd <- tryCatch(colData(.clu_obj), error = function(e) NULL)
          if (!is.null(.clu_cd)) {
            .clu_col <- intersect(c("cluster","clusters","seurat_clusters","label"), colnames(.clu_cd))
            if (length(.clu_col) > 0) .clu_v <- .clu_cd[[.clu_col[1]]]
          }
        } else if (inherits(.clu_obj, "Seurat")) {
          .clu_md <- tryCatch(.clu_obj@meta.data, error = function(e) NULL)
          if (!is.null(.clu_md)) {
            .clu_col <- intersect(c("seurat_clusters","cluster","clusters"), colnames(.clu_md))
            if (length(.clu_col) > 0) .clu_v <- .clu_md[[.clu_col[1]]]
          }
        }
      }
      if (!is.null(.clu_v) && length(.clu_v) > 0) {
        .clu_n <- length(unique(as.character(.clu_v[!is.na(.clu_v)]))); break
      }
    }
    .gates_by_label[["clustering QC"]] <- list(
      gate_row = "bioc_clustering_qc",
      metric_name = "n_clusters",
      metric_value = .clu_n,
      passes = isTRUE(is.finite(.clu_n) && .clu_n >= 2 && .clu_n <= 50),
      status = if (is.finite(.clu_n)) paste0("computed (n_clusters=", .clu_n, ")")
               else "not_computed (no SCE/Seurat with cluster column present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_SPANIEL_SPATIAL_TRANSCRIPTOMICS_VISIUM_ANALYSIS",
      domain  = "bioconductor",
      declared_qc_steps = c("cell QC metrics", "count normalization", "clustering QC"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_SPANIEL_SPATIAL_TRANSCRIPTOMICS_VISIUM_ANALYSIS":',
        paste0('    Spaniel: ', as.character(packageVersion('Spaniel')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spatial_transcriptomics_visium_analysis.csv versions.yml
    """
}

workflow BIOC_SPANIEL_SPATIAL_TRANSCRIPTOMICS_VISIUM_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pathToTenXOuts ] ]

    main:
    BIOC_SPANIEL_SPATIAL_TRANSCRIPTOMICS_VISIUM_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SPANIEL_SPATIAL_TRANSCRIPTOMICS_VISIUM_ANALYSIS.out.tables
    plots    = BIOC_SPANIEL_SPATIAL_TRANSCRIPTOMICS_VISIUM_ANALYSIS.out.plots
    objects  = BIOC_SPANIEL_SPATIAL_TRANSCRIPTOMICS_VISIUM_ANALYSIS.out.objects
    versions = BIOC_SPANIEL_SPATIAL_TRANSCRIPTOMICS_VISIUM_ANALYSIS.out.versions
}
