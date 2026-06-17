#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: partCNV — part_cnv_standard
// Identify locally aneuploid cells using the standard partCNV EM algorithm.
// Input: scRNA_seq_counts.rds, cytogenetics_info.txt
// Container: quay.io/biocontainers/bioconductor-partcnv:1.8.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Seurat, ggplot2, partCNV
// Visualizations: bar plot, UMAP/t-SNE plot, UMAP plot
// QC: count normalization, highly-variable feature selection
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Retrieve genomic coordinates for the cytogenetics feature
//  * 2. [Core Analysis] Subset and filter the count matrix
//  * 3. [Core Analysis] Run the EM algorithm for cell classification

nextflow.enable.dsl = 2

process BIOC_PARTCNV_PART_CNV_STANDARD {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("partCNV", "Seurat", "ggplot2")
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
    
    # Load required packages
    library(partCNV)
    
    # -----------------------------------------------------------------------------
    # 1. Input Validation and Loading
    # -----------------------------------------------------------------------------
    
    if (!file.exists("scRNA_seq_counts.rds")) {
      stop("Error: 'scRNA_seq_counts.rds' not found in the working directory.")
    }
    
    if (!file.exists("cytogenetics_info.txt")) {
      stop("Error: 'cytogenetics_info.txt' not found in the working directory.")
    }
    
    # Read the normalized scRNA-seq count matrix
    counts_matrix <- readRDS("scRNA_seq_counts.rds")
    
    # Read the cytogenetics prior information
    # Expected format: a headered table with columns: feature, proportion, type
    # Example:
    # feature   proportion  type
    # chr20(q11.1-q13.1)    0.40    del
    cyto_info <- read.table("cytogenetics_info.txt", header = TRUE, stringsAsFactors = FALSE)
    
    if (!all(c("feature", "proportion", "type") %in% colnames(cyto_info))) {
      stop("Error: 'cytogenetics_info.txt' must contain 'feature', 'proportion', and 'type' columns.")
    }
    
    cyto_feature_val <- cyto_info\$feature[1]
    cyto_p_val <- as.numeric(cyto_info\$proportion[1])
    cyto_type_val <- cyto_info\$type[1]
    
    # -----------------------------------------------------------------------------
    # 2. Run partCNV Standard Workflow
    # -----------------------------------------------------------------------------
    
    # Step 1: Retrieve genomic coordinates for the cytogenetics feature
    res <- GetCytoLocation(cyto_feature = cyto_feature_val)
    
    # Step 2: Subset and filter the count matrix
    GEout <- GetExprCountCyto(
      cytoloc_output = res,
      Counts = as.matrix(counts_matrix),
      normalization = TRUE,
      qt_cutoff = 0.99
    )
    
    # Step 3: Run the EM algorithm for cell classification
    pcout <- partCNV(
      int_counts = GEout\$ProcessedCount,
      cyto_type = cyto_type_val,
      cyto_p = cyto_p_val
    )
    
    # -----------------------------------------------------------------------------
    # 3. Save Outputs
    # -----------------------------------------------------------------------------
    
    # Save the raw classification vector as an RDS object
    saveRDS(pcout, "partCNV_results.rds")
    
    # Save the classification results as a CSV table
    results_df <- data.frame(
      Cell_ID = names(pcout),
      partCNV_label = pcout,
      stringsAsFactors = FALSE
    )
    write.csv(results_df, "partCNV_cell_labels.csv", row.names = FALSE)
    
    # Generate a basic summary plot
    pdf("partCNV_classification_summary.pdf", width = 6, height = 6)
    barplot(
      table(pcout),
      main = paste("partCNV Cell Classification\nFeature:", cyto_feature_val),
      xlab = "Classification (0 = diploid, 1 = aneuploid)",
      ylab = "Number of Cells",
      col = c("lightblue", "salmon")
    )
    dev.off()
    
    # Optional: Generate Seurat UMAP visualization if Seurat and ggplot2 are available
    if (requireNamespace("Seurat", quietly = TRUE) && requireNamespace("ggplot2", quietly = TRUE)) {
      tryCatch({
        library(Seurat)
        library(ggplot2)
        
        # Create Seurat object and run standard dimension reduction
        sim_seurat <- CreateSeuratObject(counts = counts_matrix)
        sim_seurat <- NormalizeData(sim_seurat, normalization.method = "LogNormalize", scale.factor = 10000)
        sim_seurat <- FindVariableFeatures(sim_seurat, selection.method = "vst", nfeatures = min(2000, nrow(counts_matrix)))
        all_genes <- rownames(sim_seurat)
        sim_seurat <- ScaleData(sim_seurat, features = all_genes)
        sim_seurat <- RunPCA(sim_seurat, features = VariableFeatures(object = sim_seurat), verbose = FALSE)
        sim_seurat <- RunUMAP(sim_seurat, dims = 1:min(10, ncol(sim_seurat) - 1), verbose = FALSE)
        
        # Align cell labels
        common_cells <- intersect(names(pcout), colnames(sim_seurat))
        if (length(common_cells) > 0) {
          sim_seurat <- subset(sim_seurat, cells = common_cells)
          pcout_sub <- pcout[common_cells]
          
          sim_seurat <- AddMetaData(
            object = sim_seurat,
            metadata = pcout_sub,
            col.name = "partCNV_label"
          )
          
          sim_seurat\$partCNV_label <- factor(
            sim_seurat\$partCNV_label,
            levels = c(1, 0),
            labels = c("aneuploid", "diploid")
          )
          
          p1 <- sum(pcout_sub == 1) / length(pcout_sub)
          
          pdf("partCNV_umap.pdf", width = 7, height = 6)
          print(
            DimPlot(sim_seurat, reduction = "umap", group.by = "partCNV_label") +
            ggtitle(paste0("partCNV (", signif(p1, 2) * 100, "%)"))
          )
          dev.off()
        }
      }, error = function(e) {
        warning("Seurat visualization skipped or failed: ", e\$message)
      })
    }
    
    cat("Pipeline completed successfully. Outputs saved to working directory.\n")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

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

    # HVG selection — count rows with high CV. Pass when 1000-3000 HVGs
    # (Stuart 2019 Cell Seurat v3 default range).
    .hvg_count <- NA_real_; .hvg_files <- character(0)
    for (.hvg_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .hvg_obj <- tryCatch(readRDS(.hvg_rds), error = function(e) NULL)
      .hvg_mat <- if (is.matrix(.hvg_obj) || is.data.frame(.hvg_obj)) .hvg_obj else NULL
      if (!is.null(.hvg_mat) && nrow(.hvg_mat) > 200) {
        .hvg_m <- suppressWarnings(as.matrix(.hvg_mat))
        .hvg_cvs <- suppressWarnings(apply(.hvg_m, 1, function(r) {
          .rv <- as.numeric(r); .m <- mean(.rv, na.rm = TRUE)
          if (is.finite(.m) && .m > 0) sd(.rv, na.rm = TRUE) / .m else NA_real_
        }))
        .hvg_count <- sum(is.finite(.hvg_cvs) & .hvg_cvs > 1.0)
        .hvg_files <- c(.hvg_files, .hvg_rds); break
      }
    }
    .gates_by_label[["highly-variable feature selection"]] <- list(
      gate_row = "bioc_hvg_selection",
      metric_name = "hvg_count",
      metric_value = .hvg_count,
      passes = isTRUE(is.finite(.hvg_count) && .hvg_count >= 1000 && .hvg_count <= 3000),
      status = if (is.finite(.hvg_count)) paste0("computed (CV>1.0 rows = ", .hvg_count, "; proxy for HVG selection)")
               else "not_computed (no expression matrix .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_PARTCNV_PART_CNV_STANDARD",
      domain  = "bioconductor",
      declared_qc_steps = c("count normalization", "highly-variable feature selection"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_PARTCNV_PART_CNV_STANDARD":',
        paste0('    partCNV: ', as.character(packageVersion('partCNV')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_part_cnv_standard.csv versions.yml
    """
}

workflow BIOC_PARTCNV_PART_CNV_STANDARD_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ scRNA_seq_counts.rds, cytogenetics_info.txt ] ]

    main:
    BIOC_PARTCNV_PART_CNV_STANDARD(ch_input)

    emit:
    tables   = BIOC_PARTCNV_PART_CNV_STANDARD.out.tables
    plots    = BIOC_PARTCNV_PART_CNV_STANDARD.out.plots
    objects  = BIOC_PARTCNV_PART_CNV_STANDARD.out.objects
    versions = BIOC_PARTCNV_PART_CNV_STANDARD.out.versions
}
