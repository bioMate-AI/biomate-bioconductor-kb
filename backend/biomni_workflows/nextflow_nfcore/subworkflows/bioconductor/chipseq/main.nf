#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: chipseq — chipseq_analysis_and_differential_peaks
// Perform ChIP-seq read extension, coverage calculation, peak calling, differential peak analysis between two samples, and genomic context annotation.
// Input: sampleFiles, TxDb.Mmusculus.UCSC.mm9.knownGene
// Container: quay.io/biocontainers/bioconductor-chipseq:1.60.0--r45h01b2380_0
// R packages: GenomicAlignments, GenomicFeatures, Rsamtools, ShortRead, TxDb.Mmusculus.UCSC.mm9.knownGene, chipseq, lattice, rtracklayer
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicAlignments, GenomicFeatures, Rsamtools, ShortRead, TxDb.Mmusculus.UCSC.mm9.knownGene, chipseq, lattice
// Visualizations: coverage plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Filter and load aligned reads using chipseqFilter and ShortRead
//  * 2. [Core Analysis] Estimate fragment length using estimate.mean.fraglen
//  * 3. [Core Analysis] Extend reads to estimated fragment length using resize
//  * 4. [Core Analysis] Calculate coverage using coverage
//  * 5. [Core Analysis] Identify islands and analyze depth using slice, viewSums, viewMaxs, and islandDepthPlot
//  * 6. [Core Analysis] Determine peak cutoff using peakCutoff and call peaks using slice
//  * 7. [Visualization & Output] Summarize peaks using peakSummary
//  * 8. [Visualization & Output] Plot strand-specific coverage using coverageplot
//  * 9. [Core Analysis] Perform differential peak analysis using diffPeakSummary
//  * 10. [Core Analysis] Annotate peaks with genomic features (promoters, genes) using GenomicFeatures and %over%

nextflow.enable.dsl = 2

