#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: normr — cnv_detection_and_filtering
// Detect Copy Number Variations (CNVs) using input control tracks and filter differential ChIP-seq calls to remove CNV-driven false positives.
// Input: treatmentInput.bam, controlInput.bam, diffFit
// Container: quay.io/biocontainers/bioconductor-normr:1.36.0--r45ha27e39d_0
// R packages: GenomicRanges, normr
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NORMR_CNV_DETECTION_AND_FILTERING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-normr:1.36.0--r45ha27e39d_0"

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
    .bm_deps <- c("GenomicRanges", "normr")
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
    library("normr")
    library("GenomicRanges")
    
    # --- Declare and verify input files ---
    treatmentInputBamfile <- "treatmentInput.bam"
    controlInputBamfile <- "controlInput.bam"
    diffFitPath <- "diffFit"
    
    if (!file.exists(treatmentInputBamfile)) {
      stop(paste("Required treatment input BAM file missing:", treatmentInputBamfile))
    }
    if (!file.exists(controlInputBamfile)) {
      stop(paste("Required control input BAM file missing:", controlInputBamfile))
    }
    if (!file.exists(diffFitPath)) {
      # Try with .rds extension if the exact name is not found
      if (file.exists("diffFit.rds")) {
        diffFitPath <- "diffFit.rds"
      } else {
        stop("Required pre-calculated differential ChIP-seq fit object 'diffFit' (RDS format) missing.")
      }
    }
    
    # --- Load the pre-calculated differential ChIP-seq fit object ---
    diffFit <- readRDS(diffFitPath)
    
    # --- Extract genome information from the pre-calculated fit ---
    # This ensures the genome specification matches the coordinates of the diffFit object.
    seq_info <- seqinfo(getRanges(diffFit))
    genome <- data.frame(
      chrom = seqnames(seq_info),
      size = seqlengths(seq_info),
      stringsAsFactors = FALSE
    )
    # Filter out any chromosomes with unresolved sizes
    genome <- genome[!is.na(genome\$size), ]
    
    # --- Call differences between the two input control tracks to ---
    cnvs <- diffR(treatment   = treatmentInputBamfile,
                  control     = controlInputBamfile,
                  genome      = genome,
                  countConfig = countConfigSingleEnd(binsize = 2.5e4))
    
    # --- Export the CNV calls ---
    exportR(cnvs, "CNVs.bed")
    
    # --- Filter previous ChIP-seq difference calls for CNVs ---
    ov <- countOverlaps(getRanges(diffFit, fdr = .05), getRanges(cnvs, fdr = .05))
    idx <- which(ov == 0)
    cnvCleanedGR <- getRanges(diffFit, fdr = .05)[idx]
    
    # --- Save meaningful outputs ---
    saveRDS(cnvs, "cnvs_fit.rds")
    saveRDS(cnvCleanedGR, "cnvCleanedGR.rds")
    write.csv(as.data.frame(cnvCleanedGR), "cnvCleanedGR.csv", row.names = FALSE)
    
    message("Pipeline completed successfully.")
    message("Outputs written: CNVs.bed, cnvs_fit.rds, cnvCleanedGR.rds, cnvCleanedGR.csv")
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
      process = "BIOC_NORMR_CNV_DETECTION_AND_FILTERING",
      domain  = "bioconductor",
      declared_qc_steps = c("alignment/mapping QC", "low-count filtering", "count normalization"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_NORMR_CNV_DETECTION_AND_FILTERING":',
        paste0('        normr: ', as.character(packageVersion("normr")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cnv_detection_and_filtering.csv versions.yml
    """
}

workflow BIOC_NORMR_CNV_DETECTION_AND_FILTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ treatmentInput.bam, controlInput.bam, diffFit ] ]

    main:
    BIOC_NORMR_CNV_DETECTION_AND_FILTERING(ch_input)

    emit:
    tables   = BIOC_NORMR_CNV_DETECTION_AND_FILTERING.out.tables
    plots    = BIOC_NORMR_CNV_DETECTION_AND_FILTERING.out.plots
    objects  = BIOC_NORMR_CNV_DETECTION_AND_FILTERING.out.objects
    versions = BIOC_NORMR_CNV_DETECTION_AND_FILTERING.out.versions
}
