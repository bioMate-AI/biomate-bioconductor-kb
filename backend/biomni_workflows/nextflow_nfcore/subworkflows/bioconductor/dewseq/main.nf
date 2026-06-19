#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DEWSeq — dewseq_clip_analysis
// Identify differentially enriched RNA-binding protein binding regions from eCLIP/iCLIP sliding window count data compared to size-matched input controls.
// Input: countFile.txt.gz, annotationFile.txt.gz, maxCountFile.txt.gz
// Container: quay.io/biocontainers/bioconductor-dewseq:1.24.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: DEWSeq, data.table, dplyr, tidyverse
// Visualizations: dispersion plot
// QC: dispersion/size-factor estimation, dispersion QC plot, low-count filtering, missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load count and annotation data using fread
//  * 2. [Input & Preparation] Define sample metadata (colData) and construct a DESeqDataSet using DESeqDataSetFromSlidingWindows
//  * 3. [Core Analysis] Prefilter low-count windows using filterCounts
//  * 4. [Core Analysis] Estimate size factors, optionally adjusting for asymmetric enrichment by temporarily identifying and excluding significant windows
//  * 5. [Core Analysis] Estimate dispersions (comparing parametric and local fits) and run the Wald test using estimateDispersions and nbinomWaldTest
//  * 6. [Core Analysis] Perform one-sided significance testing for IP enrichment using resultsDEWSeq
//  * 7. [Core Analysis] Apply multiple hypothesis correction using IHW
//  * 8. [Core Analysis] Combine overlapping significant windows into binding regions using extractRegions
//  * 9. [Visualization & Output] Export the final regions to a BED file using toBED

nextflow.enable.dsl = 2

