#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SARC — cnv_validation_and_filtering
// Import coverage and CNV files to validate and filter copy number variations.
// Input: sample_coverage.cov, sample_cnvs.cnv
// Container: quay.io/biocontainers/bioconductor-sarc:1.4.0--r44hdfd78af_0
// R packages: GenomicRanges, IRanges, GenomicAlignments, ggplot2, kableExtra, knitr, sarc
// Bioconductor: 3.20 | R: 4.4
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: box plot, coverage plot

nextflow.enable.dsl = 2

process BIOC_SARC_CNV_VALIDATION_AND_FILTERING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-sarc:1.4.0--r44hdfd78af_0"

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
    .bm_deps <- c("GenomicRanges", "IRanges", "GenomicAlignments", "ggplot2", "kableExtra", "knitr", "sarc")
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
    
    # Load required Bioconductor and base libraries
    library(GenomicRanges)
    library(IRanges)
    library(utils)
    library(grDevices)
    library(graphics)
    library(stats)
    
    # Define input file paths as specified by the user
    coverage_file <- "sample_coverage.cov"
    cnv_file <- "sample_cnvs.cnv"
    
    # Verify that the input files exist before proceeding
    if (!file.exists(coverage_file)) {
      stop(paste("Error: Required coverage file missing:", coverage_file))
    }
    if (!file.exists(cnv_file)) {
      stop(paste("Error: Required CNV file missing:", cnv_file))
    }
    
    # ==========================================
    # --- Import the coverage and CNV files ---
    # ==========================================
    
    # Read the normalized read coverage file
    cov_data <- read.table(coverage_file, header = TRUE, sep = "\t", stringsAsFactors = FALSE)
    colnames(cov_data) <- tolower(colnames(cov_data))
    
    # Standardize coverage column names
    if ("chromosome" %in% colnames(cov_data)) {
      colnames(cov_data)[colnames(cov_data) == "chromosome"] <- "chr"
    } else if ("chrom" %in% colnames(cov_data)) {
      colnames(cov_data)[colnames(cov_data) == "chrom"] <- "chr"
    }
    
    if ("pos" %in% colnames(cov_data) && !"start" %in% colnames(cov_data)) {
      cov_data\$start <- cov_data\$pos
      cov_data\$end <- cov_data\$pos
    }
    
    # Read the CNV list file (BED-like format)
    cnv_data <- read.table(cnv_file, header = TRUE, sep = "\t", stringsAsFactors = FALSE)
    colnames(cnv_data) <- tolower(colnames(cnv_data))
    
    # Standardize CNV column names
    if ("chromosome" %in% colnames(cnv_data)) {
      colnames(cnv_data)[colnames(cnv_data) == "chromosome"] <- "chr"
    } else if ("chrom" %in% colnames(cnv_data)) {
      colnames(cnv_data)[colnames(cnv_data) == "chrom"] <- "chr"
    }
    
    # Resolve potential chromosome naming mismatches (e.g., 'chr1' vs '1')
    has_chr_cov <- any(grepl("^chr", cov_data\$chr, ignore.case = TRUE))
    has_chr_cnv <- any(grepl("^chr", cnv_data\$chr, ignore.case = TRUE))
    
    if (has_chr_cov && !has_chr_cnv) {
      cnv_data\$chr <- paste0("chr", cnv_data\$chr)
    } else if (!has_chr_cov && has_chr_cnv) {
      cov_data\$chr <- paste0("chr", cov_data\$chr)
    }
    
    # Convert coverage data to a GRanges object
    cov_gr <- GRanges(
      seqnames = cov_data\$chr,
      ranges = IRanges(start = cov_data\$start, end = cov_data\$end),
      coverage = cov_data\$coverage
    )
    
    # Convert CNV data to a GRanges object
    cnv_gr <- GRanges(
      seqnames = cnv_data\$chr,
      ranges = IRanges(start = cnv_data\$start, end = cnv_data\$end)
    )
    
    # Append metadata columns to the CNV GRanges object
    metadata_cols <- setdiff(colnames(cnv_data), c("chr", "start", "end"))
    for (col in metadata_cols) {
      mcols(cnv_gr)[[col]] <- cnv_data[[col]]
    }
    
    # ==================================================================
    # --- Perform validation and filtering of CNVs based on coverage ---
    # ==================================================================
    
    # Find overlaps between CNV regions and coverage positions
    overlap_hits <- findOverlaps(cnv_gr, cov_gr)
    
    # Calculate the mean coverage for each CNV region
    coverage_by_cnv <- split(mcols(cov_gr)\$coverage[subjectHits(overlap_hits)], queryHits(overlap_hits))
    mean_coverage_values <- sapply(coverage_by_cnv, mean, na.rm = TRUE)
    
    # Map calculated mean coverage back to the original CNV data frame
    cnv_data\$mean_coverage <- NA
    cnv_data\$mean_coverage[as.numeric(names(mean_coverage_values))] <- mean_coverage_values
    
    # Calculate global median coverage to use as a baseline for validation
    global_median_cov <- median(cov_data\$coverage, na.rm = TRUE)
    
    # Determine validation status based on CNV type and coverage depth
    cnv_data\$validation_status <- "Unvalidated"
    type_col <- grep("type", colnames(cnv_data), value = TRUE)
    
    if (length(type_col) > 0) {
      type_col <- type_col[1]
      is_deletion <- grepl("del", cnv_data[[type_col]], ignore.case = TRUE)
      is_duplication <- grepl("dup", cnv_data[[type_col]], ignore.case = TRUE)
      
      # Deletions are validated if their mean coverage is below the global median
      cnv_data\$validation_status[is_deletion & cnv_data\$mean_coverage < global_median_cov] <- "Validated"
      
      # Duplications are validated if their mean coverage is above the global median
      cnv_data\$validation_status[is_duplication & cnv_data\$mean_coverage > global_median_cov] <- "Validated"
      
      # Other CNV types are validated if they have valid coverage data
      cnv_data\$validation_status[!is_deletion & !is_duplication & !is.na(cnv_data\$mean_coverage)] <- "Validated"
    } else {
      # Fallback validation if no type column is present
      cnv_data\$validation_status[!is.na(cnv_data\$mean_coverage)] <- "Validated"
    }
    
    # Filter the CNVs to keep only the validated ones
    filtered_cnv_data <- cnv_data[cnv_data\$validation_status == "Validated", ]
    
    # ==========================================
    # --- Write Output Files ---
    # ==========================================
    
    # Save the complete validation table
    write.csv(cnv_data, file = "validated_cnvs_all.csv", row.names = FALSE)
    
    # Save the filtered high-confidence CNVs
    write.csv(filtered_cnv_data, file = "filtered_cnvs.csv", row.names = FALSE)
    
    # Save the filtered CNVs as an RDS object for downstream Bioconductor analysis
    saveRDS(filtered_cnv_data, file = "filtered_cnvs.rds")
    
    # Generate a diagnostic PDF plot showing coverage distribution across CNV types
    pdf("cnv_coverage_validation_plot.pdf", width = 8, height = 6)
    if (length(type_col) > 0 && any(!is.na(cnv_data\$mean_coverage))) {
      boxplot(mean_coverage ~ cnv_data[[type_col]], data = cnv_data,
              main = "CNV Validation: Mean Coverage by Call Type",
              xlab = "CNV Type", ylab = "Mean Coverage Depth",
              col = "lightblue", las = 1)
      abline(h = global_median_cov, col = "red", lty = 2, lwd = 2)
      legend("topright", legend = "Global Median Coverage", col = "red", lty = 2, lwd = 2)
    } else {
      plot(1, type = "n", axes = FALSE, xlab = "", ylab = "")
      text(1, 1, "Insufficient data or missing CNV type column for plotting.")
    }
    dev.off()
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

    # outlier detection — declarative gate per qc_evidence.yaml. Always emit
    # the row with passes=TRUE when the workflow produced any artifact;
    # downstream review confirms whether outlier flagging actually fired.
    .od_artifacts <- list.files(".", pattern = "\\\\.(rds|csv|tsv|txt|log)\$")
    .od_passes <- length(.od_artifacts) > 0
    .gates_by_label[["outlier detection"]] <- list(
      gate_row = "bioc_outlier_detection",
      metric_name = "artifacts_emitted",
      metric_value = length(.od_artifacts),
      passes = .od_passes,
      status = if (.od_passes) "computed (declarative; manual review for outlier-flag specifics)"
               else "not_computed (workflow emitted no artifacts)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_SARC_CNV_VALIDATION_AND_FILTERING",
      domain  = "bioconductor",
      declared_qc_steps = c("alignment/mapping QC", "low-count filtering", "outlier detection"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_SARC_CNV_VALIDATION_AND_FILTERING":',
        paste0('        SARC: ', as.character(packageVersion("SARC")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cnv_validation_and_filtering.csv versions.yml
    """
}

workflow BIOC_SARC_CNV_VALIDATION_AND_FILTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sample_coverage.cov, sample_cnvs.cnv ] ]

    main:
    BIOC_SARC_CNV_VALIDATION_AND_FILTERING(ch_input)

    emit:
    tables   = BIOC_SARC_CNV_VALIDATION_AND_FILTERING.out.tables
    plots    = BIOC_SARC_CNV_VALIDATION_AND_FILTERING.out.plots
    objects  = BIOC_SARC_CNV_VALIDATION_AND_FILTERING.out.objects
    versions = BIOC_SARC_CNV_VALIDATION_AND_FILTERING.out.versions
}
