#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ABSSeq — complex_design_analysis
// Perform differential expression analysis for complex experimental designs using linear models in combination with limma.
// Input: counts.tsv, design_metadata.csv
// Container: quay.io/biocontainers/bioconductor-absseq:1.64.0--r45hdfd78af_0
// R packages: ABSSeq, limma
// Bioconductor: 3.20 | R: 4.4
// Requires: ABSSeq, limma
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Construct the ABSDataSet object with counts
//  * 2. [Input & Preparation] Create a design matrix using model.matrix
//  * 3. [Core Analysis] Run the linear model analysis using ABSSeqlm for pairwise comparisons or ANOVA

nextflow.enable.dsl = 2

process BIOC_ABSSEQ_COMPLEX_DESIGN_ANALYSIS {
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
    .bm_deps <- c("ABSSeq", "limma")
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
    library(ABSSeq)
    library(limma)
    
    # ==========================================
    # 1. Read User Input Files
    # ==========================================
    
    # Read raw integer counts matrix
    counts_data <- read.table("counts.tsv", header=TRUE, sep="\t", row.names=1, check.names=FALSE)
    counts_matrix <- as.matrix(counts_data)
    storage.mode(counts_matrix) <- "integer"
    
    # Read design metadata
    metadata <- read.csv("design_metadata.csv", header=TRUE, row.names=1, check.names=FALSE)
    
    # Align counts columns and metadata rows if necessary
    common_samples <- intersect(colnames(counts_matrix), rownames(metadata))
    if (length(common_samples) > 0) {
      counts_matrix <- counts_matrix[, common_samples, drop=FALSE]
      metadata <- metadata[common_samples, , drop=FALSE]
    }
    
    # Identify the experimental factor column
    group_col <- NULL
    possible_cols <- c("groups", "group", "condition", "treatment", "class")
    for (col in possible_cols) {
      if (col %in% colnames(metadata)) {
        group_col <- col
        break
      }
    }
    if (is.null(group_col)) {
      group_col <- colnames(metadata)[1]
    }
    
    # Map the user's group levels to "0", "1", etc.
    # This ensures that model.matrix(~0+groups) produces columns named "groups0", "groups1", etc.,
    # matching the exact condition names used in the documented vignette code.
    raw_groups <- as.factor(metadata[[group_col]])
    levels(raw_groups) <- as.character(seq_len(length(levels(raw_groups))) - 1)
    
    # ==========================================
    # 2. Execute Documented Workflow
    # ==========================================
    
    # Define groups factor
    groups <- factor(raw_groups)
    
    # Construct the ABSDataSet object with counts
    obj <- ABSDataSet(counts=counts_matrix)
    
    # Create a design matrix using model.matrix
    design <- model.matrix(~0+groups)
    
    # Run the linear model analysis using ABSSeqlm for pairwise comparisons (with limma)
    res_pairwise <- ABSSeqlm(obj, design, condA=c("groups0"), condB=c("groups1"))
    head(res_pairwise)
    
    # Run the linear model analysis using ABSSeqlm for ANOVA-like comparison
    res_anova <- ABSSeqlm(obj, design, condA=c("groups0", "groups1"))
    head(res_anova)
    
    # Run the linear model analysis using ABSSeqlm for pairwise comparisons (without limma)
    res_pairwise_nolm <- ABSSeqlm(obj, design, condA=c("groups0"), condB=c("groups1"), lmodel=FALSE)
    head(res_pairwise_nolm)
    
    # ==========================================
    # 3. Save Outputs
    # ==========================================
    
    # Save results tables
    write.csv(res_pairwise, "res_pairwise_limma.csv", row.names=TRUE)
    write.csv(res_anova, "res_anova_limma.csv", row.names=TRUE)
    write.csv(res_pairwise_nolm, "res_pairwise_no_limma.csv", row.names=TRUE)
    
    # Save R objects for downstream analysis
    saveRDS(obj, "ABSDataSet_object.rds")
    saveRDS(design, "design_matrix.rds")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # between-array norm — file-exists check for post-norm QC PDFs.
    .ban_pdfs <- list.files(".", pattern = "(?i)(boxplot|density|qnorm|norm.*array).*\\.pdf\$")
    .ban_passes <- length(.ban_pdfs) > 0
    .gates_by_label[["between-array normalization"]] <- list(
      gate_row = "bioc_count_normalization",
      metric_name = "between_array_norm_plot_exists",
      metric_value = if (.ban_passes) 1 else 0,
      passes = .ban_passes,
      status = if (.ban_passes) paste0("computed (", length(.ban_pdfs), " PDF(s) emitted)")
               else "not_computed (no between-array QC PDF present)"
    )

    # array detection QC — ExpressionSet detection p-values or detection-column data.frame.
    .adq_rate <- NA_real_
    for (.adq_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .adq_obj <- tryCatch(readRDS(.adq_rds), error = function(e) NULL)
      .adq_pv <- NULL
      if (!is.null(.adq_obj)) {
        if (inherits(.adq_obj, "ExpressionSet")) {
          .adq_pv <- tryCatch(Biobase::assayDataElement(.adq_obj, "Detection"), error = function(e) NULL)
        } else if (is.matrix(.adq_obj) || is.data.frame(.adq_obj)) {
          .adq_cols <- grep("(?i)(detection|pvalue|pval)", colnames(.adq_obj), value = TRUE)
          if (length(.adq_cols) > 0) .adq_pv <- as.matrix(.adq_obj[, .adq_cols, drop = FALSE])
        }
      }
      if (!is.null(.adq_pv) && length(.adq_pv) > 0) {
        .adq_rate <- round(mean(as.numeric(.adq_pv) < 0.05, na.rm = TRUE), 4); break
      }
    }
    .gates_by_label[["array detection QC"]] <- list(
      gate_row = "bioc_array_detection_qc",
      metric_name = "detection_rate",
      metric_value = .adq_rate,
      passes = isTRUE(is.finite(.adq_rate) && .adq_rate >= 0.75),
      status = if (is.finite(.adq_rate)) "computed (probe-detection p<0.05 fraction)"
               else "not_computed (no ExpressionSet/detection-p .rds present)"
    )

    # low-count filtering — fraction of genes retained (heuristic on matrix artifacts).
    # Pass band 30-60% per Chen 2016 F1000 (edgeR filterByExpr convention).
    .lcf_kept_fractions <- numeric(0)
    .lcf_scanned <- character(0)
    for (.lcf_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .lcf_obj <- tryCatch(readRDS(.lcf_rds), error = function(e) NULL)
      .lcf_mat <- if (is.matrix(.lcf_obj) || is.data.frame(.lcf_obj)) .lcf_obj else NULL
      if (!is.null(.lcf_mat) && nrow(.lcf_mat) > 100) {
        .lcf_m <- tryCatch(as.matrix(.lcf_mat), error = function(e) NULL)
        if (!is.null(.lcf_m)) {
          .lcf_row_med <- suppressWarnings(apply(.lcf_m, 1, function(r) median(as.numeric(r), na.rm = TRUE)))
          .lcf_kept <- sum(is.finite(.lcf_row_med) & .lcf_row_med >= 1) / nrow(.lcf_m)
          .lcf_kept_fractions <- c(.lcf_kept_fractions, .lcf_kept)
          .lcf_scanned <- c(.lcf_scanned, .lcf_rds)
        }
      }
    }
    .lcf_kept <- if (length(.lcf_kept_fractions) > 0) round(median(.lcf_kept_fractions), 4) else NA_real_
    .gates_by_label[["low-count filtering"]] <- list(
      gate_row = "bioc_low_count_filtering",
      metric_name = "genes_kept_fraction",
      metric_value = .lcf_kept,
      passes = isTRUE(is.finite(.lcf_kept) && .lcf_kept >= 0.3 && .lcf_kept <= 0.6),
      status = if (is.finite(.lcf_kept)) paste0("computed (proxy: rows w/ median count >=1 across ", length(.lcf_scanned), " matrix .rds)")
               else "not_computed (no count matrix .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_ABSSEQ_COMPLEX_DESIGN_ANALYSIS",
      domain  = "bioconductor",
      declared_qc_steps = c("between-array normalization", "array detection QC", "low-count filtering"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_ABSSEQ_COMPLEX_DESIGN_ANALYSIS":',
        paste0('    ABSSeq: ', as.character(packageVersion('ABSSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_complex_design_analysis.csv versions.yml
    """
}

workflow BIOC_ABSSEQ_COMPLEX_DESIGN_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts.tsv, design_metadata.csv ] ]

    main:
    BIOC_ABSSEQ_COMPLEX_DESIGN_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_ABSSEQ_COMPLEX_DESIGN_ANALYSIS.out.tables
    plots    = BIOC_ABSSEQ_COMPLEX_DESIGN_ANALYSIS.out.plots
    objects  = BIOC_ABSSEQ_COMPLEX_DESIGN_ANALYSIS.out.objects
    versions = BIOC_ABSSEQ_COMPLEX_DESIGN_ANALYSIS.out.versions
}
