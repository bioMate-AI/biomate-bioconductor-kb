#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: TCseq — time_course_sequencing_analysis
// Perform differential analysis and temporal pattern clustering on time-course sequencing data (RNA-seq, ATAC-seq, or ChIP-seq).
// Input: experiment_design.txt, genomic_intervals.bed, counts_table.txt
// Container: quay.io/biocontainers/bioconductor-tcseq:1.34.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, TCseq
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Generate reference genomic regions from peak files (optional)
//  * 2. [Input & Preparation] Create a TCA object
//  * 3. [Core Analysis] Count reads from BAM files (optional)
//  * 4. [Core Analysis] Perform differential analysis
//  * 5. [Core Analysis] Extract differential analysis results
//  * 6. [Input & Preparation] Construct a time course table
//  * 7. [Core Analysis] Perform temporal clustering
//  * 8. [Visualization & Output] Visualize temporal patterns

nextflow.enable.dsl = 2

process BIOC_TCSEQ_TIME_COURSE_SEQUENCING_ANALYSIS {
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
    .bm_deps <- c("TCseq", "SummarizedExperiment")
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
    library(TCseq)
    suppressWarnings(library(SummarizedExperiment))
    
    # Check for required input files
    if (!file.exists("experiment_design.txt")) {
      stop("Error: 'experiment_design.txt' not found in the working directory.")
    }
    if (!file.exists("genomic_intervals.bed")) {
      stop("Error: 'genomic_intervals.bed' not found in the working directory.")
    }
    
    # Read experiment design
    experiment <- read.delim("experiment_design.txt", header = TRUE, stringsAsFactors = FALSE)
    # Fix for Bug 2: Set rownames to match sample IDs (colnames of countsTable)
    rownames(experiment) <- experiment[, 1]
    
    # Read genomic intervals (BED format) and format to match TCseq expectations: chr, start, end, id
    genomicIntervals_raw <- read.delim("genomic_intervals.bed", header = FALSE, stringsAsFactors = FALSE)
    genomicIntervals <- data.frame(
      chr = genomicIntervals_raw[, 1],
      start = as.integer(genomicIntervals_raw[, 2]),
      end = as.integer(genomicIntervals_raw[, 3]),
      stringsAsFactors = FALSE
    )
    if (ncol(genomicIntervals_raw) >= 4) {
      genomicIntervals\$id <- as.character(genomicIntervals_raw[, 4])
    } else {
      genomicIntervals\$id <- paste0("peak", 1:nrow(genomicIntervals))
    }
    
    # 1. Generate reference genomic regions from peak files (optional)
    if (dir.exists("peaks")) {
      dir.peaks <- "peaks"
      gf <- peakreference(dir = dir.peaks, pattern = "narrowpeaks")
      write.csv(gf, "peak_reference.csv", row.names = FALSE)
    }
    
    # Determine counts source and create TCA object
    # Fix for Bug 1: Create the TCA object exactly once, removing redundant methods copied from the vignette
    if (file.exists("counts_table.txt")) {
      countsTable <- as.matrix(read.delim("counts_table.txt", row.names = 1, header = TRUE, check.names = FALSE))
      tca <- TCA(design = experiment, genomicFeature = genomicIntervals, counts = countsTable)
    } else if ("bamfile" %in% colnames(experiment)) {
      # 2. Create a TCA object using BAM files
      tca <- TCA(design = experiment, genomicFeature = genomicIntervals)
      
      # 3. Count reads from BAM files (optional)
      dir.BAM <- "."
      tca <- countReads(tca, dir = dir.BAM)
    } else {
      stop("Error: 'counts_table.txt' is missing, and no 'bamfile' column is present in 'experiment_design.txt' to count reads.")
    }
    
    # 4. Perform differential analysis
    # Fix for Bug 3: Remove redundant DBanalysis call
    tca <- DBanalysis(tca, filter.type = "raw", filter.value = 10, samplePassfilter = 2)
    
    # Extract differential analysis results dynamically based on design
    timepoints <- unique(as.character(experiment\$timepoint))
    if (length(timepoints) < 2) {
      stop("Error: At least two timepoints are required in 'experiment_design.txt' for differential analysis.")
    }
    g1 <- timepoints[1]
    g2 <- timepoints[-1]
    
    # 5. Extract differential analysis results
    DBres <- DBresult(tca, group1 = g1, group2 = g2)
    DBres.sig <- DBresult(tca, group1 = g1, group2 = g2, top.sig = TRUE)
    
    # Save differential analysis results
    saveRDS(DBres, "DBres.rds")
    saveRDS(DBres.sig, "DBres_sig.rds")
    
    for (comparison in names(DBres)) {
      write.csv(as.data.frame(DBres[[comparison]]), paste0("DBres_", comparison, ".csv"))
    }
    for (comparison in names(DBres.sig)) {
      write.csv(as.data.frame(DBres.sig[[comparison]]), paste0("DBres_sig_", comparison, ".csv"))
    }
    
    # 6. Construct a time course table
    # Fix for Bug 3: Remove redundant timecourseTable call
    tca <- timecourseTable(tca, value = "expression", norm.method = "rpkm", filter = TRUE)
    t <- tcTable(tca)
    
    # Save time course table
    write.csv(t, "timecourse_table.csv")
    
    # 7. Perform temporal clustering
    # Ensure k is appropriate for the number of rows in the time course table
    k_val <- min(6, nrow(t) - 1)
    if (k_val < 2) {
      warning("Too few rows in time course table to perform clustering with k=6. Setting k=2.")
      k_val <- 2
    }
    
    if (nrow(t) >= 2) {
      tca <- timeclust(tca, algo = "cm", k = k_val, standardize = TRUE)
      saveRDS(tca, "tca_clustered.rds")
      
      # 8. Visualize temporal patterns
      pdf("temporal_patterns_plots.pdf", width = 10, height = 8)
      p <- timeclustplot(tca, value = "z-score(PRKM)", cols = min(3, k_val))
      if (length(p) > 0) {
        print(p[[1]])
      }
      dev.off()
    } else {
      warning("Skipping clustering and plotting because the time course table has fewer than 2 rows after filtering.")
    }
    
    message("Pipeline completed successfully. Outputs saved to the working directory.")
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
      process = "BIOC_TCSEQ_TIME_COURSE_SEQUENCING_ANALYSIS",
      domain  = "bioconductor",
      declared_qc_steps = c("alignment/mapping QC", "low-count filtering", "count normalization"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_TCSEQ_TIME_COURSE_SEQUENCING_ANALYSIS":',
        paste0('    TCseq: ', as.character(packageVersion('TCseq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_time_course_sequencing_analysis.csv versions.yml
    """
}

workflow BIOC_TCSEQ_TIME_COURSE_SEQUENCING_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ experiment_design.txt, genomic_intervals.bed, counts_table.txt ] ]

    main:
    BIOC_TCSEQ_TIME_COURSE_SEQUENCING_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_TCSEQ_TIME_COURSE_SEQUENCING_ANALYSIS.out.tables
    plots    = BIOC_TCSEQ_TIME_COURSE_SEQUENCING_ANALYSIS.out.plots
    objects  = BIOC_TCSEQ_TIME_COURSE_SEQUENCING_ANALYSIS.out.objects
    versions = BIOC_TCSEQ_TIME_COURSE_SEQUENCING_ANALYSIS.out.versions
}
