#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: subSeq — subsampling_depth_analysis
// Subsample a count matrix at multiple depths, run differential expression analyses, and evaluate the impact of depth on significance and effect size estimates.
// Input: hammer.counts, hammer.design$protocol
// Container: quay.io/biocontainers/bioconductor-subseq:1.40.0--r45hdfd78af_0
// R packages: ggplot2, subSeq
// Bioconductor: 3.20 | R: 4.4
// Requires: subSeq
// Visualizations: plot (ggplot/base)
// QC: low-count filtering
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter out low-count genes
//  * 2. [Input & Preparation] Define logarithmic subsampling proportions
//  * 3. [Core Analysis] Perform subsampling and differential expression using subsample
//  * 4. [Visualization & Output] Summarize the subsamples using summary
//  * 5. [Visualization & Output] Plot the summary metrics using plot

nextflow.enable.dsl = 2

process BIOC_SUBSEQ_SUBSAMPLING_DEPTH_ANALYSIS {
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
    .bm_deps <- c("ggplot2", "subSeq")
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
    library(subSeq)
    
    # 1. Read the declared user input files from the working directory
    if (file.exists("hammer.counts")) {
      hammer.counts = tryCatch({
        readRDS("hammer.counts")
      }, error = function(e) {
        as.matrix(read.table("hammer.counts", header=TRUE, row.names=1, sep="", check.names=FALSE))
      })
    } else {
      stop("Error: 'hammer.counts' file not found in the working directory.")
    }
    
    if (file.exists("hammer.design\$protocol")) {
      protocol_vector = tryCatch({
        readRDS("hammer.design\$protocol")
      }, error = function(e) {
        readLines("hammer.design\$protocol")
      })
    } else {
      stop("Error: 'hammer.design\$protocol' file not found in the working directory.")
    }
    
    # Construct the hammer.design object to match the documented code's structure
    hammer.design = list(protocol = protocol_vector)
    
    # 2. Filter out low-count genes
    hammer.counts = hammer.counts[rowSums(hammer.counts) >= 5, ]
    
    # 3. Define logarithmic subsampling proportions
    proportions = 10^seq(-2, 0, .5)
    
    # 4. Perform subsampling and differential expression using subsample
    subsamples = subsample(hammer.counts, proportions, method=c("edgeR", "voomLimma"), treatment=hammer.design\$protocol)
    
    # 5. Summarize the subsamples using summary
    subsamples.summary = summary(subsamples)
    
    # 6. Plot the summary metrics using plot and save to PDF
    pdf("subsamples_summary_plots.pdf", width=10, height=8)
    plot(subsamples.summary)
    dev.off()
    
    # 7. Write additional meaningful outputs
    saveRDS(subsamples, "subsamples_results.rds")
    write.csv(as.data.frame(subsamples.summary), "subsamples_summary.csv", row.names=FALSE)
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

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_SUBSEQ_SUBSAMPLING_DEPTH_ANALYSIS",
      domain  = "bioconductor",
      declared_qc_steps = c("low-count filtering"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_SUBSEQ_SUBSAMPLING_DEPTH_ANALYSIS":',
        paste0('    subSeq: ', as.character(packageVersion('subSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_subsampling_depth_analysis.csv versions.yml
    """
}

workflow BIOC_SUBSEQ_SUBSAMPLING_DEPTH_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ hammer.counts, hammer.design$protocol ] ]

    main:
    BIOC_SUBSEQ_SUBSAMPLING_DEPTH_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SUBSEQ_SUBSAMPLING_DEPTH_ANALYSIS.out.tables
    plots    = BIOC_SUBSEQ_SUBSAMPLING_DEPTH_ANALYSIS.out.plots
    objects  = BIOC_SUBSEQ_SUBSAMPLING_DEPTH_ANALYSIS.out.objects
    versions = BIOC_SUBSEQ_SUBSAMPLING_DEPTH_ANALYSIS.out.versions
}
