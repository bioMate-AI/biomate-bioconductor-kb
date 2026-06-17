#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CiteFuse — between_sample_analysis
// Compare gene/protein expression and perform differential expression across different samples or conditions.
// Input: sce_control.rds, sce_disease.rds
// Container: quay.io/biocontainers/bioconductor-citefuse:1.22.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CiteFuse, SingleCellExperiment, ggplot2, scater
// Visualizations: box plot
// QC: missing-value handling, cell QC metrics
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Compare expression across samples using visualiseExprsList()
//  * 2. [Core Analysis] Perform cross-sample differential expression using DEgenesCross()
//  * 3. [Core Analysis] Select significant cross-sample DE genes using selectDEgenes()

nextflow.enable.dsl = 2

process BIOC_CITEFUSE_BETWEEN_SAMPLE_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("CiteFuse", "scater", "ggplot2", "SummarizedExperiment")
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
      library(CiteFuse)
        library(scater)
        library(ggplot2)
        
        # 1. Load User Input Files
        if (!file.exists("sce_control.rds") || !file.exists("sce_disease.rds")) {
          stop("Error: Required input files 'sce_control.rds' and/or 'sce_disease.rds' not found in the working directory.")
        }
        
        sce_citeseq <- readRDS("sce_control.rds")
        sce_ctcl_subset <- readRDS("sce_disease.rds")
        
        # Dynamically determine features to plot
        rna_features <- head(intersect(rownames(sce_citeseq), rownames(sce_ctcl_subset)), 2)
        adt_features <- head(intersect(rownames(altExp(sce_citeseq, "ADT")), rownames(altExp(sce_ctcl_subset, "ADT"))), 2)
        
        # Dynamically determine grouping columns (using the last column in colData as the default clustering)
        group_col_c <- tail(colnames(colData(sce_citeseq)), 1)
        group_col_d <- tail(colnames(colData(sce_ctcl_subset)), 1)
        
        # Dynamically determine groups to test
        group_c <- as.character(na.omit(unique(colData(sce_citeseq)[[group_col_c]])))[1]
        group_d <- as.character(na.omit(unique(colData(sce_ctcl_subset)[[group_col_d]])))[1]
        
        # 2. Compare expression across samples using visualiseExprsList()
        # RNA expression comparison
        p_rna <- visualiseExprsList(
          sce_list = list(control = sce_citeseq, ctcl = sce_ctcl_subset), 
          plot = "boxplot", 
          altExp_name = "none", 
          exprs_value = "logcounts", 
          feature_subset = rna_features, 
          group_by = c(group_col_c, group_col_d)
        )
        
        # ADT expression comparison
        p_adt <- visualiseExprsList(
          sce_list = list(control = sce_citeseq, ctcl = sce_ctcl_subset), 
          plot = "boxplot", 
          altExp_name = "ADT", 
          feature_subset = adt_features, 
          group_by = c(group_col_c, group_col_d)
        )
        
        # Save the visualization plots to a PDF file
        pdf("between_sample_expression_boxplots.pdf", width = 10, height = 8)
        if (!is.null(p_rna)) print(p_rna)
        if (!is.null(p_adt)) print(p_adt)
        dev.off()
        
        # 3. Perform cross-sample differential expression using DEgenesCross()
        de_res <- DEgenesCross(
          sce_list = list(control = sce_citeseq, ctcl = sce_ctcl_subset), 
          colData_name = c(group_col_c, group_col_d), 
          group_to_test = c(group_c, group_d)
        )
        
        # Save raw DE results
        saveRDS(de_res, "de_res_raw.rds")
        
        # 4. Select significant cross-sample DE genes using selectDEgenes()
        de_res_filter <- selectDEgenes(de_res = de_res)
        
        # Save filtered DE results as RDS
        saveRDS(de_res_filter, "de_res_filtered.rds")
        
        # Export filtered DE results to CSV tables
        if (is.list(de_res_filter)) {
          for (sample_name in names(de_res_filter)) {
            df <- de_res_filter[[sample_name]]
            if (!is.null(df) && nrow(df) > 0) {
              write.csv(df, file = paste0("de_res_filter_", sample_name, ".csv"), row.names = TRUE)
            }
          }
        }
        
        message("Pipeline completed successfully. Outputs saved to 'between_sample_expression_boxplots.pdf', 'de_res_raw.rds', 'de_res_filtered.rds', and corresponding CSV files.")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # missing-value handling — scan .rds matrix/data.frame artifacts for max NA fraction
    .mv_na_fracs <- numeric(0)
    .mv_scanned <- character(0)
    for (.mv_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .mv_obj <- tryCatch(readRDS(.mv_rds), error = function(e) NULL)
      .mv_mat <- if (is.matrix(.mv_obj) || is.data.frame(.mv_obj)) .mv_obj else NULL
      if (!is.null(.mv_mat)) {
        .mv_vals <- suppressWarnings(as.numeric(as.matrix(.mv_mat)))
        if (length(.mv_vals) > 0) {
          .mv_na_fracs <- c(.mv_na_fracs, mean(is.na(.mv_vals)))
          .mv_scanned <- c(.mv_scanned, .mv_rds)
        }
      }
    }
    .mv_max <- if (length(.mv_na_fracs) > 0) round(max(.mv_na_fracs), 4) else NA_real_
    .gates_by_label[["missing-value handling"]] <- list(
      gate_row = "bioc_missing_value_handling",
      metric_name = "na_fraction_remaining",
      metric_value = .mv_max,
      passes = isTRUE(is.finite(.mv_max) && .mv_max < 0.05),
      status = if (is.finite(.mv_max)) paste0("computed (scanned ", length(.mv_scanned), " rds files)")
               else "not_computed (no matrix/data.frame .rds artifact present)"
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

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_CITEFUSE_BETWEEN_SAMPLE_ANALYSIS",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling", "cell QC metrics"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_CITEFUSE_BETWEEN_SAMPLE_ANALYSIS":',
        paste0('    CiteFuse: ', as.character(packageVersion('CiteFuse')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_between_sample_analysis.csv versions.yml
    """
}

workflow BIOC_CITEFUSE_BETWEEN_SAMPLE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce_control.rds, sce_disease.rds ] ]

    main:
    BIOC_CITEFUSE_BETWEEN_SAMPLE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_CITEFUSE_BETWEEN_SAMPLE_ANALYSIS.out.tables
    plots    = BIOC_CITEFUSE_BETWEEN_SAMPLE_ANALYSIS.out.plots
    objects  = BIOC_CITEFUSE_BETWEEN_SAMPLE_ANALYSIS.out.objects
    versions = BIOC_CITEFUSE_BETWEEN_SAMPLE_ANALYSIS.out.versions
}