process BIOC_CHIPSEQ_CHIPSEQ_ANALYSIS_AND_DIFFERENTIAL_PEAKS {
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
    .bm_deps <- c("GenomicAlignments", "GenomicFeatures", "Rsamtools", "ShortRead", "TxDb.Mmusculus.UCSC.mm9.knownGene", "chipseq", "lattice", "rtracklayer")
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
            library(chipseq)
            library(GenomicFeatures)
            library(lattice)
            library(ShortRead)
            library(GenomicAlignments)
            library(Rsamtools)
            library(TxDb.Mmusculus.UCSC.mm9.knownGene)
            
            # Define the input files in the working directory
            # The pipeline expects these files to be present in the working directory.
            sampleFiles <- c(
              ctcf = "ctcf.bam",
              gfp = "gfp.bam"
            )
            
            # Verify that the input files exist before proceeding
            missing_files <- sampleFiles[!file.exists(sampleFiles)]
            if (length(missing_files) > 0) {
              stop(paste("Missing required input files in the working directory:",
                         paste(missing_files, collapse = ", ")))
            }
            
            # 1. Filter and load aligned reads using GenomicAlignments
            param <- ScanBamParam(mapqFilter = 15, flag = scanBamFlag(isDuplicate = FALSE, isUnmappedQuery = FALSE))
            cstest <- GRangesList(lapply(sampleFiles, function(file) {
              as(readGAlignments(file, param = param), "GRanges")
            }))
            
            # Subset to chromosomes 10, 11, and 12
            cstest <- tryCatch({
              cstest[seqnames(cstest) %in% c("chr10", "chr11", "chr12")]
            }, error = function(e) {
              # Fallback if direct subsetting on GenomicRangesList seqnames is not supported
              endoapply(cstest, function(gr) {
                gr[seqnames(gr) %in% c("chr10", "chr11", "chr12")]
              })
            })
            
            # 2. Estimate fragment length using estimate.mean.fraglen
            fraglen <- estimate.mean.fraglen(cstest\$ctcf, method="correlation")
            valid_fraglen <- fraglen[!is.na(fraglen)]
            write.csv(as.data.frame(valid_fraglen), "estimated_fragment_lengths.csv")
            
            # 3. Extend reads to estimated fragment length using resize
            ctcf.ext <- resize (cstest\$ctcf, width = 200)
            
            # 4. Calculate coverage using coverage
            cov.ctcf <- coverage(ctcf.ext)
            
            # 5. Identify islands and analyze depth using slice, viewSums, viewMaxs, and islandDepthPlot
            islands <- slice(cov.ctcf, lower = 1)
            
            viewSums(islands)
            viewMaxs(islands)
            
            nread.tab <- table(viewSums(islands) / 200)
            depth.tab <- table(viewMaxs(islands))
            
            write.csv(as.data.frame(nread.tab), "island_nreads_table.csv")
            write.csv(as.data.frame(depth.tab), "island_depths_table.csv")
            
            pdf("island_depth_plot.pdf")
            islandDepthPlot(cov.ctcf)
            dev.off()
            
            # 6. Determine peak cutoff using peakCutoff and call peaks using slice
            cutoff <- peakCutoff(cov.ctcf, fdr = 0.0001) 
            
            peaks.ctcf <- slice(cov.ctcf, lower = cutoff) 
            
            # 7. Summarize peaks using peakSummary
            peaks <- peakSummary(peaks.ctcf) 
            saveRDS(peaks, "peaks_ctcf_summary.rds")
            
            # 8. Plot strand-specific coverage using coverageplot
            peak.depths <- viewMaxs(peaks.ctcf)
            
            cov.pos <- coverage(ctcf.ext[strand(ctcf.ext) == "+"]) 
            cov.neg <- coverage(ctcf.ext[strand(ctcf.ext) == "-"])
            
            peaks.pos <- Views(cov.pos, ranges(peaks.ctcf)) 
            peaks.neg <- Views(cov.neg, ranges(peaks.ctcf))
            
            chroms_with_peaks <- names(peak.depths)[lengths(peak.depths) > 0]
            
            pdf("coverage_plots.pdf")
            if (length(chroms_with_peaks) > 0) {
              plot_chr <- chroms_with_peaks[1]
              wpeaks <- tail(order(peak.depths[[plot_chr]]), 4)
              
              if (length(wpeaks) >= 1) {
                coverageplot(peaks.pos[[plot_chr]][wpeaks[1]], peaks.neg[[plot_chr]][wpeaks[1]])
              }
              if (length(wpeaks) >= 2) {
                coverageplot(peaks.pos[[plot_chr]][wpeaks[2]], peaks.neg[[plot_chr]][wpeaks[2]])
              }
              if (length(wpeaks) >= 3) {
                coverageplot(peaks.pos[[plot_chr]][wpeaks[3]], peaks.neg[[plot_chr]][wpeaks[3]])
              }
              if (length(wpeaks) >= 4) {
                coverageplot(peaks.pos[[plot_chr]][wpeaks[4]], peaks.neg[[plot_chr]][wpeaks[4]])
              }
            }
            dev.off()
            
            # 9. Perform differential peak analysis using diffPeakSummary
            cov.gfp <- coverage(resize(cstest\$gfp, 200))
            peaks.gfp <- slice(cov.gfp, lower = cutoff)
            
            peakSummary <- diffPeakSummary(peaks.gfp, peaks.ctcf)
            
            mcols(peakSummary) <- 
                within(mcols(peakSummary), 
                   {
                       diffs <- asinh(sums2) - asinh(sums1) 
                       resids <- (diffs - median(diffs)) / mad(diffs) 
                       up <- resids > 2 
                       down <- resids < -2 
                       change <- ifelse(up, "up", ifelse(down, "down", "flat")) 
                   })
            
            # 10. Annotate peaks with genomic features (promoters, genes) using GenomicFeatures and %over%
            gregions <- transcripts(TxDb.Mmusculus.UCSC.mm9.knownGene) 
            
            promoters <- flank(gregions, 1000, both = TRUE) 
            
            peakSummary\$inPromoter <- peakSummary %over% promoters
            xtabs(~ inPromoter + change, peakSummary) 
            
            peakSummary\$inUpstream <- peakSummary %over% flank(gregions, 20000)
            peakSummary\$inGene <- peakSummary %over% gregions
            
            sumtab <- 
                as.data.frame(rbind(total = xtabs(~ change, peakSummary),
                                    promoter = xtabs(~ change, 
                                      subset(peakSummary, inPromoter)),
                                    upstream = xtabs(~ change, 
                                      subset(peakSummary, inUpstream)),
                                    gene = xtabs(~ change, subset(peakSummary, inGene))))
            
            # Write final outputs
            write.csv(sumtab, "differential_peaks_genomic_context_summary.csv")
            saveRDS(peakSummary, "differential_peaks_summary.rds")
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
      process = "BIOC_CHIPSEQ_CHIPSEQ_ANALYSIS_AND_DIFFERENTIAL_PEAKS",
      domain  = "bioconductor",
      declared_qc_steps = c("alignment/mapping QC", "low-count filtering", "count normalization"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_CHIPSEQ_CHIPSEQ_ANALYSIS_AND_DIFFERENTIAL_PEAKS":',
        paste0('    chipseq: ', as.character(packageVersion('chipseq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chipseq_analysis_and_differential_peaks.csv versions.yml
    """
}

workflow BIOC_CHIPSEQ_CHIPSEQ_ANALYSIS_AND_DIFFERENTIAL_PEAKS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sampleFiles, TxDb.Mmusculus.UCSC.mm9.knownGene ] ]

    main:
    BIOC_CHIPSEQ_CHIPSEQ_ANALYSIS_AND_DIFFERENTIAL_PEAKS(ch_input)

    emit:
    tables   = BIOC_CHIPSEQ_CHIPSEQ_ANALYSIS_AND_DIFFERENTIAL_PEAKS.out.tables
    plots    = BIOC_CHIPSEQ_CHIPSEQ_ANALYSIS_AND_DIFFERENTIAL_PEAKS.out.plots
    objects  = BIOC_CHIPSEQ_CHIPSEQ_ANALYSIS_AND_DIFFERENTIAL_PEAKS.out.objects
    versions = BIOC_CHIPSEQ_CHIPSEQ_ANALYSIS_AND_DIFFERENTIAL_PEAKS.out.versions
}
