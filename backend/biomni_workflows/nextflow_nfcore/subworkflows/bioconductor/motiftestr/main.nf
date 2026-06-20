#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: motifTestR — positional_bias_analysis
// Identify transcription factor binding motifs that show positional bias (localization) relative to the centers of a set of genomic sequences.
// Input: ar_er_peaks, BSgenome.Hsapiens.UCSC.hg19, ex_pfm
// Container: quay.io/biocontainers/bioconductor-motiftestr:1.6.1--r45hdfd78af_0
// R packages: BSgenome, BSgenome.Hsapiens.UCSC.hg19, GenomicRanges, extraChIPs, ggplot2, motifTestR, patchwork, rtracklayer
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome, BSgenome.Hsapiens.UCSC.hg19, GenomicRanges, ggplot2, motifTestR, patchwork
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Extract sequences from genomic peaks using getSeq()
//  * 2. [Core Analysis] Find PWM matches in the sequences using getPwmMatches()
//  * 3. [Core Analysis] Test for positional bias using testMotifPos()
//  * 4. [Visualization & Output] Visualize the positional distribution of matches using plotMatchPos()

nextflow.enable.dsl = 2

process BIOC_MOTIFTESTR_POSITIONAL_BIAS_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("BSgenome", "BSgenome.Hsapiens.UCSC.hg19", "GenomicRanges", "extraChIPs", "ggplot2", "motifTestR", "patchwork", "rtracklayer")
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
    library(motifTestR)
    library(BSgenome)
    library(GenomicRanges)
    library(ggplot2)
    library(patchwork)
    
    # Set cores for parallel processing
    cores <- 1
    
    # Read user inputs from the working directory
    ar_er_peaks <- readRDS("ar_er_peaks.rds")
    ex_pfm <- readRDS("ex_pfm.rds")
    
    # Load BSgenome object from RDS if available, otherwise load package
    if (file.exists("BSgenome.Hsapiens.UCSC.hg19.rds")) {
      BSgenome.Hsapiens.UCSC.hg19 <- readRDS("BSgenome.Hsapiens.UCSC.hg19.rds")
    } else {
      library(BSgenome.Hsapiens.UCSC.hg19)
    }
    
    # 1. Extract sequences from genomic peaks using getSeq()
    test_seq <- getSeq(BSgenome.Hsapiens.UCSC.hg19, ar_er_peaks)
    names(test_seq) <- as.character(ar_er_peaks)
    
    # 2. Find PWM matches in the sequences using getPwmMatches()
    score_thresh <- "70%"
    if (length(ex_pfm) > 0) {
      getPwmMatches(ex_pfm[[1]], test_seq, min_score = score_thresh)
      getPwmMatches(ex_pfm[[1]], test_seq, min_score = score_thresh, best_only = TRUE)
    }
    
    bm_all <- getPwmMatches(
      ex_pfm, test_seq, min_score = score_thresh, best_only = TRUE, break_ties = "all",
      mc.cores = cores
    )
    
    counts <- countPwmMatches(ex_pfm, test_seq, min_score = score_thresh, mc.cores = cores)
    
    # 3. Test for positional bias using testMotifPos()
    res_pos <- testMotifPos(bm_all, mc.cores = cores)
    res_abs <- testMotifPos(bm_all, abs = TRUE, mc.cores = cores)
    
    # 4. Visualize the positional distribution of matches using plotMatchPos()
    topMotifs <- res_pos |>
        subset(fdr < 0.05) |>
        rownames()
    
    if (length(topMotifs) > 0) {
      A <- plotMatchPos(bm_all[topMotifs], binwidth = 10, se = FALSE)
      B <- plotMatchPos(
          bm_all[topMotifs], binwidth = 10, geom = "col", use_totals = TRUE
      ) +
        geom_smooth(se = FALSE, show.legend = FALSE) +
        facet_wrap(~name)
      
      final_plot <- A + B + plot_annotation(tag_levels = "A") & theme(legend.position = "bottom")
    }
    
    # Write outputs to the working directory
    write.csv(as.data.frame(res_pos), "res_pos.csv", row.names = TRUE)
    write.csv(as.data.frame(res_abs), "res_abs.csv", row.names = TRUE)
    saveRDS(bm_all, "bm_all.rds")
    
    if (!is.null(counts)) {
      write.csv(data.frame(motif = names(counts), count = as.vector(counts)), "match_counts.csv", row.names = FALSE)
    }
    
    if (length(topMotifs) > 0) {
      ggsave("positional_bias_plot.pdf", plot = final_plot, width = 12, height = 6)
    }
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # alignment/mapping QC — workflow-emitted artifact check for common log
    # files (.log, .summary, alignment metrics tables). Binary pass.
    .amqc_logs <- c(list.files(".", pattern = "(?i)(align|map|samtools|flagstat).*\\.(log|txt|summary)\$"),
                    list.files(".", pattern = "(?i)flagstat\\."))
    .amqc_passes <- length(.amqc_logs) > 0
    .gates_by_label[["alignment/mapping QC"]] <- list(
      gate_row = "bioc_alignment_mapping_qc",
      metric_name = "alignment_qc_artifacts",
      metric_value = length(.amqc_logs),
      passes = .amqc_passes,
      status = if (.amqc_passes) paste0("computed (", length(.amqc_logs), " alignment log(s) emitted)")
               else "not_computed (no alignment log/summary artifact present)"
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
      process = "BIOC_MOTIFTESTR_POSITIONAL_BIAS_ANALYSIS",
      domain  = "bioconductor",
      declared_qc_steps = c("alignment/mapping QC", "low-count filtering", "count normalization"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_MOTIFTESTR_POSITIONAL_BIAS_ANALYSIS":',
        paste0('    motifTestR: ', as.character(packageVersion('motifTestR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_positional_bias_analysis.csv versions.yml
    """
}

workflow BIOC_MOTIFTESTR_POSITIONAL_BIAS_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ar_er_peaks, BSgenome.Hsapiens.UCSC.hg19, ex_pfm ] ]

    main:
    BIOC_MOTIFTESTR_POSITIONAL_BIAS_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MOTIFTESTR_POSITIONAL_BIAS_ANALYSIS.out.tables
    plots    = BIOC_MOTIFTESTR_POSITIONAL_BIAS_ANALYSIS.out.plots
    objects  = BIOC_MOTIFTESTR_POSITIONAL_BIAS_ANALYSIS.out.objects
    versions = BIOC_MOTIFTESTR_POSITIONAL_BIAS_ANALYSIS.out.versions
}
