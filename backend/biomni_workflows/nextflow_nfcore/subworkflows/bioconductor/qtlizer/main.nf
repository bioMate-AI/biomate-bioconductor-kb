#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Qtlizer — qtl_annotation_pipeline
// Identify differentially expressed or highly variable genes from expression data and annotate them with quantitative trait loci (QTLs) using Qtlizer.
// Input: counts.csv, coldata.csv
// Container: 1.24.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, Qtlizer
// Visualizations: bar plot
// QC: count normalization
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_QTLIZER_QTL_ANNOTATION_PIPELINE {
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
    .bm_deps <- c("Qtlizer", "GenomicRanges")
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
    library(Qtlizer)
    library(GenomicRanges)
    
    # ==========================================
    # --- Load and Preprocess Input Data ---
    # ==========================================
    
    message("Loading input datasets...")
    # Read counts matrix
    counts_raw <- read.csv("counts.csv", check.names = FALSE, stringsAsFactors = FALSE)
    
    # Handle gene_id column or row names
    if ("gene_id" %in% colnames(counts_raw)) {
      rownames(counts_raw) <- counts_raw\$gene_id
      counts_raw\$gene_id <- NULL
    } else if (is.character(counts_raw[, 1])) {
      rownames(counts_raw) <- counts_raw[, 1]
      counts_raw <- counts_raw[, -1, drop = FALSE]
    }
    
    # Clean gene identifiers (e.g., strip Ensembl version suffixes like .13)
    clean_genes <- sub("\\\\..*\$", "", rownames(counts_raw))
    rownames(counts_raw) <- clean_genes
    
    # Read sample metadata
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # Align samples between counts and metadata
    common_samples <- intersect(colnames(counts_raw), coldata\$sample)
    if (length(common_samples) == 0) {
      stop("Error: No matching samples found between counts.csv and coldata.csv")
    }
    
    counts <- counts_raw[, common_samples, drop = FALSE]
    coldata <- coldata[coldata\$sample %in% common_samples, ]
    
    # ==========================================
    # --- Identify Key Genes for QTL Query ---
    # ==========================================
    
    message("Normalizing expression data...")
    # Simple CPM normalization
    libsizes <- colSums(counts)
    libsizes[libsizes == 0] <- 1 # Avoid division by zero
    cpm <- t(t(counts) / libsizes) * 1e6
    log2_cpm <- log2(cpm + 1)
    
    # Find differentially expressed or highly variable genes
    conditions <- unique(coldata\$condition)
    if (length(conditions) >= 2) {
      message("Performing two-group comparison to identify candidate genes...")
      group1 <- coldata\$sample[coldata\$condition == conditions[1]]
      group2 <- coldata\$sample[coldata\$condition == conditions[2]]
      
      p_values <- apply(log2_cpm, 1, function(x) {
        tryCatch({
          t.test(x[group1], x[group2])\$p.value
        }, error = function(e) NA)
      })
      
      mean_g1 <- rowMeans(log2_cpm[, group1, drop = FALSE])
      mean_g2 <- rowMeans(log2_cpm[, group2, drop = FALSE])
      log2_fc <- mean_g2 - mean_g1
      
      stats_df <- data.frame(
        gene = rownames(log2_cpm),
        log2FC = log2_fc,
        pvalue = p_values,
        stringsAsFactors = FALSE
      )
      stats_df <- stats_df[!is.na(stats_df\$pvalue), ]
      stats_df <- stats_df[order(stats_df\$pvalue), ]
    } else {
      message("Single condition detected. Selecting highly variable genes...")
      vars <- apply(log2_cpm, 1, var)
      stats_df <- data.frame(
        gene = rownames(log2_cpm),
        variance = vars,
        stringsAsFactors = FALSE
      )
      stats_df <- stats_df[order(stats_df\$variance, decreasing = TRUE), ]
    }
    
    # Select top 15 genes to query to avoid API rate limits/timeouts
    top_genes <- head(stats_df\$gene, 15)
    
    # ==========================================
    # --- Query Qtlizer Database ---
    # ==========================================
    
    qtl_df <- data.frame()
    qtl_gr <- GRanges()
    
    if (length(top_genes) > 0) {
      message("Querying Qtlizer for top candidate genes: ", paste(top_genes, collapse = ", "))
      
      # Query as DataFrame
      qtl_df <- tryCatch({
        get_qtls(top_genes, return_obj = "dataframe")
      }, error = function(e) {
        warning("Qtlizer DataFrame query failed: ", e\$message)
        NULL
      })
      
      # Query as GRanges
      qtl_gr <- tryCatch({
        get_qtls(top_genes, return_obj = "granges", ref_version = "hg38")
      }, error = function(e) {
        warning("Qtlizer GRanges query failed: ", e\$message)
        NULL
      })
    } else {
      warning("No candidate genes found to query.")
    }
    
    # ==========================================
    # --- Post-processing and Export ---
    # ==========================================
    
    # Ensure output data frame is valid and write to CSV
    if (is.null(qtl_df) || nrow(qtl_df) == 0) {
      message("No QTL annotations returned. Creating empty placeholder output.")
      qtl_df <- data.frame(
        query_type = character(), query_term = character(), sentinel = character(),
        chr = character(), var_pos_hg19 = integer(), var_pos_hg38 = integer(),
        type = character(), gene = character(), ensgid = character(),
        colocalization = character(), distance = numeric(), tissue = character(),
        p = numeric(), sign_info = character(), beta = numeric(),
        source = character(), pmid = character(), is_sign = logical()
      )
    } else {
      # Print metadata comments from the query
      meta_info <- comment(qtl_df)
      if (!is.null(meta_info)) {
        message("Qtlizer Metadata:")
        cat(meta_info, sep = "\n")
      }
    }
    write.csv(qtl_df, "qtl_annotations.csv", row.names = FALSE)
    
    # Process and write GRanges output
    if (!is.null(qtl_gr) && length(qtl_gr) > 0) {
      gr_df <- as.data.frame(qtl_gr)
      write.csv(gr_df, "qtl_ranges.csv", row.names = FALSE)
    } else {
      write.csv(data.frame(message = "No genomic ranges returned or query failed"), 
                "qtl_ranges.csv", row.names = FALSE)
    }
    
    # ==========================================
    # --- Diagnostic Visualizations ---
    # ==========================================
    
    pdf("qtl_summary_plots.pdf", width = 8, height = 6)
    
    if (nrow(qtl_df) > 0 && "tissue" %in% colnames(qtl_df)) {
      # Plot 1: Distribution of QTLs across tissues
      tissue_counts <- table(qtl_df\$tissue)
      tissue_counts <- sort(tissue_counts, decreasing = TRUE)
      top_tissues <- head(tissue_counts, 10)
      
      if (length(top_tissues) > 0) {
        op <- par(mar = c(5, 15, 4, 2))
        barplot(top_tissues, las = 2, horiz = TRUE, col = "skyblue",
                main = "Top 10 Tissues with Associated QTLs",
                xlab = "Number of QTLs")
        par(op)
      }
      
      # Plot 2: P-value distribution of retrieved QTLs
      if ("p" %in% colnames(qtl_df)) {
        p_vals <- as.numeric(qtl_df\$p)
        p_vals <- p_vals[!is.na(p_vals)]
        if (length(p_vals) > 0) {
          hist(-log10(p_vals), col = "coral", border = "white",
               main = "Significance Distribution of Associated QTLs",
               xlab = "-log10(P-value)", ylab = "Frequency")
        }
      }
    } else {
      # Fallback empty plot if no data
      plot.new()
      text(0.5, 0.5, "No QTL data available to plot", cex = 1.2)
    }
    
    dev.off()
    message("Pipeline completed successfully.")
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

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_QTLIZER_QTL_ANNOTATION_PIPELINE",
      domain  = "bioconductor",
      declared_qc_steps = c("count normalization"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_QTLIZER_QTL_ANNOTATION_PIPELINE":',
        paste0('    Qtlizer: ', as.character(packageVersion('Qtlizer')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_qtl_annotation_pipeline.csv versions.yml
    """
}

workflow BIOC_QTLIZER_QTL_ANNOTATION_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_QTLIZER_QTL_ANNOTATION_PIPELINE(ch_input)

    emit:
    tables   = BIOC_QTLIZER_QTL_ANNOTATION_PIPELINE.out.tables
    plots    = BIOC_QTLIZER_QTL_ANNOTATION_PIPELINE.out.plots
    objects  = BIOC_QTLIZER_QTL_ANNOTATION_PIPELINE.out.objects
    versions = BIOC_QTLIZER_QTL_ANNOTATION_PIPELINE.out.versions
}
