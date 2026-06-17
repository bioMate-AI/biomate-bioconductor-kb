#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: epigraHMM — consensus_peak_calling
// Detect consensus enrichment regions (peaks) across technical or biological replicates of a single experimental condition.
// Input: bamFiles, colData
// Container: quay.io/biocontainers/bioconductor-epigrahmm:1.18.0--r45ha27e39d_2
// R packages: Rsamtools, Seqinfo, epigraHMM, gcapc, GenomeInfoDb, GenomicRanges, rtracklayer, SummarizedExperiment
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, Rsamtools, Seqinfo, SummarizedExperiment, epigraHMM, rtracklayer
// Visualizations: gene count plot
// QC: missing-value handling, count normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load BAM files and create an epigraHMMDataSet using epigraHMMDataSetFromBam
//  * 2. [Input & Preparation] Create an EM control object using controlEM
//  * 3. [Core Analysis] Normalize counts using normalizeCounts
//  * 4. [Core Analysis] Initialize the model parameters using initializer
//  * 5. [Core Analysis] Run the HMM model for consensus peak detection using epigraHMM with type = 'consensus'
//  * 6. [Core Analysis] Call peaks using callPeaks
//  * 7. [Visualization & Output] Visualize peaks and normalized counts using plotCounts

nextflow.enable.dsl = 2

