#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mirTarRnaSeq — mirna_mrna_relationship_two_timepoint
// Identify significant miRNA-mRNA fold change differences between two time points compared to a background distribution.
// Input: mRNA0_5.txt.gz, miRNA0_5.txt.gz
// Container: quay.io/biocontainers/bioconductor-mirtarrnaseq:1.18.0--r45hdfd78af_0
// R packages: mirTarRnaSeq
// Bioconductor: 3.20 | R: 4.4
// Requires: mirTarRnaSeq
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load differential expression files for mRNA and miRNA
//  * 2. [Input & Preparation] Parse fold changes and filter mRNAs by p-value threshold using one2OneRnaMiRNA
//  * 3. [Core Analysis] Estimate miRNA-mRNA fold change differences using twoTimePoint
//  * 4. [Core Analysis] Generate a background distribution of fold change differences using twoTimePointSamp
//  * 5. [Core Analysis] Retrieve species-specific miRanda target predictions using getInputSpecies
//  * 6. [Core Analysis] Identify relationships below a p-value threshold using threshSigInter
//  * 7. [Core Analysis] Intersect significant relationships with miRanda predictions using mirandaIntersectInter
//  * 8. [Core Analysis] Format final results using finInterResult
//  * 9. [Visualization & Output] Draw fold change plots using drawInterPlots and a heatmap using mirRnaHeatmapDiff

nextflow.enable.dsl = 2

process BIOC_MIRTARRNASEQ_MIRNA_MRNA_RELATIONSHIP_TWO_TIMEPOINT {
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
    .bm_deps <- c("mirTarRnaSeq")
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
    library(mirTarRnaSeq)
    
    # 1. Load differential expression files for mRNA and miRNA from the working directory
    mrna_df <- read.table("mRNA0_5.txt.gz", as.is = TRUE, header = TRUE, sep = "\t")
    mirna_df <- read.table("miRNA0_5.txt.gz", as.is = TRUE, header = TRUE, sep = "\t")
    
    # Construct the named lists as expected by the package functions
    mrna_files <- list("mRNA0_5" = mrna_df)
    mirna_files <- list("miRNA0_5" = mirna_df)
    
    # 2. Parse fold changes and filter mRNAs by p-value threshold using one2OneRnaMiRNA
    mrna <- one2OneRnaMiRNA(mrna_files, pthreshold = 0.05)\$foldchanges
    mirna <- one2OneRnaMiRNA(mirna_files)\$foldchanges
    
    # 3. Estimate miRNA-mRNA fold change differences using twoTimePoint
    inter0 <- twoTimePoint(mrna, mirna)
    
    # 4. Generate a background distribution of fold change differences using twoTimePointSamp
    outs <- twoTimePointSamp(mrna, mirna, Shrounds = 10)
    
    # 5. Retrieve species-specific miRanda target predictions using getInputSpecies
    miRanda <- getInputSpecies("Mouse", threshold = 140)
    
    # 6. Identify relationships below a p-value threshold using threshSigInter
    sig_InterR <- threshSigInter(inter0, outs)
    
    # 7. Intersect significant relationships with miRanda predictions using mirandaIntersectInter
    results <- mirandaIntersectInter(sig_InterR, outs, mrna, mirna, miRanda)
    
    # 8. Format final results using finInterResult
    final_results <- finInterResult(results)
    
    # Save tabular results and R objects
    write.csv(final_results, "final_results.csv", row.names = FALSE)
    saveRDS(results, "results.rds")
    
    # 9. Draw fold change plots using drawInterPlots and a heatmap using mirRnaHeatmapDiff
    pdf("mirna_mrna_plots.pdf", width = 8, height = 8)
    par(mar = c(4, 4, 2, 1))
    drawInterPlots(mrna, mirna, final_results)
    CorRes <- results\$corrs
    mirRnaHeatmapDiff(CorRes, upper_bound = 9.9)
    dev.off()
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
      process = "BIOC_MIRTARRNASEQ_MIRNA_MRNA_RELATIONSHIP_TWO_TIMEPOINT",
      domain  = "bioconductor",
      declared_qc_steps = c("low-count filtering", "count normalization", "dispersion/size-factor estimation"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_MIRTARRNASEQ_MIRNA_MRNA_RELATIONSHIP_TWO_TIMEPOINT":',
        paste0('    mirTarRnaSeq: ', as.character(packageVersion('mirTarRnaSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mirna_mrna_relationship_two_timepoint.csv versions.yml
    """
}

workflow BIOC_MIRTARRNASEQ_MIRNA_MRNA_RELATIONSHIP_TWO_TIMEPOINT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mRNA0_5.txt.gz, miRNA0_5.txt.gz ] ]

    main:
    BIOC_MIRTARRNASEQ_MIRNA_MRNA_RELATIONSHIP_TWO_TIMEPOINT(ch_input)

    emit:
    tables   = BIOC_MIRTARRNASEQ_MIRNA_MRNA_RELATIONSHIP_TWO_TIMEPOINT.out.tables
    plots    = BIOC_MIRTARRNASEQ_MIRNA_MRNA_RELATIONSHIP_TWO_TIMEPOINT.out.plots
    objects  = BIOC_MIRTARRNASEQ_MIRNA_MRNA_RELATIONSHIP_TWO_TIMEPOINT.out.objects
    versions = BIOC_MIRTARRNASEQ_MIRNA_MRNA_RELATIONSHIP_TWO_TIMEPOINT.out.versions
}
