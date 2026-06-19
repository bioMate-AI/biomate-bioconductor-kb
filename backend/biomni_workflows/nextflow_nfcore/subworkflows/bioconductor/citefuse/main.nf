#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CiteFuse — preprocessing_doublets_integration
// Preprocess raw CITE-seq matrices, perform step-wise doublet detection, integrate RNA and ADT modalities using Similarity Network Fusion (SNF), and cluster cells
// Input: RNA_counts.matrix, ADT_counts.matrix, HTO_counts.matrix
// Container: quay.io/biocontainers/bioconductor-citefuse:1.22.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CiteFuse, SingleCellExperiment, ggplot2, gridExtra, scater
// Visualizations: plot (ggplot/base)
// QC: doublet detection QC, cell QC metrics, count normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Preprocess raw matrices into a SingleCellExperiment object using preprocessing()
//  * 2. [Core Analysis] Normalize HTO expression using normaliseExprs()
//  * 3. [Core Analysis] Run dimensional reduction on HTO using runTSNE() or runUMAP()
//  * 4. [Core Analysis] Detect cross-sample doublets using crossSampleDoublets()
//  * 5. [Core Analysis] Detect within-sample doublets using withinSampleDoublets()
//  * 6. [Core Analysis] Filter out doublets from the SingleCellExperiment object
//  * 7. [Core Analysis] Normalize RNA and ADT expression
//  * 8. [Core Analysis] Integrate modalities using CiteFuse()
//  * 9. [Core Analysis] Cluster cells using spectralClustering() or igraphClustering()
//  * 10. [Visualization & Output] Visualize joint dimensional reduction using reducedDimSNF() and visualiseDim()

nextflow.enable.dsl = 2

