#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DMRcaller — bisulfite_seq_replicates_analysis
// Identify DMRs from bisulfite sequencing data with biological replicates using beta regression.
// Input: replicates_joined.rds
// Container: quay.io/biocontainers/bioconductor-dmrcaller:1.42.0--r45ha27e39d_0
// R packages: DMRcaller, GenomicRanges
// Bioconductor: 3.20 | R: 4.4
// Requires: DMRcaller, GenomicRanges
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define condition vector
//  * 2. [Core Analysis] Compute DMRs across replicates using computeDMRsReplicates with test = "betareg"

nextflow.enable.dsl = 2

process BIOC_DMRCALLER_BISULFITE_SEQ_REPLICATES_ANALYSIS {
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
    .bm_deps <- c("DMRcaller", "GenomicRanges")
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
    library(DMRcaller)
    library(GenomicRanges)
    
    # Read the user input file
    # The user-provided replicates_joined.rds is a GRanges object containing joined methylation data with replicates
    syntheticDataReplicates <- readRDS("replicates_joined.rds")
    
    # 1. Define condition vector
    condition <- c("a", "a", "b", "b")
    
    # 2. Compute DMRs across replicates using computeDMRsReplicates with test = "betareg"
    # Keep every documented function call and its argument names EXACTLY as shown in the vignette
    DMRsReplicatesBins <- computeDMRsReplicates(methylationData = syntheticDataReplicates,
                                                condition = condition,
                                                regions = NULL,
                                                context = "CG",
                                                method = "bins",
                                                binSize = 100,
                                                test = "betareg",
                                                pseudocountM = 1,
                                                pseudocountN = 2,
                                                pValueThreshold = 0.01,
                                                minCytosinesCount = 4,
                                                minProportionDifference = 0.4,
                                                minGap = 0,
                                                minSize = 50,
                                                minReadsPerCytosine = 4,
                                                cores = 1)
    
    # Print the identified DMRs to console
    print(DMRsReplicatesBins)
    
    # Save the results to output files
    # Save as RDS object
    saveRDS(DMRsReplicatesBins, file = "DMRsReplicatesBins.rds")
    
    # Save as CSV table
    write.csv(as.data.frame(DMRsReplicatesBins), file = "DMRsReplicatesBins.csv", row.names = FALSE)
    
    # Generate a diagnostic plot of the identified DMRs and save as PDF
    pdf("DMRsReplicates_plot.pdf", width = 7, height = 5)
    if (length(DMRsReplicatesBins) > 0) {
      # Plot the distribution of DMR sizes
      hist(width(DMRsReplicatesBins), 
           main = "Distribution of Identified DMR Sizes", 
           xlab = "DMR Width (bp)", 
           col = "skyblue", 
           border = "white")
    } else {
      plot(1, type = "n", axes = FALSE, xlab = "", ylab = "", main = "No DMRs identified")
      text(1, 1, "No DMRs met the filtering criteria.", cex = 1.2)
    }
    dev.off()
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # array detection QC — ExpressionSet detection p-values or detection-column data.frame.
    .adq_rate <- NA_real_
    for (.adq_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .adq_obj <- tryCatch(readRDS(.adq_rds), error = function(e) NULL)
      .adq_pv <- NULL
      if (!is.null(.adq_obj)) {
        if (inherits(.adq_obj, "ExpressionSet")) {
          .adq_pv <- tryCatch(Biobase::assayDataElement(.adq_obj, "Detection"), error = function(e) NULL)
        } else if (is.matrix(.adq_obj) || is.data.frame(.adq_obj)) {
          .adq_cols <- grep("(?i)(detection|pvalue|pval)", colnames(.adq_obj), value = TRUE)
          if (length(.adq_cols) > 0) .adq_pv <- as.matrix(.adq_obj[, .adq_cols, drop = FALSE])
        }
      }
      if (!is.null(.adq_pv) && length(.adq_pv) > 0) {
        .adq_rate <- round(mean(as.numeric(.adq_pv) < 0.05, na.rm = TRUE), 4); break
      }
    }
    .gates_by_label[["array detection QC"]] <- list(
      gate_row = "bioc_array_detection_qc",
      metric_name = "detection_rate",
      metric_value = .adq_rate,
      passes = isTRUE(is.finite(.adq_rate) && .adq_rate >= 0.75),
      status = if (is.finite(.adq_rate)) "computed (probe-detection p<0.05 fraction)"
               else "not_computed (no ExpressionSet/detection-p .rds present)"
    )

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

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_DMRCALLER_BISULFITE_SEQ_REPLICATES_ANALYSIS",
      domain  = "bioconductor",
      declared_qc_steps = c("array detection QC", "alignment/mapping QC", "low-count filtering"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_DMRCALLER_BISULFITE_SEQ_REPLICATES_ANALYSIS":',
        paste0('    DMRcaller: ', as.character(packageVersion('DMRcaller')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bisulfite_seq_replicates_analysis.csv versions.yml
    """
}

workflow BIOC_DMRCALLER_BISULFITE_SEQ_REPLICATES_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ replicates_joined.rds ] ]

    main:
    BIOC_DMRCALLER_BISULFITE_SEQ_REPLICATES_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_DMRCALLER_BISULFITE_SEQ_REPLICATES_ANALYSIS.out.tables
    plots    = BIOC_DMRCALLER_BISULFITE_SEQ_REPLICATES_ANALYSIS.out.plots
    objects  = BIOC_DMRCALLER_BISULFITE_SEQ_REPLICATES_ANALYSIS.out.objects
    versions = BIOC_DMRCALLER_BISULFITE_SEQ_REPLICATES_ANALYSIS.out.versions
}
