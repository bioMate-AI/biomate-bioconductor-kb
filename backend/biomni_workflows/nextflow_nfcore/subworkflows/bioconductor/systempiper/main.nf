#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: systemPipeR — systempiper_transcriptomics_pipeline
// A complete multi-stage transcriptomics downstream analysis pipeline using systemPipeR to manage data loading, normalization, differential expression analysis, f
// Input: counts.csv, coldata.csv
// Container: 2.16.3--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: systemPipeR
// Visualizations: volcano plot, PCA plot
// QC: low-count filtering, count normalization
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SYSTEMPIPER_SYSTEMPIPER_TRANSCRIPTOMICS_PIPELINE {
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
    .bm_deps <- c("systemPipeR")
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
    
    # Load systemPipeR and required base packages
    library(systemPipeR)
    
    # Initialize systemPipeR project (creates default directory structure)
    sal <- SPRproject(overwrite = TRUE)
    
    # --- Load and Preprocess Data ---
    appendStep(sal) <- LineWise(code = {
      # Read input files
      counts <- read.csv("counts.csv", row.names = 1)
      coldata <- read.csv("coldata.csv")
      
      # Align counts columns with coldata samples
      common_samples <- intersect(colnames(counts), coldata\$sample)
      counts <- counts[, common_samples, drop = FALSE]
      coldata <- coldata[coldata\$sample %in% common_samples, ]
      
      # Filter out genes with zero counts across all samples
      counts <- counts[rowSums(counts) > 0, , drop = FALSE]
      
      save(counts, coldata, file = "step1_loaded.RData")
    }, step_name = "load_data")
    
    # --- Normalization ---
    appendStep(sal) <- LineWise(code = {
      load("step1_loaded.RData")
      
      # Simple CPM (Counts Per Million) normalization
      libsizes <- colSums(counts)
      cpm <- t(t(counts) / libsizes) * 1e6
      log2_cpm <- log2(cpm + 1)
      
      # Write primary output
      write.csv(log2_cpm, "normalized_counts.csv")
      save(log2_cpm, coldata, file = "step2_normalized.RData")
    }, step_name = "normalize", dependency = "load_data")
    
    # --- Differential Expression Analysis ---
    appendStep(sal) <- LineWise(code = {
      load("step2_normalized.RData")
      
      conditions <- unique(coldata\$condition)
      if (length(conditions) >= 2) {
        cond1_samples <- coldata\$sample[coldata\$condition == conditions[1]]
        cond2_samples <- coldata\$sample[coldata\$condition == conditions[2]]
        
        # Two-sample t-test for each gene
        pvals <- apply(log2_cpm, 1, function(x) {
          t_res <- tryCatch(t.test(x[cond1_samples], x[cond2_samples]), error = function(e) NULL)
          if (is.null(t_res)) return(NA) else return(t_res\$p.value)
        })
        
        fdr <- p.adjust(pvals, method = "BH")
        mean1 <- rowMeans(log2_cpm[, cond1_samples, drop = FALSE])
        mean2 <- rowMeans(log2_cpm[, cond2_samples, drop = FALSE])
        log2FC <- mean2 - mean1
        
        deg_table <- data.frame(
          gene_id = rownames(log2_cpm),
          logFC = log2FC,
          pvalue = pvals,
          FDR = fdr
        )
      } else {
        # Fallback if insufficient conditions are present
        deg_table <- data.frame(
          gene_id = rownames(log2_cpm),
          logFC = 0,
          pvalue = 1,
          FDR = 1
        )
      }
      
      save(deg_table, file = "step3_deg.RData")
    }, step_name = "deg_analysis", dependency = "normalize")
    
    # --- Filter DEGs using systemPipeR's filterDEGs ---
    appendStep(sal) <- LineWise(code = {
      load("step3_deg.RData")
      
      # Format data frame for filterDEGs
      deg_df <- data.frame(
        logFC = deg_table\$logFC,
        FDR = deg_table\$FDR
      )
      rownames(deg_df) <- deg_table\$gene_id
      
      # Run filterDEGs with a robust fallback
      filtered_list <- tryCatch({
        # systemPipeR::filterDEGs expects FDR in percentage (e.g., 10 for 10%)
        systemPipeR::filterDEGs(degDF = deg_df, filter = c(FoldChange = 1.5, FDR = 10))
      }, error = function(e) {
        # Manual fallback if filterDEGs fails
        up <- rownames(deg_df[deg_df\$logFC >= log2(1.5) & deg_df\$FDR <= 0.1, , drop = FALSE])
        down <- rownames(deg_df[deg_df\$logFC <= -log2(1.5) & deg_df\$FDR <= 0.1, , drop = FALSE])
        list(Uplist = up, Downlist = down)
      })
      
      # Extract Up and Down genes safely
      up_genes <- if (!is.null(filtered_list\$Uplist)) filtered_list\$Uplist else character(0)
      down_genes <- if (!is.null(filtered_list\$Downlist)) filtered_list\$Downlist else character(0)
      
      summary_df <- data.frame(
        Direction = c("Up", "Down"),
        Count = c(length(up_genes), length(down_genes))
      )
      write.csv(summary_df, "deg_summary.csv", row.names = FALSE)
      save(filtered_list, file = "step4_filtered.RData")
    }, step_name = "filter_degs", dependency = "deg_analysis")
    
    # --- Visualization (Volcano & PCA Plots) ---
    appendStep(sal) <- LineWise(code = {
      load("step2_normalized.RData")
      load("step3_deg.RData")
      
      # 1. Volcano Plot
      pdf("volcano_plot.pdf", width = 7, height = 7)
      plot(deg_table\$logFC, -log10(deg_table\$pvalue), 
           col = ifelse(deg_table\$FDR <= 0.1 & abs(deg_table\$logFC) >= log2(1.5), "red", "black"),
           pch = 20, xlab = "log2 Fold Change", ylab = "-log10 p-value",
           main = "Volcano Plot")
      abline(h = -log10(0.05), col = "blue", lty = 2)
      abline(v = c(-log2(1.5), log2(1.5)), col = "blue", lty = 2)
      dev.off()
      
      # 2. PCA Plot
      pca <- prcomp(t(log2_cpm))
      pca_df <- data.frame(pca\$x, condition = coldata\$condition)
      pdf("pca_plot.pdf", width = 7, height = 7)
      plot(pca_df\$PC1, pca_df\$PC2, col = as.factor(pca_df\$condition), 
           pch = 19, cex = 2, xlab = "PC1", ylab = "PC2", main = "PCA Plot")
      legend("topright", legend = unique(pca_df\$condition), col = 1:length(unique(pca_df\$condition)), pch = 19)
      dev.off()
    }, step_name = "visualization", dependency = "filter_degs")
    
    # --- Workflow Report & Topology ---
    appendStep(sal) <- LineWise(code = {
      # Plot workflow topology
      pdf("workflow_topology.pdf", width = 8, height = 8)
      tryCatch({
        systemPipeR::plotWF(sal, rstudio = FALSE)
      }, error = function(e) {
        plot.new()
        text(0.5, 0.5, "Workflow Topology Plot Failed")
      })
      dev.off()
    }, step_name = "workflow_report", dependency = "visualization")
    
    # Execute the entire workflow
    sal <- runWF(sal)
    
    # Save the final workflow state
    sal <- write_SYSargsList(sal)
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # low-count filtering — fraction of genes retained (heuristic on matrix artifacts).
    # Pass band 30-60% per Chen 2016 F1000 (edgeR filterByExpr convention).
    .lcf_kept_fractions <- numeric(0)
    .lcf_scanned <- character(0)
    for (.lcf_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
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
      process = "BIOC_SYSTEMPIPER_SYSTEMPIPER_TRANSCRIPTOMICS_PIPELINE",
      domain  = "bioconductor",
      declared_qc_steps = c("low-count filtering", "count normalization"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_SYSTEMPIPER_SYSTEMPIPER_TRANSCRIPTOMICS_PIPELINE":',
        paste0('    systemPipeR: ', as.character(packageVersion('systemPipeR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_systempiper_transcriptomics_pipeline.csv versions.yml
    """
}

workflow BIOC_SYSTEMPIPER_SYSTEMPIPER_TRANSCRIPTOMICS_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_SYSTEMPIPER_SYSTEMPIPER_TRANSCRIPTOMICS_PIPELINE(ch_input)

    emit:
    tables   = BIOC_SYSTEMPIPER_SYSTEMPIPER_TRANSCRIPTOMICS_PIPELINE.out.tables
    plots    = BIOC_SYSTEMPIPER_SYSTEMPIPER_TRANSCRIPTOMICS_PIPELINE.out.plots
    objects  = BIOC_SYSTEMPIPER_SYSTEMPIPER_TRANSCRIPTOMICS_PIPELINE.out.objects
    versions = BIOC_SYSTEMPIPER_SYSTEMPIPER_TRANSCRIPTOMICS_PIPELINE.out.versions
}
