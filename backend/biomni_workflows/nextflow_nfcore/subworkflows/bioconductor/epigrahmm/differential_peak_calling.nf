#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: epigraHMM — differential_peak_calling
// Detect differential enrichment regions (peaks) across multiple experimental conditions and classify peaks into combinatorial patterns of enrichment.
// Input: bamFiles, colData
// Container: quay.io/biocontainers/bioconductor-epigrahmm:1.18.0--r45ha27e39d_2
// R packages: GenomicRanges, Seqinfo, SummarizedExperiment, epigraHMM, rtracklayer
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, Seqinfo, SummarizedExperiment, epigraHMM, rtracklayer
// Visualizations: gene count plot
// QC: count normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load BAM files for multiple conditions and create an epigraHMMDataSet using epigraHMMDataSetFromBam
//  * 2. [Input & Preparation] Create an EM control object using controlEM
//  * 3. [Core Analysis] Normalize counts using normalizeCounts
//  * 4. [Core Analysis] Initialize the model parameters using initializer
//  * 5. [Core Analysis] Run the HMM model for differential peak detection using epigraHMM with type = 'differential'
//  * 6. [Core Analysis] Call peaks using callPeaks
//  * 7. [Core Analysis] Extract and classify differential combinatorial patterns using callPatterns and info
//  * 8. [Visualization & Output] Visualize differential peaks and patterns using plotCounts and plotPatterns

nextflow.enable.dsl = 2

