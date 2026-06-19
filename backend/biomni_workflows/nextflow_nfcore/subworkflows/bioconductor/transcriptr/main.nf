#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: transcriptr — rna_seq_only_transcript_detection
// Detect, annotate, and quantify de novo primary transcripts from strand-specific RNA-seq data alone.
// Input: path.to.Bam, knownGene
// Container: quay.io/biocontainers/bioconductor-transcriptr:1.38.3--r45hdfd78af_0
// R packages: GenomicRanges, Rsamtools, GenomicFeatures, transcriptR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_TRANSCRIPTR_RNA_SEQ_ONLY_TRANSCRIPT_DETECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-transcriptr:1.38.3--r45hdfd78af_0"

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
    .bm_deps <- c("GenomicRanges", "Rsamtools", "GenomicFeatures", "transcriptR")
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
    library(transcriptR)
    library(GenomicFeatures)
    library(GenomicRanges)
    library(Rsamtools)
    
    # ==========================================
    # --- INPUT LOADING & PREPARATION ---
    # ==========================================
    
    # Locate the strand-specific RNA-seq BAM file
    if (file.exists("path.to.Bam")) {
      path.to.Bam <- "path.to.Bam"
    } else if (file.exists("path.to.Bam.bam")) {
      path.to.Bam <- "path.to.Bam.bam"
    } else {
      # Fallback: search for any BAM file in the working directory
      bam_files <- list.files(pattern = "\\\\.bam\$")
      if (length(bam_files) > 0) {
        path.to.Bam <- bam_files[1]
        message("Using found BAM file: ", path.to.Bam)
      } else {
        stop("Required BAM file 'path.to.Bam' not found in the working directory.")
      }
    }
    
    # Load the TxDb reference annotation object
    if (file.exists("knownGene.rds")) {
      knownGene <- readRDS("knownGene.rds")
    } else if (file.exists("knownGene")) {
      knownGene <- readRDS("knownGene")
    } else {
      stop("Required TxDb object file ('knownGene.rds' or 'knownGene') not found in the working directory.")
    }
    
    # Extract genes information from the TxDb object
    knownGene.genes <- genes(knownGene)
    
    # Dynamically construct the region GRanges from the BAM header to cover the entire genome/chromosomes present
    bam_header <- Rsamtools::scanBamHeader(path.to.Bam)
    targets <- bam_header[[1]]\$targets
    if (length(targets) > 0) {
      region <- GenomicRanges::GRanges(seqnames = names(targets), ranges = IRanges::IRanges(start = 1, end = targets))
    } else {
      region <- NULL
    }
    
    # ==========================================
    # --- TRANSCRIPTION DATASET CONSTRUCTION ---
    # ==========================================
    
    # Initialize the TranscriptionDataSet object
    tds <- constructTDS(
      file = path.to.Bam, 
      region = region, 
      fragment.size = 250, 
      unique = FALSE, 
      paired.end = FALSE, 
      swap.strand = TRUE
    )
    
    # ==========================================
    # --- BACKGROUND NOISE ESTIMATION ---
    # ==========================================
    
    # Estimate expression background noise level
    estimateBackground(tds, fdr.cutoff = 0.01)
    
    # ==========================================
    # --- GAP DISTANCE TUNING ---
    # ==========================================
    
    # Define the range of gap distances to test
    gd <- seq(from = 0, to = 10000, by = 100)
    
    # Estimate the optimal gap distance for merging fragmented transcripts
    estimateGapDistance(
      object = tds, 
      annot = knownGene.genes, 
      filter.annot = TRUE, 
      fpkm.quantile = 0.25, 
      gap.dist.range = gd
    )
    
    # Export the gap distance error rate plot to a PDF
    tryCatch({
      pdf("gap_distance_error_rate.pdf", width = 7, height = 7)
      plotErrorRate(tds, lwd = 2)
      dev.off()
      message("Saved gap distance error rate plot to 'gap_distance_error_rate.pdf'")
    }, error = function(e) {
      warning("Could not generate the error rate plot: ", e\$message)
    })
    
    # Save intermediate gap distance calculations
    tryCatch({
      gdTest <- getTestedGapDistances(tds)
      write.csv(gdTest, "tested_gap_distances.csv", row.names = FALSE)
      message("Saved tested gap distances to 'tested_gap_distances.csv'")
    }, error = function(e) {
      warning("Could not retrieve tested gap distances: ", e\$message)
    })
    
    # ==========================================
    # --- TRANSCRIPT CALLING & ANNOTATION ---
    # ==========================================
    
    # Call transcripts using the estimated parameters
    detectTranscripts(tds, estimate.params = TRUE)
    
    # Annotate detected transcripts against reference genes
    annotateTranscripts(object = tds, annot = knownGene.genes, min.overlap = 0.5)
    
    # Retrieve the final set of transcripts
    trx <- getTranscripts(tds, min.length = 250, min.fpkm = 0.5)
    
    # ==========================================
    # --- EXPORT RESULTS ---
    # ==========================================
    
    # Export transcripts to BED format
    transcriptsToBed(object = trx, file = "transcripts.bed", strand.color = c("blue", "red"))
    message("Exported transcripts to 'transcripts.bed'")
    
    # Save transcripts as an RDS object
    saveRDS(trx, "detected_transcripts.rds")
    message("Saved transcripts object to 'detected_transcripts.rds'")
    
    # Save transcripts as a CSV table
    write.csv(as.data.frame(trx), "detected_transcripts.csv", row.names = FALSE)
    message("Saved transcripts table to 'detected_transcripts.csv'")
    
    # Save the final TranscriptionDataSet object
    saveRDS(tds, "tds_final.rds")
    message("Saved final TranscriptionDataSet object to 'tds_final.rds'")
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_TRANSCRIPTR_RNA_SEQ_ONLY_TRANSCRIPT_DETECTION":',
        paste0('        transcriptr: ', as.character(packageVersion("transcriptr")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rna_seq_only_transcript_detection.csv versions.yml
    """
}

workflow BIOC_TRANSCRIPTR_RNA_SEQ_ONLY_TRANSCRIPT_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ path.to.Bam, knownGene ] ]

    main:
    BIOC_TRANSCRIPTR_RNA_SEQ_ONLY_TRANSCRIPT_DETECTION(ch_input)

    emit:
    tables   = BIOC_TRANSCRIPTR_RNA_SEQ_ONLY_TRANSCRIPT_DETECTION.out.tables
    plots    = BIOC_TRANSCRIPTR_RNA_SEQ_ONLY_TRANSCRIPT_DETECTION.out.plots
    objects  = BIOC_TRANSCRIPTR_RNA_SEQ_ONLY_TRANSCRIPT_DETECTION.out.objects
    versions = BIOC_TRANSCRIPTR_RNA_SEQ_ONLY_TRANSCRIPT_DETECTION.out.versions
}