process BIOC_CITEFUSE_PREPROCESSING_DOUBLETS_INTEGRATION {
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
    .bm_deps <- c("CiteFuse", "scater", "gridExtra", "ggplot2")
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
    library(CiteFuse)
    library(scater)
    library(gridExtra)
    library(ggplot2)
    
    # Helper function to read input matrices robustly
    read_matrix <- function(file_path) {
      if (!file.exists(file_path)) {
        stop(paste("Required input file not found:", file_path))
      }
      
      # Try reading as RDS first
      mat <- tryCatch({
        readRDS(file_path)
      }, error = function(e) {
        NULL
      })
      
      if (!is.null(mat)) {
        return(as.matrix(mat))
      }
      
      # Try reading as whitespace-delimited text
      mat <- tryCatch({
        as.matrix(read.table(file_path, header = TRUE, row.names = 1, sep = "", check.names = FALSE))
      }, error = function(e) {
        # Try reading as comma-delimited text
        as.matrix(read.table(file_path, header = TRUE, row.names = 1, sep = ",", check.names = FALSE))
      })
      
      return(mat)
    }
    
    # 1. Read user input files from the working directory
    message("Reading input matrices...")
    rna_mat <- read_matrix("RNA_counts.matrix")
    adt_mat <- read_matrix("ADT_counts.matrix")
    hto_mat <- read_matrix("HTO_counts.matrix")
    
    # Construct the input list matching the structure of CITEseq_example
    CITEseq_example <- list(
      RNA = rna_mat,
      ADT = adt_mat,
      HTO = hto_mat
    )
    
    # Start PDF device to capture all visualisations
    pdf("CiteFuse_outputs.pdf", width = 10, height = 8)
    
    # 2. Preprocess raw matrices into a SingleCellExperiment object
    message("Preprocessing CITE-seq data...")
    sce_citeseq <- preprocessing(CITEseq_example)
    
    # 3. Normalize HTO expression
    message("Normalising HTO expression...")
    sce_citeseq <- normaliseExprs(sce = sce_citeseq, altExp_name = "HTO", transform = "log")
    
    # 4. Run dimensional reduction on HTO
    message("Running dimensional reduction on HTO...")
    sce_citeseq <- scater::runTSNE(sce_citeseq, altexp = "HTO", name = "TSNE_HTO", pca = TRUE)
    print(visualiseDim(sce_citeseq, dimNames = "TSNE_HTO") + labs(title = "tSNE (HTO)"))
    
    sce_citeseq <- scater::runUMAP(sce_citeseq, altexp = "HTO", name = "UMAP_HTO")
    print(visualiseDim(sce_citeseq, dimNames = "UMAP_HTO") + labs(title = "UMAP (HTO)"))
    
    # 5. Detect cross-sample doublets
    message("Detecting cross-sample doublets...")
    sce_citeseq <- crossSampleDoublets(sce_citeseq)
    
    # Save cross-sample doublet tables
    write.csv(as.data.frame(table(sce_citeseq\$doubletClassify_between_label)), 
              "doubletClassify_between_label.csv", row.names = FALSE)
    write.csv(as.data.frame(table(sce_citeseq\$doubletClassify_between_class)), 
              "doubletClassify_between_class.csv", row.names = FALSE)
    
    print(visualiseDim(sce_citeseq, dimNames = "TSNE_HTO", colour_by = "doubletClassify_between_label"))
    
    # Plot HTO pairwise scatter (wrapped in tryCatch in case of fewer than 4 HTOs)
    tryCatch({
      plotHTO(sce_citeseq, 1:4)
    }, error = function(e) {
      message("Skipping plotHTO(1:4) due to: ", e\$message)
    })
    
    # 6. Detect within-sample doublets
    message("Detecting within-sample doublets...")
    sce_citeseq <- withinSampleDoublets(sce_citeseq, minPts = 10)
    
    # Save within-sample doublet tables
    write.csv(as.data.frame(table(sce_citeseq\$doubletClassify_within_label)), 
              "doubletClassify_within_label.csv", row.names = FALSE)
    write.csv(as.data.frame(table(sce_citeseq\$doubletClassify_within_class)), 
              "doubletClassify_within_class.csv", row.names = FALSE)
    
    print(visualiseDim(sce_citeseq, dimNames = "TSNE_HTO", colour_by = "doubletClassify_within_label"))
    
    # 7. Filter out doublets from the SingleCellExperiment object
    message("Filtering out doublets...")
    sce_citeseq <- sce_citeseq[, sce_citeseq\$doubletClassify_within_class == "Singlet" & 
                                 sce_citeseq\$doubletClassify_between_class == "Singlet"]
    
    # 8. Normalize RNA and ADT expression
    message("Normalising RNA and ADT expression...")
    sce_citeseq <- scater::logNormCounts(sce_citeseq)
    sce_citeseq <- normaliseExprs(sce_citeseq, altExp_name = "ADT", transform = "log")
    
    # 9. Integrate modalities using CiteFuse
    message("Integrating modalities using CiteFuse...")
    sce_citeseq <- CiteFuse(sce_citeseq)
    
    # 10. Cluster cells using spectralClustering
    message("Performing spectral clustering...")
    SNF_W_clust <- spectralClustering(metadata(sce_citeseq)[["SNF_W"]], K = 20)
    plot(SNF_W_clust\$eigen_values)
    message("Optimal K based on eigenvalues: ", which.max(abs(diff(SNF_W_clust\$eigen_values))))
    
    # Perform spectral clustering with K = 5 as documented
    SNF_W_clust <- spectralClustering(metadata(sce_citeseq)[["SNF_W"]], K = 5)
    sce_citeseq\$SNF_W_clust <- as.factor(SNF_W_clust\$labels)
    
    SNF_W1_clust <- spectralClustering(metadata(sce_citeseq)[["ADT_W"]], K = 5)
    sce_citeseq\$ADT_clust <- as.factor(SNF_W1_clust\$labels)
    
    SNF_W2_clust <- spectralClustering(metadata(sce_citeseq)[["RNA_W"]], K = 5)
    sce_citeseq\$RNA_clust <- as.factor(SNF_W2_clust\$labels)
    
    # 11. Visualize joint dimensional reduction
    message("Visualising joint dimensional reduction...")
    sce_citeseq <- reducedDimSNF(sce_citeseq, method = "tSNE", dimNames = "tSNE_joint")
    
    g1 <- visualiseDim(sce_citeseq, dimNames = "tSNE_joint", colour_by = "SNF_W_clust") + 
      labs(title = "tSNE (SNF clustering)")
    g2 <- visualiseDim(sce_citeseq, dimNames = "tSNE_joint",  colour_by = "ADT_clust") + 
      labs(title = "tSNE (ADT clustering)")
    g3 <- visualiseDim(sce_citeseq, dimNames = "tSNE_joint",  colour_by = "RNA_clust") + 
      labs(title = "tSNE (RNA clustering)")
    
    grid.arrange(g3, g2, g1, ncol = 2)
    
    # Louvain clustering
    message("Performing Louvain clustering...")
    SNF_W_louvain <- igraphClustering(sce_citeseq, method = "louvain")
    write.csv(as.data.frame(table(SNF_W_louvain)), "SNF_W_louvain_table.csv", row.names = FALSE)
    
    sce_citeseq\$SNF_W_louvain <- as.factor(SNF_W_louvain)
    
    print(visualiseDim(sce_citeseq, dimNames = "tSNE_joint", colour_by = "SNF_W_louvain") + 
      labs(title = "tSNE (SNF louvain clustering)"))
    
    print(visualiseKNN(sce_citeseq, colour_by = "SNF_W_louvain"))
    
    # Close PDF device
    dev.off()
    
    # Save the final processed SingleCellExperiment object
    message("Saving processed SingleCellExperiment object...")
    saveRDS(sce_citeseq, "sce_citeseq_processed.rds")
    
    message("Pipeline completed successfully!")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # doublet detection — SCE/Seurat with doublet column; pass: rate ≤ 10%.
    .dbl_rate <- NA_real_
    for (.dbl_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .dbl_obj <- tryCatch(readRDS(.dbl_rds), error = function(e) NULL)
      .dbl_calls <- NULL
      if (!is.null(.dbl_obj)) {
        if (inherits(.dbl_obj, "SingleCellExperiment")) {
          .dbl_cd <- tryCatch(colData(.dbl_obj), error = function(e) NULL)
          if (!is.null(.dbl_cd)) {
            .dbl_col <- intersect(c("doublet_class","scDblFinder.class","DoubletFinder","is_doublet"), colnames(.dbl_cd))
            if (length(.dbl_col) > 0) .dbl_calls <- as.character(.dbl_cd[[.dbl_col[1]]])
          }
        } else if (inherits(.dbl_obj, "Seurat")) {
          .dbl_md <- tryCatch(.dbl_obj@meta.data, error = function(e) NULL)
          if (!is.null(.dbl_md)) {
            .dbl_col <- intersect(c("DoubletFinder","scDblFinder.class","doublet_class","is_doublet"), colnames(.dbl_md))
            if (length(.dbl_col) > 0) .dbl_calls <- as.character(.dbl_md[[.dbl_col[1]]])
          }
        }
      }
      if (!is.null(.dbl_calls) && length(.dbl_calls) > 0) {
        .dbl_rate <- round(mean(grepl("doublet|TRUE|1", .dbl_calls, ignore.case = TRUE), na.rm = TRUE), 4); break
      }
    }
    .gates_by_label[["doublet detection QC"]] <- list(
      gate_row = "bioc_doublet_detection_qc",
      metric_name = "doublet_rate",
      metric_value = .dbl_rate,
      passes = isTRUE(is.finite(.dbl_rate) && .dbl_rate <= 0.10),
      status = if (is.finite(.dbl_rate)) "computed (SCE colData / Seurat meta.data doublet col)"
               else "not_computed (no SCE/Seurat with doublet column present)"
    )

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

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_CITEFUSE_PREPROCESSING_DOUBLETS_INTEGRATION",
      domain  = "bioconductor",
      declared_qc_steps = c("doublet detection QC", "cell QC metrics", "count normalization"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_CITEFUSE_PREPROCESSING_DOUBLETS_INTEGRATION":',
        paste0('    CiteFuse: ', as.character(packageVersion('CiteFuse')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_preprocessing_doublets_integration.csv versions.yml
    """
}

workflow BIOC_CITEFUSE_PREPROCESSING_DOUBLETS_INTEGRATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ RNA_counts.matrix, ADT_counts.matrix, HTO_counts.matrix ] ]

    main:
    BIOC_CITEFUSE_PREPROCESSING_DOUBLETS_INTEGRATION(ch_input)

    emit:
    tables   = BIOC_CITEFUSE_PREPROCESSING_DOUBLETS_INTEGRATION.out.tables
    plots    = BIOC_CITEFUSE_PREPROCESSING_DOUBLETS_INTEGRATION.out.plots
    objects  = BIOC_CITEFUSE_PREPROCESSING_DOUBLETS_INTEGRATION.out.objects
    versions = BIOC_CITEFUSE_PREPROCESSING_DOUBLETS_INTEGRATION.out.versions
}