process BIOC_EPIGRAHMM_CONSENSUS_PEAK_CALLING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

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
    .bm_deps <- c("Rsamtools", "Seqinfo", "epigraHMM", "gcapc", "GenomeInfoDb", "GenomicRanges", "rtracklayer", "SummarizedExperiment")
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
    library(GenomicRanges)
    library(SummarizedExperiment)
    library(epigraHMM)
    library(rtracklayer)
    library(Seqinfo)
    library(Rsamtools)
    
    # ==========================================
    # 1. Load BAM files and create epigraHMMDataSet
    # ==========================================
    
    # Read user input files from the working directory
    if (file.exists("colData.csv")) {
      colData <- read.csv("colData.csv", stringsAsFactors = FALSE)
    } else {
      stop("Required input file 'colData.csv' not found in the working directory.")
    }
    
    if (file.exists("bamFiles.txt")) {
      bamFiles <- readLines("bamFiles.txt")
    } else if ("bam_path" %in% colnames(colData)) {
      bamFiles <- colData\$bam_path
    } else {
      bamFiles <- list.files(pattern = "\\\\.bam\$", full.names = TRUE)
    }
    
    if (length(bamFiles) == 0) {
      stop("No BAM files found or specified.")
    }
    
    # Ensure colData contains the required columns
    if (!all(c("condition", "replicate") %in% colnames(colData))) {
      stop("colData must contain 'condition' and 'replicate' columns.")
    }
    
    # Determine genome from colData or BAM file header to avoid hardcoding 'hg19'
    bam_seqinfo <- seqinfo(BamFile(bamFiles[1]))
    genome_name <- unique(na.omit(genome(bam_seqinfo)))[1]
    
    if ("genome" %in% colnames(colData)) {
      genome_input <- colData\$genome[1]
      gap_input <- TRUE
      black_input <- TRUE
    } else if (!is.na(genome_name) && length(genome_name) > 0) {
      genome_input <- genome_name
      gap_input <- TRUE
      black_input <- TRUE
    } else {
      seq_len <- seqlengths(bam_seqinfo)
      seq_len[is.na(seq_len)] <- 1e8 # Fallback for missing lengths
      genome_input <- GRanges(seqnames(bam_seqinfo), IRanges(1, seq_len))
      gap_input <- FALSE
      black_input <- FALSE
    }
    
    # Create epigraHMM object
    object_consensus <- epigraHMMDataSetFromBam(bamFiles = bamFiles,
                                                colData = colData,
                                                genome = genome_input,
                                                windowSize = 500,
                                                gapTrack = gap_input,
                                                blackList = black_input)
    
    # ==========================================
    # 2. Create an EM control object
    # ==========================================
    control <- controlEM(fileName = 'control-consensus')
    
    # ==========================================
    # 3. Normalize counts
    # ==========================================
    object_consensus <- normalizeCounts(object_consensus,
                                        control = control)
    
    # ==========================================
    # 4. Initialize model parameters
    # ==========================================
    object_consensus <- initializer(object_consensus, control)
    
    # ==========================================
    # 5. Run HMM model for consensus peak detection
    # ==========================================
    object_consensus <- epigraHMM(object = object_consensus,
                                  control = control,
                                  type = 'consensus')
    
    # Save the fitted epigraHMM object
    saveRDS(object_consensus, file = "object_consensus.rds")
    
    # ==========================================
    # 6. Call peaks
    # ==========================================
    peaks_consensus <- callPeaks(object = object_consensus)
    
    # Save called peaks
    saveRDS(peaks_consensus, file = "peaks_consensus.rds")
    write.csv(as.data.frame(peaks_consensus), file = "peaks_consensus.csv", row.names = FALSE)
    
    # ==========================================
    # 7. Visualize peaks and normalized counts
    # ==========================================
    # Fetch annotation from UCSC (wrapped in tryCatch to handle network issues)
    annotation <- tryCatch({
      if (is.character(genome_input)) {
        session <- browserSession()
        genome(session) <- genome_input
        refSeq <- getTable(ucscTableQuery(session, table = "refGene"))
      
        makeGRangesFromDataFrame(refSeq,
                                 starts.in.df.are.0based = TRUE,
                                 seqnames.field = 'chrom',
                                 start.field = 'txStart',
                                 end.field = 'txEnd',
                                 strand.field = 'strand',
                                 keep.extra.columns = TRUE)
      } else {
        NULL
      }
    }, error = function(e) {
      message("Warning: Failed to fetch annotation from UCSC. Plotting without annotation track.")
      NULL
    })
    
    # Dynamically select a region to plot based on called peaks to avoid hardcoded coordinates
    if (length(peaks_consensus) > 0) {
      gr_consensus <- peaks_consensus[1]
      new_start <- max(1, start(gr_consensus) - 10000)
      new_end <- end(gr_consensus) + 10000
      ranges(gr_consensus) <- IRanges(new_start, new_end)
    } else {
      gr_consensus <- rowRanges(object_consensus)[1]
      new_start <- max(1, start(gr_consensus) - 10000)
      new_end <- end(gr_consensus) + 10000
      ranges(gr_consensus) <- IRanges(new_start, new_end)
    }
    
    # Save visualization plot to PDF
    pdf("consensus_peaks_plot.pdf", width = 10, height = 8)
    if (!is.null(annotation)) {
      plotCounts(object = object_consensus,
                 ranges = gr_consensus,
                 peaks = peaks_consensus,
                 annotation = annotation)
    } else {
      plotCounts(object = object_consensus,
                 ranges = gr_consensus,
                 peaks = peaks_consensus)
    }
    dev.off()
    
    message("Pipeline completed successfully.")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # missing-value handling — scan .rds matrix/data.frame artifacts for max NA fraction
    .mv_na_fracs <- numeric(0)
    .mv_scanned <- character(0)
    for (.mv_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .mv_obj <- tryCatch(readRDS(.mv_rds), error = function(e) NULL)
      .mv_mat <- if (is.matrix(.mv_obj) || is.data.frame(.mv_obj)) .mv_obj else NULL
      if (!is.null(.mv_mat)) {
        .mv_vals <- suppressWarnings(as.numeric(as.matrix(.mv_mat)))
        if (length(.mv_vals) > 0) {
          .mv_na_fracs <- c(.mv_na_fracs, mean(is.na(.mv_vals)))
          .mv_scanned <- c(.mv_scanned, .mv_rds)
        }
      }
    }
    .mv_max <- if (length(.mv_na_fracs) > 0) round(max(.mv_na_fracs), 4) else NA_real_
    .gates_by_label[["missing-value handling"]] <- list(
      gate_row = "bioc_missing_value_handling",
      metric_name = "na_fraction_remaining",
      metric_value = .mv_max,
      passes = isTRUE(is.finite(.mv_max) && .mv_max < 0.05),
      status = if (is.finite(.mv_max)) paste0("computed (scanned ", length(.mv_scanned), " rds files)")
               else "not_computed (no matrix/data.frame .rds artifact present)"
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
      process = "BIOC_EPIGRAHMM_CONSENSUS_PEAK_CALLING",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling", "count normalization"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_EPIGRAHMM_CONSENSUS_PEAK_CALLING":',
        paste0('    epigraHMM: ', as.character(packageVersion('epigraHMM')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_consensus_peak_calling.csv versions.yml
    """
}

workflow BIOC_EPIGRAHMM_CONSENSUS_PEAK_CALLING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bamFiles, colData ] ]

    main:
    BIOC_EPIGRAHMM_CONSENSUS_PEAK_CALLING(ch_input)

    emit:
    tables   = BIOC_EPIGRAHMM_CONSENSUS_PEAK_CALLING.out.tables
    plots    = BIOC_EPIGRAHMM_CONSENSUS_PEAK_CALLING.out.plots
    objects  = BIOC_EPIGRAHMM_CONSENSUS_PEAK_CALLING.out.objects
    versions = BIOC_EPIGRAHMM_CONSENSUS_PEAK_CALLING.out.versions
}
