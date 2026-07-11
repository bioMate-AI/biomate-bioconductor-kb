#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: dmrseq — dmr_detection
// Scan the genome to detect and perform inference on local differentially methylated regions (DMRs) from WGBS count data.
// Input: sample_bismark.cov.gz, sample_metadata.csv
// Container: quay.io/biocontainers/bioconductor-dmrseq:1.30.0--r45hdfd78af_0
// R packages: DelayedMatrixStats, GenomicRanges, annotatr, BiocParallel, bsseq, dmrseq
// Bioconductor: 3.20 | R: 4.4
// Requires: DelayedMatrixStats, GenomicRanges, annotatr, bsseq, dmrseq
// Visualizations: DMR plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load Bismark coverage files into a BSseq object using read.bismark
//  * 2. [Core Analysis] Add sample metadata to the pData slot of the BSseq object
//  * 3. [Core Analysis] Filter out CpGs with zero coverage and subset samples
//  * 4. [Core Analysis] Run dmrseq to detect candidate regions and perform permutation-based inference
//  * 5. [Core Analysis] Extract significant regions and calculate raw mean differences using meanDiff
//  * 6. [Visualization & Output] Visualize DMRs and empirical distributions using plotDMRs and plotEmpiricalDistribution

nextflow.enable.dsl = 2

process BIOC_DMRSEQ_DMR_DETECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("DelayedMatrixStats", "GenomicRanges", "annotatr", "BiocParallel", "bsseq", "dmrseq")
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
                    
        library(dmrseq)
        library(bsseq)
        library(DelayedMatrixStats)
        library(GenomicRanges)
        library(annotatr)
        
        # ==========================================
        # STAGE 1: Load Bismark coverage files into a BSseq object
        # ==========================================
        
        # Read user metadata
        metadata <- read.csv("sample_metadata.csv", stringsAsFactors = FALSE)
        
        # dmrseq requires at least 2 samples per condition (minimum 4 samples total for 2 groups)
        if (nrow(metadata) < 4) {
          stop("dmrseq requires at least 2 samples per condition (minimum 4 samples total).")
        }
        
        # Dynamically use sample names and conditions from metadata
        sampleNames <- metadata[[1]]
        condition <- metadata[[2]]
        
        # Read the Bismark coverage files
        infiles <- paste0(sampleNames, "_bismark.cov.gz")
        
        bs <- read.bismark(files = infiles,
                           colData = data.frame(row.names = sampleNames),
                           rmZeroCov = TRUE,
                           strandCollapse = FALSE,
                           verbose = TRUE)
        show(bs)
        
        # ==========================================
        # STAGE 2: Add sample metadata to the pData slot
        # ==========================================
        
        pData(bs)\$Condition <- condition
        pData(bs)\$Replicate <- ave(seq_along(condition), condition, FUN = seq_along)
        
        pData(bs)
        
        # ==========================================
        # STAGE 3: Filter out CpGs with zero coverage and subset samples
        # ==========================================
        
        loci.idx <- which(DelayedMatrixStats::rowSums2(getCoverage(bs, type="Cov")==0) == 0)
        sample.idx <- which(pData(bs)\$Condition %in% unique(condition))
        
        bs.filtered <- bs[loci.idx, sample.idx]
        
        # ==========================================
        # STAGE 4: Run dmrseq to detect candidate regions and perform inference
        # ==========================================
        
        testCovariate <- "Condition"
        regions <- dmrseq(bs=bs.filtered,
                          cutoff = 0.05,
                          testCovariate=testCovariate)
        show(regions)
        
        # Run block detection
        blocks <- dmrseq(bs=bs.filtered,
                          cutoff = 0.05,
                          testCovariate=testCovariate,
                          block = TRUE,
                          minInSpan = 500,
                          bpSpan = 5e4,
                          maxGapSmooth = 1e6,
                          maxGap = 5e3)
        head(blocks)
        
        # ==========================================
        # STAGE 5: Extract significant regions and calculate raw mean differences
        # ==========================================
        
        sum(regions\$qval < 0.05, na.rm = TRUE)
        
        sigRegions <- regions[which(regions\$qval < 0.05),]
        
        if (length(sigRegions) > 0) {
          print(sum(sigRegions\$stat > 0) / length(sigRegions))
          
          rawDiff <- meanDiff(bs.filtered, dmrs=sigRegions, testCovariate=testCovariate)
          str(rawDiff)
          saveRDS(rawDiff, file="raw_mean_differences.rds")
        } else {
          message("No significant regions found at FDR 0.05.")
        }
        
        # Export tabular results
        write.csv(as.data.frame(regions), file="dmrseq_results.csv")
        write.csv(as.data.frame(blocks), file="dmrseq_blocks.csv")
        saveRDS(regions, file="regions.rds")
        saveRDS(blocks, file="blocks.rds")
        
        # ==========================================
        # STAGE 6: Visualize DMRs and empirical distributions
        # ==========================================
        
        pdf("dmr_plots.pdf", width = 10, height = 8)
        
        # Plot first DMR region
        if (length(regions) > 0) {
          tryCatch({
            plotDMRs(bs.filtered, regions=regions[1,], testCovariate=testCovariate)
          }, error = function(e) {
            message("Error plotting DMR: ", e\$message)
          })
        }
        
        # Plot first block region
        if (length(blocks) > 0) {
          tryCatch({
            plotDMRs(bs.filtered, regions=blocks[1,], testCovariate=testCovariate)
          }, error = function(e) {
            message("Error plotting block: ", e\$message)
          })
        }
        
        # Plot empirical distributions
        tryCatch({
          plotEmpiricalDistribution(bs.filtered, testCovariate=testCovariate)
        }, error = function(e) {
          message("Error plotting empirical distribution: ", e\$message)
        })
        
        tryCatch({
          plotEmpiricalDistribution(bs.filtered, testCovariate=testCovariate, 
                                    type="Cov", bySample=TRUE)
        }, error = function(e) {
          message("Error plotting empirical distribution by sample: ", e\$message)
        })
        
        dev.off()
        
        sessionInfo()
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # array detection QC — ExpressionSet detection p-values or detection-column data.frame.
    .adq_rate <- NA_real_
    for (.adq_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
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

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_DMRSEQ_DMR_DETECTION",
      domain  = "bioconductor",
      declared_qc_steps = c("array detection QC", "alignment/mapping QC", "low-count filtering"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_DMRSEQ_DMR_DETECTION":',
        paste0('    dmrseq: ', as.character(packageVersion('dmrseq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dmr_detection.csv versions.yml
    """
}

workflow BIOC_DMRSEQ_DMR_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sample_bismark.cov.gz, sample_metadata.csv ] ]

    main:
    BIOC_DMRSEQ_DMR_DETECTION(ch_input)

    emit:
    tables   = BIOC_DMRSEQ_DMR_DETECTION.out.tables
    plots    = BIOC_DMRSEQ_DMR_DETECTION.out.plots
    objects  = BIOC_DMRSEQ_DMR_DETECTION.out.objects
    versions = BIOC_DMRSEQ_DMR_DETECTION.out.versions
}
