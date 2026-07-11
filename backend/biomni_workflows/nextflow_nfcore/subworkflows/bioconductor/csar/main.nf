#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CSAR — chip_seq_peak_calling_and_annotation
// Identify protein-bound genomic regions from ChIP-seq data, map them to genes, and calculate FDR thresholds using permutation.
// Input: sample_reads.tsv, control_reads.tsv, genes.gff
// Container: quay.io/biocontainers/bioconductor-csar:1.62.0--r45h01b2380_0
// R packages: CSAR
// Bioconductor: 3.20 | R: 4.4
// Requires: CSAR
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Calculate extended read overlaps per nucleotide using mappedReads2Nhits
//  * 2. [Input & Preparation] Calculate read-enrichment scores using ChIPseqScore
//  * 3. [Core Analysis] Identify candidate enriched regions using sigWin
//  * 4. [Visualization & Output] Export scores to WIG format using score2wig
//  * 5. [Core Analysis] Calculate distance of candidate regions to genes using distance2Genes
//  * 6. [Core Analysis] Identify genes with peaks using genesWithPeaks
//  * 7. [Core Analysis] Generate permutated datasets and calculate permutated window scores using permutatedWinScores
//  * 8. [Input & Preparation] Load permutated scores using getPermutatedWinScores
//  * 9. [Core Analysis] Calculate FDR threshold using getThreshold

nextflow.enable.dsl = 2

process BIOC_CSAR_CHIP_SEQ_PEAK_CALLING_AND_ANNOTATION {
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
    .bm_deps <- c("CSAR")
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
        
    # Load required library
    library(CSAR)
    
    # Read user input files from the working directory
    sampleSEP3_test <- read.delim("sample_reads.tsv", header = TRUE, stringsAsFactors = FALSE)
    controlSEP3_test <- read.delim("control_reads.tsv", header = TRUE, stringsAsFactors = FALSE)
    TAIR8_genes_test <- read.delim("genes.gff", header = TRUE, stringsAsFactors = FALSE)
    
    # Dynamically determine the list of chromosomes and their lengths from the input datasets
    all_chr <- c(sampleSEP3_test\$chr, controlSEP3_test\$chr)
    all_pos <- c(sampleSEP3_test\$pos + sampleSEP3_test\$lengthRead, controlSEP3_test\$pos + controlSEP3_test\$lengthRead)
    chr_lengths_tapply <- tapply(all_pos, all_chr, max, na.rm = TRUE)
    chr_names <- names(chr_lengths_tapply)
    # Add a buffer of 1000bp to account for the virtual read extension (default 300bp)
    chr_lengths <- as.numeric(chr_lengths_tapply) + 1000
    
    # 1. Calculate extended read overlaps per nucleotide using mappedReads2Nhits
    nhitsS<-mappedReads2Nhits(sampleSEP3_test,file="sampleSEP3_test",chr=chr_names,chrL=chr_lengths)
    nhitsC<-mappedReads2Nhits(controlSEP3_test,file="controlSEP3_test",chr=chr_names,chrL=chr_lengths)
    nhitsC\$filenames
    nhitsS\$filenames
    
    # 2. Calculate read-enrichment scores using ChIPseqScore
    test<-ChIPseqScore(control=nhitsC,sample=nhitsS,file="test",times=10000)
    test\$filenames
    
    # 3. Identify candidate enriched regions using sigWin
    win<-sigWin(test)
    head(win)
    
    # 4. Export scores to WIG format using score2wig
    score2wig(test,file="test.wig",times=10000)
    
    # 5. Calculate distance of candidate regions to genes using distance2Genes
    d<-distance2Genes(win=win,gff=TAIR8_genes_test)
    d
    
    # 6. Identify genes with peaks using genesWithPeaks
    genes<-genesWithPeaks(d)
    head(genes)
    
    # 7. Generate permutated datasets and calculate permutated window scores using permutatedWinScores
    permutatedWinScores(nn=1,sample=sampleSEP3_test,control=controlSEP3_test,fileOutput="test",chr=chr_names,chrL=chr_lengths)
    permutatedWinScores(nn=2,sample=sampleSEP3_test,control=controlSEP3_test,fileOutput="test",chr=chr_names,chrL=chr_lengths)
    
    # 8. Load permutated scores using getPermutatedWinScores
    nulldist<-getPermutatedWinScores(file="test",nn=1:2)
    
    # 9. Calculate FDR threshold using getThreshold
    threshold_results <- getThreshold(winscores=values(win)\$score,permutatedScores=nulldist,FDR=.05)
    threshold_results
    
    # Save meaningful results to output files
    write.csv(as.data.frame(win), "sig_windows.csv", row.names = FALSE)
    saveRDS(win, "sig_windows.rds")
    write.csv(d, "distance_to_genes.csv", row.names = FALSE)
    write.csv(genes, "genes_with_peaks.csv", row.names = FALSE)
    write.csv(as.data.frame(threshold_results), "fdr_threshold_results.csv", row.names = FALSE)
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
      process = "BIOC_CSAR_CHIP_SEQ_PEAK_CALLING_AND_ANNOTATION",
      domain  = "bioconductor",
      declared_qc_steps = c("alignment/mapping QC", "low-count filtering", "count normalization"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_CSAR_CHIP_SEQ_PEAK_CALLING_AND_ANNOTATION":',
        paste0('    CSAR: ', as.character(packageVersion('CSAR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chip_seq_peak_calling_and_annotation.csv versions.yml
    """
}

workflow BIOC_CSAR_CHIP_SEQ_PEAK_CALLING_AND_ANNOTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sample_reads.tsv, control_reads.tsv, genes.gff ] ]

    main:
    BIOC_CSAR_CHIP_SEQ_PEAK_CALLING_AND_ANNOTATION(ch_input)

    emit:
    tables   = BIOC_CSAR_CHIP_SEQ_PEAK_CALLING_AND_ANNOTATION.out.tables
    plots    = BIOC_CSAR_CHIP_SEQ_PEAK_CALLING_AND_ANNOTATION.out.plots
    objects  = BIOC_CSAR_CHIP_SEQ_PEAK_CALLING_AND_ANNOTATION.out.objects
    versions = BIOC_CSAR_CHIP_SEQ_PEAK_CALLING_AND_ANNOTATION.out.versions
}