process BIOC_EPIGRAHMM_DIFFERENTIAL_PEAK_CALLING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("GenomicRanges", "Seqinfo", "SummarizedExperiment", "epigraHMM", "rtracklayer")
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
    
    # ==========================================
    # 1. Load User Input Files
    # ==========================================
    
    # Read colData from the working directory
    if (file.exists("colData.csv")) {
      colData <- read.csv("colData.csv", stringsAsFactors = FALSE)
    } else if (file.exists("colData.rds")) {
      colData <- readRDS("colData.rds")
    } else {
      stop("Error: colData file (colData.csv or colData.rds) not found in the working directory.")
    }
    
    # Extract bamFiles from colData or look for them
    if ("bamFiles" %in% colnames(colData)) {
      bamFiles <- colData\$bamFiles
    } else if ("bam" %in% colnames(colData)) {
      bamFiles <- colData\$bam
    } else {
      stop("Error: BAM file paths not found in colData. Please provide a 'bamFiles' or 'bam' column.")
    }
    
    # Extract genome from colData to avoid hardcoding
    if ("genome" %in% colnames(colData) && !is.na(colData\$genome[1]) && colData\$genome[1] != "") {
      genome_name <- colData\$genome[1]
    } else {
      genome_name <- 'hg19'
      message("Warning: Valid 'genome' column not found in colData. Defaulting to 'hg19'.")
    }
    
    # Ensure BAM files exist
    for (bam in bamFiles) {
      if (!file.exists(bam)) {
        stop(paste("Error: BAM file not found:", bam))
      }
    }
    
    # ==========================================
    # 2. Create epigraHMMDataSet
    # ==========================================
    
    object_differential <- epigraHMMDataSetFromBam(bamFiles = bamFiles,
                                                   colData = colData,
                                                   genome = genome_name,
                                                   windowSize = 500,
                                                   gapTrack = TRUE,
                                                   blackList = TRUE)
    
    # ==========================================
    # 3. Create EM Control Object
    # ==========================================
    
    control <- controlEM(fileName = 'control-differential', criterion = 'MACPE')
    
    # ==========================================
    # 4. Normalize Counts
    # ==========================================
    
    object_differential <- normalizeCounts(object_differential, control)
    
    # ==========================================
    # 5. Initialize Model Parameters
    # ==========================================
    
    object_differential <- initializer(object_differential, control)
    
    # ==========================================
    # 6. Run HMM Model for Differential Peak Detection
    # ==========================================
    
    object_differential <- epigraHMM(object = object_differential,
                                     control = control,
                                     type = 'differential')
    
    # Save the final fitted object
    saveRDS(object_differential, "object_differential.rds")
    
    # ==========================================
    # 7. Call Peaks
    # ==========================================
    
    peaks_differential <- callPeaks(object = object_differential)
    
    # Save called peaks
    saveRDS(peaks_differential, "peaks_differential.rds")
    write.csv(as.data.frame(peaks_differential), "peaks_differential.csv", row.names = FALSE)
    
    # ==========================================
    # 8. Fetch Annotation and Visualize
    # ==========================================
    
    annotation <- NULL
    tryCatch({
      session <- browserSession()
      genome(session) <- genome_name
      refSeq <- getTable(ucscTableQuery(session, table = "refGene"))
    
      annotation <- makeGRangesFromDataFrame(refSeq,
                                             starts.in.df.are.0based = TRUE,
                                             seqnames.field = 'chrom',
                                             start.field = 'txStart',
                                             end.field = 'txEnd',
                                             strand.field = 'strand',
                                             keep.extra.columns = TRUE)
    }, error = function(e) {
      message("Warning: Failed to fetch annotation from UCSC. Plotting will proceed without annotation.")
    })
    
    # Dynamically select a genomic range for visualization based on called peaks or available data
    if (length(peaks_differential) > 0) {
      gr_differential <- peaks_differential[1]
    } else if (length(rowRanges(object_differential)) > 0) {
      gr_differential <- rowRanges(object_differential)[1]
    } else {
      gr_differential <- GRanges('chr21', IRanges(41198328, 41352762))
    }
    
    # Expand the range by 10kb for better visualization context
    seq_name <- as.character(seqnames(gr_differential))[1]
    seq_lens <- seqlengths(object_differential)
    
    new_start <- max(1, start(gr_differential) - 10000)
    new_end <- end(gr_differential) + 10000
    
    if (!is.null(seq_lens) && seq_name %in% names(seq_lens) && !is.na(seq_lens[seq_name])) {
      new_end <- min(seq_lens[seq_name], new_end)
    }
    
    start(gr_differential) <- new_start
    end(gr_differential) <- new_end
    
    # Plot counts and save to PDF
    pdf("plot_counts_differential.pdf", width = 10, height = 8)
    tryCatch({
      plotCounts(object = object_differential,
                 ranges = gr_differential,
                 peaks = peaks_differential,
                 annotation = annotation)
    }, error = function(e) {
      message("Error plotting counts: ", e\$message)
    })
    dev.off()
    
    # Plot patterns and save to PDF
    pattern_peak <- peaks_differential[overlapsAny(peaks_differential, gr_differential)]
    
    if (length(pattern_peak) > 0) {
      # Use the 4th peak if available, otherwise fallback to the first available peak
      target_idx <- if (length(pattern_peak) >= 4) 4 else 1
      
      pdf("plot_patterns_differential.pdf", width = 8, height = 6)
      tryCatch({
        plotPatterns(object = object_differential,
                     ranges = pattern_peak[target_idx],
                     peaks = peaks_differential)
      }, error = function(e) {
        message("Error plotting patterns: ", e\$message)
      })
      dev.off()
    } else {
      message("No overlapping peaks found in the specified genomic range. Skipping pattern plot.")
    }
    
    # ==========================================
    # 9. Extract and Classify Combinatorial Patterns
    # ==========================================
    
    # Get object information and save to text file
    info_list <- info(object_differential)
    sink("model_info.txt")
    print(info_list)
    sink()
    
    # Get all posterior probabilities and save to CSV
    patterns_all <- callPatterns(object = object_differential, peaks = peaks_differential, type = 'all')
    write.csv(as.data.frame(patterns_all), "patterns_all.csv", row.names = FALSE)
    
    # Get most likely differential enrichment and save to CSV
    patterns_max <- callPatterns(object = object_differential, peaks = peaks_differential, type = 'max')
    write.csv(as.data.frame(patterns_max), "patterns_max.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_EPIGRAHMM_DIFFERENTIAL_PEAK_CALLING":',
        paste0('    epigraHMM: ', as.character(packageVersion('epigraHMM')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_peak_calling.csv versions.yml
    """
}

workflow BIOC_EPIGRAHMM_DIFFERENTIAL_PEAK_CALLING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bamFiles, colData ] ]

    main:
    BIOC_EPIGRAHMM_DIFFERENTIAL_PEAK_CALLING(ch_input)

    emit:
    tables   = BIOC_EPIGRAHMM_DIFFERENTIAL_PEAK_CALLING.out.tables
    plots    = BIOC_EPIGRAHMM_DIFFERENTIAL_PEAK_CALLING.out.plots
    objects  = BIOC_EPIGRAHMM_DIFFERENTIAL_PEAK_CALLING.out.objects
    versions = BIOC_EPIGRAHMM_DIFFERENTIAL_PEAK_CALLING.out.versions
}
