#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DRIMSeq — differential_transcript_usage
// Perform differential transcript usage (DTU) analysis between experimental conditions, with or without batch effects, using Dirichlet-multinomial and beta-binomi
// Input: pasilla_counts.txt, metadata.txt
// Container: quay.io/biocontainers/bioconductor-drimseq:1.38.0--r45hdfd78af_0
// R packages: DRIMSeq, geuvadistranscriptexpr, ggplot2, knitr, pasillatranscriptexpr, stageR
// Bioconductor: 3.20 | R: 4.4
// Requires: DRIMSeq, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load counts and sample metadata into a dmDSdata object using dmDSdata()
//  * 2. [Core Analysis] Filter out lowly expressed genes and transcripts using dmFilter()
//  * 3. [Input & Preparation] Define the full model design matrix using model.matrix()
//  * 4. [Core Analysis] Estimate precision parameters using dmPrecision()
//  * 5. [Core Analysis] Fit the full model proportions and coefficients using dmFit()
//  * 6. [Core Analysis] Test for differential usage against a null model using dmTest()
//  * 7. [Visualization & Output] Extract results using results() and visualize proportions using plotProportions()

nextflow.enable.dsl = 2

process BIOC_DRIMSEQ_DIFFERENTIAL_TRANSCRIPT_USAGE {
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
    .bm_deps <- c("DRIMSeq", "geuvadistranscriptexpr", "ggplot2", "knitr", "pasillatranscriptexpr", "stageR")
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
        library(DRIMSeq)
        library(ggplot2)
        
        # 1. Load counts and sample metadata from the working directory
        if (!file.exists("metadata.txt") || !file.exists("pasilla_counts.txt")) {
          stop("Required input files 'metadata.txt' and/or 'pasilla_counts.txt' are missing from the working directory.")
        }
        
        pasilla_metadata <- read.table("metadata.txt", header = TRUE, as.is = TRUE)
        pasilla_counts <- read.table("pasilla_counts.txt", header = TRUE, as.is = TRUE)
        
        pasilla_samples <- data.frame(sample_id = pasilla_metadata\$SampleName, 
          group = as.factor(pasilla_metadata\$condition))
        levels(pasilla_samples\$group)
        
        d <- dmDSdata(counts = pasilla_counts, samples = pasilla_samples)
        d
        head(counts(d), 3)
        head(samples(d), 3)
        
        # Save initial data plot
        pdf("plot_data_summary.pdf")
        print(plotData(d))
        dev.off()
        
        # Optional subsetting if the subset file is provided in the working directory
        if (file.exists("gene_id_subset.txt")) {
          gene_id_subset <- readLines("gene_id_subset.txt")
          d <- d[names(d) %in% gene_id_subset, ]
        }
        d
        
        table(samples(d)\$group)
        
        # 2. Filter out lowly expressed genes and transcripts
        total_samps <- nrow(pasilla_samples)
        min_reps <- min(table(pasilla_samples\$group))
        
        d <- dmFilter(d, min_samps_gene_expr = total_samps, min_samps_feature_expr = min_reps,
          min_gene_expr = 10, min_feature_expr = 10)
        
        # 3. Define the full model design matrix
        design_full <- model.matrix(~ group, data = samples(d))
        design_full
        
        # 4. Estimate precision parameters
        set.seed(123)
        d <- dmPrecision(d, design = design_full)
        d
        head(mean_expression(d), 3)
        common_precision(d)
        head(genewise_precision(d))
        
        pdf("plot_precision.pdf")
        print(plotPrecision(d))
        dev.off()
        
        ggp <- plotPrecision(d)
        pdf("plot_precision_custom.pdf")
        print(ggp + geom_point(size = 4))
        dev.off()
        
        # 5. Fit the full model proportions and coefficients
        d <- dmFit(d, design = design_full, verbose = 1)
        d
        
        head(proportions(d))
        head(coefficients(d))
        head(coefficients(d), level = "feature")
        
        # 6. Test for differential usage against a null model
        coef_to_test <- paste0("group", levels(pasilla_samples\$group)[2])
        d <- dmTest(d, coef = coef_to_test, verbose = 1)
        print(design(d))
        print(head(results(d), 3))
        
        head(results(d, level = "feature"), 3)
        
        # Save diagnostic plots
        pdf("plot_pvalues_gene.pdf")
        print(plotPValues(d))
        dev.off()
        
        pdf("plot_pvalues_feature.pdf")
        print(plotPValues(d, level = "feature"))
        dev.off()
        
        # 7. Extract results and visualize proportions
        res <- results(d)
        res <- res[order(res\$pvalue, decreasing = FALSE), ]
        top_gene_id <- res\$gene_id[1]
        
        pdf("plot_proportions_bar.pdf")
        print(plotProportions(d, gene_id = top_gene_id, group_variable = "group"))
        dev.off()
        
        pdf("plot_proportions_line.pdf")
        print(plotProportions(d, gene_id = top_gene_id, group_variable = "group", 
          plot_type = "lineplot"))
        dev.off()
        
        pdf("plot_proportions_ribbon.pdf")
        print(plotProportions(d, gene_id = top_gene_id, group_variable = "group", 
          plot_type = "ribbonplot"))
        dev.off()
        
        # Save meaningful tabular results and objects to the working directory
        write.csv(results(d), "dtu_gene_results.csv", row.names = FALSE)
        write.csv(results(d, level = "feature"), "dtu_feature_results.csv", row.names = FALSE)
        write.csv(proportions(d), "fitted_proportions.csv", row.names = FALSE)
        write.csv(coefficients(d), "coefficients_gene.csv", row.names = FALSE)
        write.csv(coefficients(d, level = "feature"), "coefficients_feature.csv", row.names = FALSE)
        saveRDS(d, "drimseq_final_object.rds")
        
        message("DRIMSeq pipeline completed successfully. Outputs saved to working directory.")
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

    # dispersion/size-factor estimation — object-type-aware. Try DESeq2
    # DESeqDataSet (mcols\$dispOutlier), then edgeR DGEList (common.dispersion).
    .dsf_value <- NA_real_; .dsf_kind <- "none"
    for (.dsf_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
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
      process = "BIOC_DRIMSEQ_DIFFERENTIAL_TRANSCRIPT_USAGE",
      domain  = "bioconductor",
      declared_qc_steps = c("low-count filtering", "count normalization", "dispersion/size-factor estimation"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_DRIMSEQ_DIFFERENTIAL_TRANSCRIPT_USAGE":',
        paste0('    DRIMSeq: ', as.character(packageVersion('DRIMSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_transcript_usage.csv versions.yml
    """
}

workflow BIOC_DRIMSEQ_DIFFERENTIAL_TRANSCRIPT_USAGE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pasilla_counts.txt, metadata.txt ] ]

    main:
    BIOC_DRIMSEQ_DIFFERENTIAL_TRANSCRIPT_USAGE(ch_input)

    emit:
    tables   = BIOC_DRIMSEQ_DIFFERENTIAL_TRANSCRIPT_USAGE.out.tables
    plots    = BIOC_DRIMSEQ_DIFFERENTIAL_TRANSCRIPT_USAGE.out.plots
    objects  = BIOC_DRIMSEQ_DIFFERENTIAL_TRANSCRIPT_USAGE.out.objects
    versions = BIOC_DRIMSEQ_DIFFERENTIAL_TRANSCRIPT_USAGE.out.versions
}
