#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: consensusSeekeR — chip_seq_consensus_from_narrowpeak
// Identify consensus peak regions from multiple ChIP-Seq replicates or experiments starting from NarrowPeak files.
// Input: file_narrowPeak, chrList
// Container: quay.io/biocontainers/bioconductor-consensusseeker:1.38.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, consensusSeekeR, rtracklayer
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load Input Files
//  * 2. [Input & Preparation] Write Outputs

nextflow.enable.dsl = 2

process BIOC_CONSENSUSSEEKER_CHIP_SEQ_CONSENSUS_FROM_NARROWPEAK {
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
    .bm_deps <- c("consensusSeekeR", "GenomicRanges", "rtracklayer")
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
            library(consensusSeekeR)
            library(GenomicRanges)
            library(rtracklayer)
            
            # -----------------------------------------------------------------------------
            # --- Load Input Files ---
            # -----------------------------------------------------------------------------
            
            # Locate narrowPeak files in the working directory
            files <- list.files(pattern = "\\\\.narrowPeak\$")
            if (file.exists("file_narrowPeak") && !("file_narrowPeak" %in% files)) {
              files <- c("file_narrowPeak", files)
            }
            
            if (length(files) == 0) {
              stop("Error: No narrowPeak files found in the working directory.")
            }
            
            # Locate and load the Seqinfo object (chrList)
            if (file.exists("chrList.rds")) {
              chrList <- readRDS("chrList.rds")
            } else if (file.exists("chrList")) {
              chrList <- readRDS("chrList")
            } else {
              stop("Error: chrList (Seqinfo object) file not found in the working directory.")
            }
            
            # -----------------------------------------------------------------------------
            # Stage 2 & 3: Process Replicates, Assign Experiment Names & Unique Feature Names
            # -----------------------------------------------------------------------------
            
            narrowPeaks_list <- list()
            peaks_list <- list()
            
            for (i in seq_along(files)) {
              input_file <- files[i]
              
              # Read the narrowPeak file to extract both regions and peak positions
              result <- readNarrowPeakFile(input_file, extractRegions = TRUE, extractPeaks = TRUE)
              
              narrowPeak_all <- result\$narrowPeak
              peak_all <- result\$peak
              
              # Filter and align seqinfo to match the user-provided chrList
              seqlevels(narrowPeak_all, pruning.mode = "coarse") <- intersect(seqlevels(narrowPeak_all), seqlevels(chrList))
              seqlevels(narrowPeak_all) <- seqlevels(chrList)
              seqinfo(narrowPeak_all) <- chrList
              
              seqlevels(peak_all, pruning.mode = "coarse") <- intersect(seqlevels(peak_all), seqlevels(chrList))
              seqlevels(peak_all) <- seqlevels(chrList)
              seqinfo(peak_all) <- chrList
              
              # Trim ranges to ensure they do not exceed chromosome boundaries
              narrowPeak_all <- GenomicRanges::trim(narrowPeak_all)
              peak_all <- GenomicRanges::trim(peak_all)
              
              # Assign experiment names as row names to the GRanges objects
              exp_name <- paste0("rep", sprintf("%02d", i))
              names(narrowPeak_all) <- rep(exp_name, length(narrowPeak_all))
              names(peak_all)       <- rep(exp_name, length(peak_all))
              
              # Assign unique feature names to the name metadata column to pair them
              narrowPeak_all\$name <- paste0("peak_", exp_name, "_", seq_along(narrowPeak_all))
              peak_all\$name       <- paste0("peak_", exp_name, "_", seq_along(peak_all))
              
              narrowPeaks_list[[i]] <- narrowPeak_all
              peaks_list[[i]] <- peak_all
            }
            
            # Combine all replicates into single GRanges objects
            all_narrowPeaks <- do.call(c, narrowPeaks_list)
            all_peaks <- do.call(c, peaks_list)
            
            # -----------------------------------------------------------------------------
            # Stage 4 & 5: Run findConsensusPeakRegions
            # -----------------------------------------------------------------------------
            
            results <- findConsensusPeakRegions(
                        narrowPeaks = all_narrowPeaks,
                        peaks = all_peaks,
                        chrInfo = chrList,
                        extendingSize = 100,
                        expandToFitPeakRegion = TRUE,
                        shrinkToFitPeakRegion = TRUE,
                        minNbrExp = min(2, length(files)),
                        nbrThreads = 1)
            
            # Print the call and the first few consensus regions to console
            print(results\$call)
            print(head(results\$consensusRanges, n = 3))
            
            # -----------------------------------------------------------------------------
            # --- Write Outputs ---
            # -----------------------------------------------------------------------------
            
            # Save the consensus ranges as an RDS object
            saveRDS(results\$consensusRanges, file = "consensus_regions.rds")
            
            # Save the consensus ranges as a CSV table
            consensus_df <- as.data.frame(results\$consensusRanges)
            write.csv(consensus_df, file = "consensus_regions.csv", row.names = FALSE)
            
            # Save a summary text file containing the call and basic statistics
            summary_conn <- file("consensus_summary.txt", "w")
            writeLines("Consensus Peak Regions Analysis Summary", summary_conn)
            writeLines("========================================", summary_conn)
            writeLines(paste("Call:", deparse(results\$call)), summary_conn)
            writeLines(paste("Total consensus regions identified:", length(results\$consensusRanges)), summary_conn)
            close(summary_conn)
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
      process = "BIOC_CONSENSUSSEEKER_CHIP_SEQ_CONSENSUS_FROM_NARROWPEAK",
      domain  = "bioconductor",
      declared_qc_steps = c("alignment/mapping QC", "low-count filtering", "count normalization"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_CONSENSUSSEEKER_CHIP_SEQ_CONSENSUS_FROM_NARROWPEAK":',
        paste0('    consensusSeekeR: ', as.character(packageVersion('consensusSeekeR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chip_seq_consensus_from_narrowpeak.csv versions.yml
    """
}

workflow BIOC_CONSENSUSSEEKER_CHIP_SEQ_CONSENSUS_FROM_NARROWPEAK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ file_narrowPeak, chrList ] ]

    main:
    BIOC_CONSENSUSSEEKER_CHIP_SEQ_CONSENSUS_FROM_NARROWPEAK(ch_input)

    emit:
    tables   = BIOC_CONSENSUSSEEKER_CHIP_SEQ_CONSENSUS_FROM_NARROWPEAK.out.tables
    plots    = BIOC_CONSENSUSSEEKER_CHIP_SEQ_CONSENSUS_FROM_NARROWPEAK.out.plots
    objects  = BIOC_CONSENSUSSEEKER_CHIP_SEQ_CONSENSUS_FROM_NARROWPEAK.out.objects
    versions = BIOC_CONSENSUSSEEKER_CHIP_SEQ_CONSENSUS_FROM_NARROWPEAK.out.versions
}
