#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: transcriptr — integrated_rna_and_chip_seq_demarcation
// Integrate RNA-seq and ChIP-seq data to classify active transcription start sites and demarcate individual transcript boundaries.
// Input: path.to.Bam, path.to.peaks, path.to.reads, knownGene
// Container: quay.io/biocontainers/bioconductor-transcriptr:1.38.3--r45hdfd78af_0
// R packages: GenomicFeatures, TxDb.Hsapiens.UCSC.hg19.knownGene, transcriptR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: ROC curve, enrichment plot, box plot

nextflow.enable.dsl = 2

process BIOC_TRANSCRIPTR_INTEGRATED_RNA_AND_CHIP_SEQ_DEMARCATION {
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
    .bm_deps <- c("GenomicFeatures", "TxDb.Hsapiens.UCSC.hg19.knownGene", "transcriptR")
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
    library(transcriptR)
    library(GenomicFeatures)
    
    # Define user input files from the working directory
    path.to.Bam   <- "path.to.Bam"   # strand-specific RNA-seq BAM file
    path.to.peaks <- "path.to.peaks" # ChIP-seq peak file (e.g., MACS2 output)
    path.to.reads <- "path.to.reads" # ChIP-seq alignment BAM file
    
    # Load TxDb reference annotation object
    if (file.exists("knownGene.rds")) {
      knownGene <- readRDS("knownGene.rds")
    } else {
      # Fallback to the standard hg19 TxDb if the RDS is not present in the working directory
      library(TxDb.Hsapiens.UCSC.hg19.knownGene)
      knownGene <- TxDb.Hsapiens.UCSC.hg19.knownGene
    }
    
    # Extract genes information
    knownGene.genes <- genes(knownGene)
    
    # Define region (set to NULL to process the entire genome/BAM, or specify a GRanges object)
    region <- NULL
    
    # =========================================================================
    # --- Initialize and run the RNA-seq transcript detection ---
    # =========================================================================
    message("[STAGE 1] Initializing RNA-seq transcript detection...")
    
    tds <- constructTDS(
      file = path.to.Bam,
      region = region,
      fragment.size = 250,
      unique = FALSE,
      paired.end = FALSE,
      swap.strand = TRUE
    )
    
    message("Estimating expression background...")
    estimateBackground(tds, fdr.cutoff = 0.01)
    
    message("Tuning gap distance parameters...")
    gd <- seq(from = 0, to = 10000, by = 100)
    estimateGapDistance(
      object = tds,
      annot = knownGene.genes,
      filter.annot = TRUE,
      fpkm.quantile = 0.25,
      gap.dist.range = gd
    )
    
    # Save gap distance error rate plot
    pdf("gap_distance_error_rate.pdf")
    plotErrorRate(tds, lwd = 2)
    dev.off()
    
    # Save intermediate gap distance calculations
    gdTest <- getTestedGapDistances(tds)
    write.csv(gdTest, "tested_gap_distances.csv", row.names = FALSE)
    
    message("Detecting transcripts...")
    detectTranscripts(tds, estimate.params = TRUE)
    
    message("Annotating detected transcripts...")
    annotateTranscripts(object = tds, annot = knownGene.genes, min.overlap = 0.5)
    
    # Retrieve and save intermediate transcripts
    trx <- getTranscripts(tds, min.length = 250, min.fpkm = 0.5)
    saveRDS(trx, "transcripts_intermediate.rds")
    transcriptsToBed(object = trx, file = "transcripts.bed", strand.color = c("blue", "red"))
    
    # =========================================================================
    # --- Construct the ChipDataSet object and evaluate peak ---
    # =========================================================================
    message("[STAGE 2] Constructing ChipDataSet and evaluating peak distribution...")
    
    cds <- constructCDS(
      peaks = path.to.peaks,
      reads = path.to.reads,
      region = region,
      TxDb = knownGene,
      tssOf = "transcript",
      tss.region = c(-2000, 2000),
      reduce.peaks = TRUE,
      gapwidth = 500,
      unique = TRUE,
      swap.strand = FALSE
    )
    
    # Save genomic annotations of peaks
    genomic_annot <- getGenomicAnnot(cds)
    write.csv(genomic_annot, "peaks_genomic_annotation.csv", row.names = FALSE)
    
    # Plot genomic distribution and enrichment
    pdf("peaks_genomic_distribution.pdf")
    plotGenomicAnnot(object = cds, plot.type = "distr")
    dev.off()
    
    pdf("peaks_genomic_enrichment.pdf")
    plotGenomicAnnot(object = cds, plot.type = "enrich")
    dev.off()
    
    # =========================================================================
    # --- Predict gene-associated ChIP-seq peaks using a logistic ---
    # =========================================================================
    message("[STAGE 3] Predicting gene-associated peaks...")
    
    # Plot features used in classification
    pdf("peaks_features_boxplot.pdf")
    plotFeatures(cds, plot.type = "box")
    dev.off()
    
    # Fit logistic regression model
    predictTssOverlap(object = cds, feature = "pileup", p = 0.75)
    
    # Save classification performance metrics
    sink("classification_performance.txt")
    cat("=== Confusion Matrix ===\n")
    print(getConfusionMatrix(cds))
    cat("\n=== Predictor Significance ===\n")
    print(getPredictorSignificance(cds))
    sink()
    
    # Plot ROC curve
    pdf("peaks_classification_roc.pdf")
    plotROC(object = cds, col = "red3", grid = TRUE, auc.polygon = TRUE)
    dev.off()
    
    # =========================================================================
    # --- Predict peak strandedness by analyzing ---
    # =========================================================================
    message("[STAGE 4] Predicting peak strandedness...")
    
    predictStrand(cdsObj = cds, tdsObj = tds, quant.cutoff = 0.1, win.size = 2000)
    
    # Save quad probabilities
    df_plus <- getQuadProb(cds, strand = "+")
    write.csv(df_plus, "quad_probabilities_plus.csv", row.names = FALSE)
    
    # Save predicted peaks
    peaks_predicted <- getPeaks(cds)
    saveRDS(peaks_predicted, "peaks_predicted.rds")
    peaksToBed(object = cds, file = "peaks.bed", gene.associated.peaks = TRUE)
    
    # =========================================================================
    # --- Demarcate transcript boundaries by breaking closely ---
    # =========================================================================
    message("[STAGE 5] Demarcating transcript boundaries...")
    
    breakTranscriptsByPeaks(tdsObj = tds, cdsObj = cds, estimate.params = TRUE)
    
    # =========================================================================
    # --- Re-annotate and retrieve the final set of resolved ---
    # =========================================================================
    message("[STAGE 6] Re-annotating and retrieving final transcripts...")
    
    annotateTranscripts(object = tds, annot = knownGene.genes, min.overlap = 0.5)
    
    # Retrieve final transcripts
    trx.final <- getTranscripts(tds)
    saveRDS(trx.final, "transcripts_final.rds")
    
    # Export final transcripts to BED
    transcriptsToBed(object = trx.final, file = "transcripts_final.bed")
    
    # Identify and save transcripts that were broken by peaks
    hits <- findOverlaps(query = trx, subject = trx.final)
    trx.broken <- trx[unique(queryHits(hits)[duplicated(queryHits(hits))])]
    saveRDS(trx.broken, "transcripts_broken_by_peaks.rds")
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_TRANSCRIPTR_INTEGRATED_RNA_AND_CHIP_SEQ_DEMARCATION":',
        paste0('        transcriptr: ', as.character(packageVersion("transcriptr")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_integrated_rna_and_chip_seq_demarcation.csv versions.yml
    """
}

workflow BIOC_TRANSCRIPTR_INTEGRATED_RNA_AND_CHIP_SEQ_DEMARCATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ path.to.Bam, path.to.peaks, path.to.reads, knownGene ] ]

    main:
    BIOC_TRANSCRIPTR_INTEGRATED_RNA_AND_CHIP_SEQ_DEMARCATION(ch_input)

    emit:
    tables   = BIOC_TRANSCRIPTR_INTEGRATED_RNA_AND_CHIP_SEQ_DEMARCATION.out.tables
    plots    = BIOC_TRANSCRIPTR_INTEGRATED_RNA_AND_CHIP_SEQ_DEMARCATION.out.plots
    objects  = BIOC_TRANSCRIPTR_INTEGRATED_RNA_AND_CHIP_SEQ_DEMARCATION.out.objects
    versions = BIOC_TRANSCRIPTR_INTEGRATED_RNA_AND_CHIP_SEQ_DEMARCATION.out.versions
}
