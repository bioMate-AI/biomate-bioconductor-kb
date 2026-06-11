#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ATACseqQC — atacseq_downstream_analysis
// Visualize nucleosome positions, generate transcription factor footprints, and create V-plots for fragment midpoint vs length.
// Input: shifted.bam, NucleosomeFree.bam, mononucleosome.bam, dinucleosome.bam, trinucleosome.bam
// Container: quay.io/biocontainers/bioconductor-atacseqqc:1.34.0--r45hdfd78af_0
// R packages: ATACseqQC, BSgenome.Hsapiens.UCSC.hg19, ChIPpeakAnno, GenomicAlignments, MotifDb, TxDb.Hsapiens.UCSC.hg19.knownGene
// Bioconductor: 3.20 | R: 4.4
// Requires: ATACseqQC, BSgenome.Hsapiens.UCSC.hg19, ChIPpeakAnno, GenomicAlignments, MotifDb, TxDb.Hsapiens.UCSC.hg19.knownGene
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Plot cumulative percentage of tag allocation using cumulativePercentage. 2. Estimate library size using estLibSize. 3. Calculate s

nextflow.enable.dsl = 2

process BIOC_ATACSEQQC_ATACSEQ_DOWNSTREAM_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("ATACseqQC", "BSgenome.Hsapiens.UCSC.hg19", "ChIPpeakAnno", "GenomicAlignments", "MotifDb", "TxDb.Hsapiens.UCSC.hg19.knownGene")
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
    library(ATACseqQC)
    library(ChIPpeakAnno)
    library(MotifDb)
    library(GenomicAlignments)
    library(BSgenome.Hsapiens.UCSC.hg19)
    library(TxDb.Hsapiens.UCSC.hg19.knownGene)
    
    # Define expected input files in the working directory
    shiftedBamfile <- "shifted.bam"
    bamfiles <- c(
      "NucleosomeFree.bam",
      "mononucleosome.bam",
      "dinucleosome.bam",
      "trinucleosome.bam"
    )
    
    # Verify input files exist
    all_files <- c(shiftedBamfile, bamfiles)
    missing_files <- all_files[!file.exists(all_files)]
    if (length(missing_files) > 0) {
      stop(paste("Missing required input files in the working directory:", 
                 paste(missing_files, collapse = ", ")))
    }
    
    message("All input files found. Starting downstream analysis...")
    
    # Set up genome, transcripts, and chromosome of interest
    seqlev <- "chr1"
    genome <- Hsapiens
    txs <- transcripts(TxDb.Hsapiens.UCSC.hg19.knownGene)
    txs <- txs[seqnames(txs) %in% seqlev]
    seqinformation <- seqinfo(TxDb.Hsapiens.UCSC.hg19.knownGene)
    which_gr <- as(seqinformation[seqlev], "GRanges")
    
    # Read BAM files into a named list of GAlignments (objs) for enrichedFragments
    message("Reading BAM files into memory...")
    objs <- list(
      NucleosomeFree = readBamFile("NucleosomeFree.bam", tag=character(0), which=which_gr, asMates=TRUE),
      mononucleosome = readBamFile("mononucleosome.bam", tag=character(0), which=which_gr, asMates=TRUE),
      dinucleosome = readBamFile("dinucleosome.bam", tag=character(0), which=which_gr, asMates=TRUE),
      trinucleosome = readBamFile("trinucleosome.bam", tag=character(0), which=which_gr, asMates=TRUE)
    )
    
    # 1. Plot cumulative percentage of tag allocation
    message("Plotting cumulative percentage...")
    pdf("cumulative_percentage.pdf")
    cumulativePercentage(bamfiles[1:2], as(seqinformation["chr1"], "GRanges"))
    dev.off()
    
    # 2. Estimate library size
    message("Estimating library size...")
    librarySize <- estLibSize(bamfiles)
    write.csv(as.data.frame(as.list(librarySize)), "library_size.csv", row.names=FALSE)
    
    # 3. Calculate signals around TSSs
    message("Calculating enriched fragments around TSSs...")
    TSS <- promoters(txs, upstream=0, downstream=1)
    TSS <- unique(TSS)
    NTILE <- 101
    dws <- ups <- 1010
    
    sigs <- enrichedFragments(gal=objs[c("NucleosomeFree", 
                                         "mononucleosome",
                                         "dinucleosome",
                                         "trinucleosome")], 
                              TSS=TSS,
                              librarySize=librarySize,
                              seqlev=seqlev,
                              TSS.filter=0.5,
                              n.tile = NTILE,
                              upstream = ups,
                              downstream = dws)
    saveRDS(sigs, "enriched_fragments_sigs.rds")
    
    # 4. Plot heatmap of signals
    message("Generating feature aligned heatmap...")
    sigs.log2 <- lapply(sigs, function(.ele) log2(.ele+1))
    pdf("feature_aligned_heatmap.pdf")
    featureAlignedHeatmap(sigs.log2, reCenterPeaks(TSS, width=ups+dws),
                          zeroAt=.5, n.tile=NTILE)
    dev.off()
    
    # 5. Plot averaged coverage
    message("Generating feature aligned distribution plot...")
    pdf("averaged_coverage.pdf")
    out <- featureAlignedDistribution(sigs, 
                                      reCenterPeaks(TSS, width=ups+dws),
                                      zeroAt=.5, n.tile=NTILE, type="l", 
                                      ylab="Averaged coverage")
    range01 <- function(x){(x-min(x))/(max(x)-min(x))}
    out_scaled <- apply(out, 2, range01)
    matplot(out_scaled, type="l", xaxt="n", 
            xlab="Position (bp)", 
            ylab="Fraction of signal")
    axis(1, at=seq(0, 100, by=10)+1, 
         labels=c("-1K", seq(-800, 800, by=200), "1K"), las=2)
    abline(v=seq(0, 100, by=10)+1, lty=2, col="gray")
    dev.off()
    write.csv(out, "feature_aligned_distribution.csv")
    
    # 6. Calculate and plot transcription factor footprints
    message("Calculating CTCF footprints...")
    CTCF <- query(MotifDb, c("CTCF"))
    CTCF <- as.list(CTCF)
    
    sigs_fp <- factorFootprints(shiftedBamfile, pfm=CTCF[[1]], 
                                genome=genome,
                                min.score="90%", seqlev=seqlev,
                                upstream=100, downstream=100)
    saveRDS(sigs_fp, "ctcf_footprints_sigs.rds")
    
    pdf("ctcf_footprints_heatmap.pdf")
    featureAlignedHeatmap(sigs_fp\$signal, 
                          feature.gr=reCenterPeaks(sigs_fp\$bindingSites,
                                                   width=200+width(sigs_fp\$bindingSites[1])), 
                          annoMcols="score",
                          sortBy="score",
                          n.tile=ncol(sigs_fp\$signal[[1]]))
    dev.off()
    
    # Save footprint statistics
    write.csv(as.data.frame(sigs_fp\$Profile.segmentation), "ctcf_profile_segmentation.csv", row.names=FALSE)
    saveRDS(sigs_fp\$spearman.correlation, "ctcf_spearman_correlation.rds")
    
    # 7. Generate V-plot and distance dyad
    message("Generating V-plot and distance dyad...")
    pdf("ctcf_vplot.pdf")
    vp <- vPlot(shiftedBamfile, pfm=CTCF[[1]], 
                genome=genome, min.score="90%", seqlev=seqlev,
                upstream=200, downstream=200, 
                ylim=c(30, 250), bandwidth=c(2, 1))
    distanceDyad(vp, pch=20, cex=.5)
    dev.off()
    saveRDS(vp, "ctcf_vplot_data.rds")
    
    # 8. Plot correlation for multiple samples
    message("Plotting correlation across all samples...")
    bamfiles_corr <- c("shifted.bam", "NucleosomeFree.bam", "mononucleosome.bam", "dinucleosome.bam", "trinucleosome.bam")
    gals <- lapply(bamfiles_corr, function(bamfile){
                   readBamFile(bamFile=bamfile, tag=character(0), 
                              which=GRanges("chr1", IRanges(1, 1e6)), 
                              asMates=FALSE)
             })
    
    pdf("samples_correlation.pdf")
    plotCorrelation(GAlignmentsList(gals), txs, seqlev="chr1")
    dev.off()
    
    message("Pipeline completed successfully. All outputs saved.")

    writeLines(c(
        '"BIOC_ATACSEQQC_ATACSEQ_DOWNSTREAM_ANALYSIS":',
        paste0('    ATACseqQC: ', as.character(packageVersion('ATACseqQC')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_atacseq_downstream_analysis.csv versions.yml
    """
}

workflow BIOC_ATACSEQQC_ATACSEQ_DOWNSTREAM_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ shifted.bam, NucleosomeFree.bam, mononucleosome.bam, dinucleosome.bam, trinucleosome.bam ] ]

    main:
    BIOC_ATACSEQQC_ATACSEQ_DOWNSTREAM_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_ATACSEQQC_ATACSEQ_DOWNSTREAM_ANALYSIS.out.tables
    plots    = BIOC_ATACSEQQC_ATACSEQ_DOWNSTREAM_ANALYSIS.out.plots
    objects  = BIOC_ATACSEQQC_ATACSEQ_DOWNSTREAM_ANALYSIS.out.objects
    versions = BIOC_ATACSEQQC_ATACSEQ_DOWNSTREAM_ANALYSIS.out.versions
}
