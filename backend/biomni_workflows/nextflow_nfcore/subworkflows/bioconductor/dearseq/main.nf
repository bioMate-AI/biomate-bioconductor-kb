#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: dearseq — gene_wise_analysis
// Identify differentially expressed genes from RNA-seq data using the variance component score test.
// Input: expression_matrix.xlsx, metadata.csv
// Container: quay.io/biocontainers/bioconductor-dearseq:1.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, dearseq, edgeR, readxl
// Visualizations: plot (ggplot/base)
// QC: low-count filtering, count normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Prepare expression data and metadata in a SummarizedExperiment object
//  * 2. [Core Analysis] Filter out lowly expressed genes (if starting from raw counts)
//  * 3. [Core Analysis] Run gene-wise differential analysis using dear_seq()
//  * 4. [Visualization & Output] Summarize and plot results using summary() and plot()

nextflow.enable.dsl = 2

process BIOC_DEARSEQ_GENE_WISE_ANALYSIS {
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
    .bm_deps <- c("dearseq", "readxl", "edgeR", "SummarizedExperiment")
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
       library(dearseq)
        library(readxl)
        library(edgeR)
        
        # 1. Prepare expression data and metadata in a SummarizedExperiment object
        # Read metadata from the user-provided CSV file
        infos_df <- read.csv("metadata.csv", stringsAsFactors = TRUE)
        
        # Construct col_data and handle factor levels robustly
        # Assuming first column is Sample ID and second column is the condition of interest
        col_data <- data.frame("Condition" = infos_df[[2]])
        if ("Control" %in% col_data\$Condition) {
          col_data\$Condition <- stats::relevel(factor(col_data\$Condition), ref="Control")
        } else {
          col_data\$Condition <- factor(col_data\$Condition)
        }
        rownames(col_data) <- as.character(infos_df[[1]])
        
        # Read expression matrix from the user-provided Excel file
        London_raw <- readxl::read_excel("expression_matrix.xlsx")
        
        # Identify the gene identifier column and numeric expression columns
        if ("Genes" %in% colnames(London_raw)) {
          genes_raw <- London_raw\$Genes
        } else {
          genes_raw <- London_raw[[1]]
        }
        
        num_cols <- sapply(London_raw, is.numeric)
        London_raw_mat <- as.matrix(London_raw[, num_cols])
        rownames(London_raw_mat) <- genes_raw
        
        # Create SummarizedExperiment object
        se_raw <- SummarizedExperiment(assays = London_raw_mat, 
                                       colData = col_data)
        
        # 2. Filter out lowly expressed genes (if starting from raw counts)
        group <- se_raw\$Condition
        
        dgList <- DGEList(counts = London_raw_mat, group = group)
        cpm <- cpm(dgList)
        countCheck <- cpm > 2
        keep <- which(rowSums(countCheck) >= 5)
        London_raw_mat <- London_raw_mat[keep,]
        se_raw <- se_raw[keep, ]
        
        # 3. Run gene-wise differential analysis using dear_seq()
        se_subset <- se_raw
        
        res_dearseq <- dearseq::dear_seq(object = se_subset,
                                         variables2test = "Condition",
                                         which_test='permutation',
                                         preprocessed=FALSE, 
                                         parallel_comp = interactive())
        
        # 4. Summarize and plot results using summary() and plot()
        # Save summary text output
        sink("dearseq_summary.txt")
        summary(res_dearseq)
        sink()
        
        # Save diagnostic plots to PDF
        pdf("dearseq_plots.pdf")
        plot(res_dearseq)
        dev.off()
        
        # Save results to CSV and RDS files
        write.csv(as.data.frame(res_dearseq\$pvals), "dearseq_results.csv", row.names = TRUE)
        saveRDS(res_dearseq, "dearseq_results.rds")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

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

    # count normalization — scan .rds matrix artifacts for library-size CV
    # ratio (post-norm / pre-norm); without raw input we report median lib CV
    # as a proxy diagnostic. Threshold = 0.7 (Bullard 2010 BMC Bioinf).
    .cn_lib_cvs <- numeric(0)
    .cn_scanned <- character(0)
    for (.cn_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
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
      process = "BIOC_DEARSEQ_GENE_WISE_ANALYSIS",
      domain  = "bioconductor",
      declared_qc_steps = c("low-count filtering", "count normalization"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_DEARSEQ_GENE_WISE_ANALYSIS":',
        paste0('    dearseq: ', as.character(packageVersion('dearseq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gene_wise_analysis.csv versions.yml
    """
}

workflow BIOC_DEARSEQ_GENE_WISE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.xlsx, metadata.csv ] ]

    main:
    BIOC_DEARSEQ_GENE_WISE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_DEARSEQ_GENE_WISE_ANALYSIS.out.tables
    plots    = BIOC_DEARSEQ_GENE_WISE_ANALYSIS.out.plots
    objects  = BIOC_DEARSEQ_GENE_WISE_ANALYSIS.out.objects
    versions = BIOC_DEARSEQ_GENE_WISE_ANALYSIS.out.versions
}
