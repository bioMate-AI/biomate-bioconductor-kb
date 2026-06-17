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
