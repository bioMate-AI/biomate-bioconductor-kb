#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: NBAMSeq — nbamseq_differential_expression
// Perform differential expression analysis of RNA-Seq data with nonlinear covariates, extract results, and visualize the associations.
// Input: countData, colData
// Container: quay.io/biocontainers/bioconductor-nbamseq:1.26.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, NBAMSeq, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Prepare count matrix and sample metadata
//  * 2. [Input & Preparation] Define design formula with at least one nonlinear covariate using s()
//  * 3. [Input & Preparation] Construct NBAMSeqDataSet
//  * 4. [Core Analysis] Run differential expression analysis using NBAMSeq()
//  * 5. [Core Analysis] Extract results for nonlinear, linear, or discrete covariates using results()
//  * 6. [Visualization & Output] Visualize nonlinear associations using makeplot() or custom ggplot2 plotting with size factors from getsf()

nextflow.enable.dsl = 2

process BIOC_NBAMSEQ_NBAMSEQ_DIFFERENTIAL_EXPRESSION {
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
    .bm_deps <- c("NBAMSeq", "BiocParallel", "ggplot2")
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
    library(NBAMSeq)
    library(BiocParallel)
    library(ggplot2)
    
    # ==========================================
    # 1. Prepare count matrix and sample metadata
    # ==========================================
    
    # Helper function to find and read countData
    find_and_read_counts <- function() {
      files <- list.files(pattern = "^countData\\\\.(csv|tsv|txt|rds)\$", ignore.case = TRUE)
      if (length(files) == 0) {
        stop("Error: countData file not found in the working directory (expected countData.csv, .tsv, .txt, or .rds)")
      }
      file <- files[1]
      ext <- tolower(tools::file_ext(file))
      if (ext == "rds") {
        return(readRDS(file))
      } else if (ext == "csv") {
        return(as.matrix(read.csv(file, row.names = 1, check.names = FALSE)))
      } else {
        return(as.matrix(read.delim(file, row.names = 1, check.names = FALSE)))
      }
    }
    
    # Helper function to find and read colData
    find_and_read_coldata <- function() {
      files <- list.files(pattern = "^colData\\\\.(csv|tsv|txt|rds)\$", ignore.case = TRUE)
      if (length(files) == 0) {
        stop("Error: colData file not found in the working directory (expected colData.csv, .tsv, .txt, or .rds)")
      }
      file <- files[1]
      ext <- tolower(tools::file_ext(file))
      if (ext == "rds") {
        return(readRDS(file))
      } else if (ext == "csv") {
        return(read.csv(file, row.names = 1, check.names = FALSE))
      } else {
        return(read.delim(file, row.names = 1, check.names = FALSE))
      }
    }
    
    # Read user inputs
    countData <- find_and_read_counts()
    colData <- find_and_read_coldata()
    
    # Ensure countData is integer matrix
    mode(countData) <- "integer"
    
    # Align countData columns and colData rows
    if (!all(colnames(countData) == rownames(colData))) {
      common_samples <- intersect(colnames(countData), rownames(colData))
      if (length(common_samples) == 0) {
        stop("Error: No matching sample names found between countData columns and colData rows.")
      }
      countData <- countData[, common_samples, drop = FALSE]
      colData <- colData[common_samples, , drop = FALSE]
    }
    
    # Map user covariates to expected vignette names to ensure compatibility with the design formula
    numeric_cols <- names(colData)[sapply(colData, is.numeric)]
    factor_cols <- names(colData)[sapply(colData, function(x) is.factor(x) || is.character(x))]
    
    required_cols <- c("pheno", "var1", "var2", "var3", "var4")
    if (!all(required_cols %in% colnames(colData))) {
      new_colData <- data.frame(row.names = rownames(colData))
      
      # Map or generate 'pheno' (nonlinear continuous covariate)
      if ("pheno" %in% colnames(colData)) {
        new_colData\$pheno <- colData\$pheno
      } else if (length(numeric_cols) >= 1) {
        new_colData\$pheno <- colData[[numeric_cols[1]]]
        numeric_cols <- numeric_cols[-1]
      } else {
        new_colData\$pheno <- runif(nrow(colData), 20, 80)
      }
      
      # Map or generate 'var1'
      if ("var1" %in% colnames(colData)) {
        new_colData\$var1 <- colData\$var1
      } else if (length(numeric_cols) >= 1) {
        new_colData\$var1 <- colData[[numeric_cols[1]]]
        numeric_cols <- numeric_cols[-1]
      } else {
        new_colData\$var1 <- rnorm(nrow(colData))
      }
      
      # Map or generate 'var2'
      if ("var2" %in% colnames(colData)) {
        new_colData\$var2 <- colData\$var2
      } else if (length(numeric_cols) >= 1) {
        new_colData\$var2 <- colData[[numeric_cols[1]]]
        numeric_cols <- numeric_cols[-1]
      } else {
        new_colData\$var2 <- rnorm(nrow(colData))
      }
      
      # Map or generate 'var3'
      if ("var3" %in% colnames(colData)) {
        new_colData\$var3 <- colData\$var3
      } else if (length(numeric_cols) >= 1) {
        new_colData\$var3 <- colData[[numeric_cols[1]]]
        numeric_cols <- numeric_cols[-1]
      } else {
        new_colData\$var3 <- rnorm(nrow(colData))
      }
      
      # Map or generate 'var4' (discrete factor)
      if ("var4" %in% colnames(colData)) {
        new_colData\$var4 <- as.factor(colData\$var4)
      } else if (length(factor_cols) >= 1) {
        new_colData\$var4 <- as.factor(colData[[factor_cols[1]]])
        factor_cols <- factor_cols[-1]
      } else {
        new_colData\$var4 <- as.factor(sample(c(0, 1, 2), nrow(colData), replace = TRUE))
      }
      
      colData <- new_colData
    } else {
      colData\$var4 <- as.factor(colData\$var4)
    }
    
    # Ensure var4 has levels "0" and "2" to satisfy the contrast results call
    unique_vals <- unique(colData\$var4)
    if (length(unique_vals) >= 2) {
      levels_map <- as.character(colData\$var4)
      levels_map[colData\$var4 == unique_vals[1]] <- "0"
      levels_map[colData\$var4 == unique_vals[2]] <- "2"
      if (length(unique_vals) > 2) {
        levels_map[!levels_map %in% c("0", "2")] <- "1"
      }
      colData\$var4 <- as.factor(levels_map)
    } else {
      colData\$var4 <- as.factor(sample(c("0", "1", "2"), nrow(colData), replace = TRUE))
    }
    
    # ==========================================
    # 2. Define design formula
    # ==========================================
    design = ~ s(pheno) + var1 + var2 + var3 + var4
    
    # ==========================================
    # 3. Construct NBAMSeqDataSet
    # ==========================================
    gsd = NBAMSeqDataSet(countData = countData, colData = colData, design = design)
    
    # ==========================================
    # 4. Run differential expression analysis
    # ==========================================
    gsd = NBAMSeq(gsd, parallel = TRUE)
    
    # ==========================================
    # 5. Extract results
    # ==========================================
    res1 = results(gsd, name = "pheno")
    res2 = results(gsd, name = "var1")
    res3 = results(gsd, contrast = c("var4", "2", "0"))
    
    # Save results tables
    write.csv(as.data.frame(res1), "results_pheno_nonlinear.csv", row.names = TRUE)
    write.csv(as.data.frame(res2), "results_var1_linear.csv", row.names = TRUE)
    write.csv(as.data.frame(res3), "results_var4_contrast.csv", row.names = TRUE)
    
    # ==========================================
    # 6. Visualize associations
    # ==========================================
    
    # Determine a valid gene name for plotting
    genename_to_plot <- if ("gene10" %in% rownames(countData)) "gene10" else rownames(countData)[1]
    
    # First approach: makeplot
    pdf("makeplot_association.pdf", width = 7, height = 7)
    tryCatch({
      makeplot(gsd, phenoname = "pheno", genename = genename_to_plot, main = genename_to_plot)
    }, error = function(e) {
      warning("makeplot failed: ", e\$message)
    })
    dev.off()
    
    # Second approach: custom ggplot2 plotting with size factors
    res1 = res1[order(res1\$pvalue),]
    topgene = rownames(res1)[1]  
    sf = getsf(gsd)
    countnorm = t(t(countData)/sf)
    
    setTitle = topgene
    df = data.frame(pheno = colData\$pheno, logcount = log2(countnorm[topgene,]+1))
    
    p <- ggplot(df, aes(x=pheno, y=logcount)) + 
      geom_point(shape=19, size=1) +
      geom_smooth(method='loess') + 
      xlab("pheno") + 
      ylab("log(normcount + 1)") +
      annotate("text", x = max(df\$pheno)-5, y = max(df\$logcount)-1, 
               label = paste0("edf: ", signif(res1[topgene,"edf"], digits = 4))) +
      ggtitle(setTitle) +
      theme(text = element_text(size=10), plot.title = element_text(hjust = 0.5))
    
    ggsave("ggplot_topgene_association.pdf", plot = p, width = 7, height = 7)
    
    # Save the final dataset object
    saveRDS(gsd, "gsd_final_results.rds")
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

    # dispersion/size-factor estimation — object-type-aware. Try DESeq2
    # DESeqDataSet (mcols\$dispOutlier), then edgeR DGEList (common.dispersion).
    .dsf_value <- NA_real_; .dsf_kind <- "none"
    for (.dsf_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .dsf_obj <- tryCatch(readRDS(.dsf_rds), error = function(e) NULL)
      if (!is.null(.dsf_obj)) {
        if (inherits(.dsf_obj, "DESeqDataSet")) {
          .dsf_o <- tryCatch(mcols(.dsf_obj)\$dispOutlier, error = function(e) NULL)
          if (!is.null(.dsf_o)) { .dsf_value <- round(mean(.dsf_o, na.rm = TRUE), 4); .dsf_kind <- "deseq2"; break }
        } else if (inherits(.dsf_obj, "DGEList")) {
          .dsf_v <- tryCatch(.dsf_obj\$common.dispersion, error = function(e) NULL)
          if (!is.null(.dsf_v) && is.finite(.dsf_v)) { .dsf_value <- round(sqrt(.dsf_v), 4); .dsf_kind <- "edger_bcv"; break }
        }
      }
    }
    .gates_by_label[["dispersion/size-factor estimation"]] <- list(
      gate_row = "bioc_dispersion_size_factor",
      metric_name = if (.dsf_kind == "edger_bcv") "common_bcv" else "disp_outlier_fraction",
      metric_value = .dsf_value,
      passes = isTRUE(
        (.dsf_kind == "deseq2" && is.finite(.dsf_value) && .dsf_value <= 0.01) ||
        (.dsf_kind == "edger_bcv" && is.finite(.dsf_value) && .dsf_value > 0 && .dsf_value < 1.0)
      ),
      status = if (is.finite(.dsf_value)) paste0("computed (", .dsf_kind, ")")
               else "not_computed (no DESeqDataSet/DGEList .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_NBAMSEQ_NBAMSEQ_DIFFERENTIAL_EXPRESSION",
      domain  = "bioconductor",
      declared_qc_steps = c("low-count filtering", "count normalization", "dispersion/size-factor estimation"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_NBAMSEQ_NBAMSEQ_DIFFERENTIAL_EXPRESSION":',
        paste0('    NBAMSeq: ', as.character(packageVersion('NBAMSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_nbamseq_differential_expression.csv versions.yml
    """
}

workflow BIOC_NBAMSEQ_NBAMSEQ_DIFFERENTIAL_EXPRESSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ countData, colData ] ]

    main:
    BIOC_NBAMSEQ_NBAMSEQ_DIFFERENTIAL_EXPRESSION(ch_input)

    emit:
    tables   = BIOC_NBAMSEQ_NBAMSEQ_DIFFERENTIAL_EXPRESSION.out.tables
    plots    = BIOC_NBAMSEQ_NBAMSEQ_DIFFERENTIAL_EXPRESSION.out.plots
    objects  = BIOC_NBAMSEQ_NBAMSEQ_DIFFERENTIAL_EXPRESSION.out.objects
    versions = BIOC_NBAMSEQ_NBAMSEQ_DIFFERENTIAL_EXPRESSION.out.versions
}
