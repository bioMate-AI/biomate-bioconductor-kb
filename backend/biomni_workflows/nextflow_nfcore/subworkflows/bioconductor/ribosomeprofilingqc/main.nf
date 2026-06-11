#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ribosomeprofilingqc — qc_and_psite_estimation
// Perform quality control on Ribo-Seq BAM files, estimate the P-site offset, and check reading frame alignment.
// Input: bamfile, txdb, genome
// Container: quay.io/biocontainers/bioconductor-ribosomeprofilingqc:1.22.0--r45hdfd78af_0
// R packages: Biostrings, Rsamtools, AnnotationDbi, AnnotationHub, biocmanager, ChIPpeakAnno, GenomicFeatures, ribosomeProfilingQC
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RIBOSOMEPROFILINGQC_QC_AND_PSITE_ESTIMATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-ribosomeprofilingqc:1.22.0--r45hdfd78af_0"

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
    .bm_deps <- c("Biostrings", "Rsamtools", "AnnotationDbi", "AnnotationHub", "biocmanager", "ChIPpeakAnno", "GenomicFeatures", "ribosomeProfilingQC")
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
    library(ribosomeProfilingQC)
    library(Rsamtools)
    library(AnnotationDbi)
    library(Biostrings)
    
    message("Starting ribosomeProfilingQC pipeline...")
    
    # ==========================================
    # 1. RESOLVE USER INPUTS FROM WORKING DIR
    # ==========================================
    
    # Locate BAM file
    bamfilename <- "bamfile"
    if (!file.exists(bamfilename)) {
      if (file.exists("bamfile.bam")) {
        bamfilename <- "bamfile.bam"
      } else {
        bam_files <- list.files(pattern = "\\\\.bam\$")
        if (length(bam_files) > 0) {
          bamfilename <- bam_files[1]
        } else {
          stop("Error: BAM file ('bamfile' or '*.bam') not found in the working directory.")
        }
      }
    }
    message("Using BAM file: ", bamfilename)
    
    # Ensure BAM index exists
    if (!file.exists(paste0(bamfilename, ".bai")) && !file.exists(sub("\\\\.bam\$", ".bai", bamfilename))) {
      message("BAM index not found. Creating index...")
      Rsamtools::indexBam(bamfilename)
    }
    bamfile <- Rsamtools::BamFile(bamfilename, yieldSize = 10000000)
    
    # Locate TxDb
    txdb <- NULL
    if (file.exists("txdb")) {
      txdb <- tryCatch(readRDS("txdb"), error = function(e) NULL)
      if (is.null(txdb)) {
        txdb <- tryCatch(AnnotationDbi::loadDb("txdb"), error = function(e) NULL)
      }
    }
    if (is.null(txdb) && file.exists("txdb.rds")) {
      txdb <- readRDS("txdb.rds")
    }
    if (is.null(txdb) && file.exists("txdb.sqlite")) {
      txdb <- AnnotationDbi::loadDb("txdb.sqlite")
    }
    if (is.null(txdb)) {
      db_files <- list.files(pattern = "\\\\.(sqlite|sqlite3|db|rds)\$")
      for (f in db_files) {
        obj <- tryCatch(if (grepl("\\\\.rds\$", f)) readRDS(f) else AnnotationDbi::loadDb(f), error = function(e) NULL)
        if (!is.null(obj) && (inherits(obj, "TxDb") || inherits(obj, "GenomicFeatures"))) {
          txdb <- obj
          break
        }
      }
    }
    if (is.null(txdb)) {
      stop("Error: TxDb object ('txdb', 'txdb.rds', or 'txdb.sqlite') not found or could not be loaded.")
    }
    message("Loaded TxDb annotation successfully.")
    
    # Locate Genome
    genome <- NULL
    if (file.exists("genome")) {
      genome <- tryCatch(readRDS("genome"), error = function(e) NULL)
      if (is.null(genome)) {
        genome <- tryCatch(Biostrings::readDNAStringSet("genome"), error = function(e) NULL)
      }
    }
    if (is.null(genome) && file.exists("genome.rds")) {
      genome <- readRDS("genome.rds")
    }
    if (is.null(genome)) {
      fa_files <- list.files(pattern = "\\\\.(fa|fasta|fna)\$")
      if (length(fa_files) > 0) {
        genome <- Biostrings::readDNAStringSet(fa_files[1])
      }
    }
    if (is.null(genome)) {
      rds_files <- list.files(pattern = "\\\\.rds\$")
      for (f in rds_files) {
        obj <- tryCatch(readRDS(f), error = function(e) NULL)
        if (!is.null(obj) && (inherits(obj, "BSgenome") || inherits(obj, "DNAStringSet"))) {
          genome <- obj
          break
        }
      }
    }
    if (is.null(genome)) {
      stop("Error: Genome object ('genome', 'genome.rds', or FASTA file) not found or could not be loaded.")
    }
    message("Loaded Genome successfully.")
    
    
    # ==========================================
    # 2. RUN WORKFLOW: qc_and_psite_estimation
    # ==========================================
    
    # Stage 1: Prepare CDS annotation
    message("Stage 1: Preparing CDS annotation...")
    CDS <- prepareCDS(txdb)
    
    # Stage 2: Estimate P-site offset
    message("Stage 2: Estimating P-site offset...")
    p5 <- estimatePsite(bamfile, CDS, genome)
    p3 <- estimatePsite(bamfile, CDS, genome, anchor = "3end")
    writeLines(c(
      paste("Estimated P-site (5' end anchor):", p5),
      paste("Estimated P-site (3' end anchor):", p3)
    ), "psite_estimation_results.txt")
    
    # Stage 3: Plot start/stop windows
    message("Stage 3: Plotting start/stop windows...")
    pdf("reads_end_plots.pdf", width = 8, height = 6)
    re <- readsEndPlot(bamfile, CDS, toStartCodon=TRUE)
    readsEndPlot(re\$reads, CDS, toStartCodon=TRUE, fiveEnd=FALSE)
    dev.off()
    
    # Stage 4: Get P-site coordinates
    message("Stage 4: Getting P-site coordinates...")
    pc <- getPsiteCoordinates(bamfile, bestpsite = 13)
    
    # Stage 5: Summarize fragment length
    message("Stage 5: Summarizing fragment length...")
    readsLen <- summaryReadsLength(pc)
    write.csv(as.data.frame(readsLen), "summary_reads_length.csv", row.names = TRUE)
    
    # Filter reads by fragment size (28-29 nt)
    pc.sub <- pc[pc\$qwidth %in% c(28, 29)]
    
    # Stage 6: Plot strand specificity
    message("Stage 6: Plotting strand specificity...")
    pdf("strand_plot.pdf", width = 6, height = 6)
    strandPlot(pc.sub, CDS)
    dev.off()
    
    # Stage 7: Check genomic element distribution
    message("Stage 7: Checking genomic element distribution...")
    pdf("reads_distribution_plot.pdf", width = 8, height = 6)
    pc.sub <- readsDistribution(pc.sub, txdb, las=2)
    dev.off()
    saveRDS(pc.sub, "pc_sub_distribution.rds")
    
    # Stage 8: Plot metagene coverage
    message("Stage 8: Calculating coverage depth and plotting metagene coverage...")
    cvgs.utr5 <- coverageDepth(RPFs = bamfilename, gtf = txdb, region="utr5")
    cvgs.CDS <- coverageDepth(RPFs = bamfilename, gtf = txdb, region="cds")
    cvgs.utr3 <- coverageDepth(RPFs = bamfilename, gtf = txdb, region="utr3")
    
    pdf("metagene_plot.pdf", width = 8, height = 6)
    metaPlot(cvgs.utr5, cvgs.CDS, cvgs.utr3, sample=1)
    dev.off()
    
    # Stage 9: Assign reading frames and plot frame density
    message("Stage 9: Assigning reading frames and plotting frame density...")
    pc.sub <- assignReadingFrame(pc.sub, CDS)
    
    pdf("distance_to_codon_plot.pdf", width = 8, height = 6)
    plotDistance2Codon(pc.sub)
    dev.off()
    
    pdf("frame_density_plot.pdf", width = 6, height = 6)
    plotFrameDensity(pc.sub)
    dev.off()
    
    # Stage 10: Calculate ORFscore and coverage rate
    message("Stage 10: Calculating ORFscore and coverage rate...")
    cvg <- frameCounts(pc.sub, coverageRate=TRUE)
    saveRDS(cvg, "frame_counts_coverage.rds")
    
    ORFscore <- getORFscore(pc.sub)
    write.csv(as.data.frame(ORFscore), "orf_scores.csv", row.names = TRUE)
    
    message("Pipeline completed successfully! All outputs saved to the working directory.")

    writeLines(c(
        '"BIOC_RIBOSOMEPROFILINGQC_QC_AND_PSITE_ESTIMATION":',
        paste0('        ribosomeprofilingqc: ', as.character(packageVersion("ribosomeprofilingqc")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_qc_and_psite_estimation.csv versions.yml
    """
}

workflow BIOC_RIBOSOMEPROFILINGQC_QC_AND_PSITE_ESTIMATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bamfile, txdb, genome ] ]

    main:
    BIOC_RIBOSOMEPROFILINGQC_QC_AND_PSITE_ESTIMATION(ch_input)

    emit:
    tables   = BIOC_RIBOSOMEPROFILINGQC_QC_AND_PSITE_ESTIMATION.out.tables
    plots    = BIOC_RIBOSOMEPROFILINGQC_QC_AND_PSITE_ESTIMATION.out.plots
    objects  = BIOC_RIBOSOMEPROFILINGQC_QC_AND_PSITE_ESTIMATION.out.objects
    versions = BIOC_RIBOSOMEPROFILINGQC_QC_AND_PSITE_ESTIMATION.out.versions
}