process BIOC_DEWSEQ_DEWSEQ_CLIP_ANALYSIS {
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
    .bm_deps <- c("DEWSeq", "IHW", "tidyverse", "data.table", "SummarizedExperiment")
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
        library(DEWSeq)
        library(IHW)
        library(tidyverse)
        library(data.table)
        
        # Define input files
        countFile <- "countFile.txt.gz"
        annotationFile <- "annotationFile.txt.gz"
        maxCountFile <- "maxCountFile.txt.gz"
        
        # Check if files exist
        if (!file.exists(countFile)) {
          stop(paste("Required input file missing:", countFile))
        }
        if (!file.exists(annotationFile)) {
          stop(paste("Required input file missing:", annotationFile))
        }
        
        # Read data
        countData <- fread(countFile, sep = "\t")
        annotationData <- fread(annotationFile, sep = "\t")
        
        # Define sample metadata (colData) dynamically based on columns of countData
        sample_names <- colnames(countData)[-1]
        types <- rep("IP", length(sample_names))
        smi_indices <- grep("SMI|input|control", sample_names, ignore.case = TRUE)
        if (length(smi_indices) > 0) {
          types[smi_indices] <- "SMI"
        } else {
          # Fallback: if no SMI is found in names, assume the last one is SMI
          types[length(types)] <- "SMI"
        }
        
        colData <- data.frame(
          row.names = sample_names,
          type      = factor(types, levels = c("IP", "SMI"))
        )
        
        # Construct DESeqDataSet
        ddw <- DESeqDataSetFromSlidingWindows(countData  = countData,
                                              colData    = colData,
                                              annotObj   = annotationData,
                                              tidy       = TRUE,
                                              design     = ~type)
        
        ddw <- estimateSizeFactors(ddw)
        
        # Prefilter low-count windows
        if (file.exists(maxCountFile)) {
          ddw <- filterCounts( object = ddw, maxCountFile = maxCountFile, 
                                countThresh = 5, nsamples = 2)
        } else {
          # Fallback filtering if maxCountFile is not provided
          keep <- rowSums(counts(ddw)) >= 10
          ddw <- ddw[keep,]
        }
        
        # Estimate size factors based on protein coding genes
        if ("gene_type" %in% colnames(rowData(ddw)) && any(rowData(ddw)[,"gene_type"] == "protein_coding")) {
          ddw_mRNAs <- ddw[ rowData(ddw)[,"gene_type"] == "protein_coding", ]
        } else {
          ddw_mRNAs <- ddw
        }
        
        ddw_mRNAs <- estimateSizeFactors(ddw_mRNAs)
        sizeFactors(ddw) <- sizeFactors(ddw_mRNAs)
        
        # Estimate size factors for asymmetric data
        ddw_tmp <- ddw
        ddw_tmp <- estimateDispersions(ddw_tmp, fitType = "local", quiet = TRUE)
        ddw_tmp <- nbinomWaldTest(ddw_tmp)
        ddw_tmp_results <- results(ddw_tmp, contrast = c("type", "IP", "SMI"),
                                   tidy = TRUE, filterFun = ihw)
        tmp_significant_windows <- ddw_tmp_results %>%
                                   dplyr::filter(padj < 0.05) %>% 
                                   dplyr::pull(row)
        rm(list = c("ddw_tmp", "ddw_tmp_results"))
        
        ddw_mRNAs <- ddw_mRNAs[ !rownames(ddw_mRNAs) %in% tmp_significant_windows, ]
        ddw_mRNAs <- estimateSizeFactors(ddw_mRNAs)
        sizeFactors(ddw) <- sizeFactors(ddw_mRNAs)
        rm( list = c("tmp_significant_windows", "ddw_mRNAs"))
        
        # Decide fit type
        decide_fit <- TRUE
        parametric_ddw  <- estimateDispersions(ddw, fitType="parametric")
        if(decide_fit){
          local_ddw  <- estimateDispersions(ddw, fitType="local")
        }
        
        parametricResid <- na.omit(with(mcols(parametric_ddw),abs(log(dispGeneEst)-log(dispFit))))
        if(decide_fit){
          localResid <- na.omit(with(mcols(local_ddw),abs(log(dispGeneEst)-log(dispFit))))
          residDf <- data.frame(residuals=c(parametricResid,localResid),
                                fitType=c(rep("parametric",length(parametricResid)),
                                          rep("local",length(localResid))))
        }
        
        if (median(localResid) <= median(parametricResid)){
          cat("chosen fitType: local\n")
          ddw <- local_ddw
        }else{
          cat("chosen fitType: parametric\n")
          ddw <- parametric_ddw
        }
        rm(local_ddw,parametric_ddw,residDf,parametricResid,localResid)
        
        # Run Wald test
        ddw <- nbinomWaldTest(ddw)
        
        # Save dispersion plot
        pdf("dispersion_plots.pdf")
        plotDispEsts(ddw)
        dev.off()
        
        # Significance testing
        resultWindows <- resultsDEWSeq(ddw,
                                      contrast = c("type", "IP", "SMI"),
                                      tidy = TRUE) %>% as_tibble
        
        resultWindows[,"p_adj_IHW"] <- adj_pvalues(ihw(pSlidingWindows ~ baseMean, 
                             data = resultWindows,
                             alpha = 0.05,
                             nfolds = 10))
        
        resultWindows <- resultWindows %>% 
                              mutate(significant = resultWindows\$p_adj_IHW < 0.01)
        
        # Combine overlapping significant windows into binding regions
        resultRegions <- extractRegions(windowRes  = resultWindows,
                                        padjCol    = "p_adj_IHW",
                                        padjThresh = 0.01, 
                                        log2FoldChangeThresh = 0.5) %>% as_tibble
        
        # Export final regions to BED
        toBED(windowRes = resultWindows,
              regionRes = resultRegions,
              fileName  = "enrichedWindowsRegions.bed")
        
        # Save additional outputs
        write_tsv(resultWindows, "resultWindows.tsv")
        write_tsv(resultRegions, "resultRegions.tsv")
        saveRDS(ddw, "ddw_final.rds")
        
        cat("Pipeline completed successfully.\n")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

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

    # dispersion QC plot — file-exists check for any PDF with "disp" or "bcv"
    # in the filename. Pairs with bioc_dispersion_size_factor.
    .dqp_pdfs <- list.files(".", pattern = "(?i)(disp|bcv).*\\.pdf\$")
    .dqp_passes <- length(.dqp_pdfs) > 0
    .gates_by_label[["dispersion QC plot"]] <- list(
      gate_row = "bioc_dispersion_qc_plot",
      metric_name = "dispersion_plot_exists",
      metric_value = if (.dqp_passes) 1 else 0,
      passes = .dqp_passes,
      status = if (.dqp_passes) paste0("computed (", length(.dqp_pdfs), " dispersion PDF(s) emitted)")
               else "not_computed (no dispersion PDF found)"
    )

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

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_DEWSEQ_DEWSEQ_CLIP_ANALYSIS",
      domain  = "bioconductor",
      declared_qc_steps = c("dispersion/size-factor estimation", "dispersion QC plot", "low-count filtering", "missing-value handling"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_DEWSEQ_DEWSEQ_CLIP_ANALYSIS":',
        paste0('    DEWSeq: ', as.character(packageVersion('DEWSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dewseq_clip_analysis.csv versions.yml
    """
}

workflow BIOC_DEWSEQ_DEWSEQ_CLIP_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ countFile.txt.gz, annotationFile.txt.gz, maxCountFile.txt.gz ] ]

    main:
    BIOC_DEWSEQ_DEWSEQ_CLIP_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_DEWSEQ_DEWSEQ_CLIP_ANALYSIS.out.tables
    plots    = BIOC_DEWSEQ_DEWSEQ_CLIP_ANALYSIS.out.plots
    objects  = BIOC_DEWSEQ_DEWSEQ_CLIP_ANALYSIS.out.objects
    versions = BIOC_DEWSEQ_DEWSEQ_CLIP_ANALYSIS.out.versions
}
