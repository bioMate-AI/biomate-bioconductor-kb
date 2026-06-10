#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: atacseqqc — atac_seq_qc_and_preprocessing
// Perform quality control, Tn5 shift correction, nucleosome-fraction splitting, and downstream footprinting/V-plot analysis on ATAC-seq BAM files.
// Input: sample.bam, sample.bam.bai
// Container: quay.io/biocontainers/bioconductor-atacseqqc:1.34.0--r45hdfd78af_0
// R packages: BSgenome.Hsapiens.UCSC.hg19, TxDb.Hsapiens.UCSC.hg19.knownGene, ATACseqQC, ChIPpeakAnno, GenomicAlignments, MotifDb, phastCons100way.UCSC.hg19, Rsamtools
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ATACSEQQC_ATAC_SEQ_QC_AND_PREPROCESSING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-atacseqqc:1.34.0--r45hdfd78af_0"

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
    .bm_deps <- c("BSgenome.Hsapiens.UCSC.hg19", "TxDb.Hsapiens.UCSC.hg19.knownGene", "ATACseqQC", "ChIPpeakAnno", "GenomicAlignments", "MotifDb", "phastCons100way.UCSC.hg19", "Rsamtools")
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
    library(BSgenome.Hsapiens.UCSC.hg19)
    library(TxDb.Hsapiens.UCSC.hg19.knownGene)
    library(phastCons100way.UCSC.hg19)
    library(MotifDb)
    library(GenomicAlignments)
    library(Rsamtools)
    
    # Define input files from the working directory
    bamfile <- "sample.bam"
    bamfile.labels <- gsub(".bam", "", basename(bamfile))
    
    # Start PDF device to capture all diagnostic plots
    pdf("atacseq_qc_plots.pdf", width=10, height=8)
    
    # 1. Estimate library complexity
    lib_complexity <- estimateLibComplexity(readsDupFreq(bamfile))
    write.csv(as.data.frame(lib_complexity), "library_complexity.csv", row.names=FALSE)
    
    # 2. Generate fragment size distribution
    fragSize <- fragSizeDist(bamfile, bamfile.labels)
    saveRDS(fragSize, "fragment_size_distribution.rds")
    
    # 3. Read BAM file and shift coordinates to adjust for Tn5 transposase dimer insertion
    possibleTag <- list("integer"=c("AM", "AS", "CM", "CP", "FI", "H0", "H1", "H2", "HI", "IH", "MQ", "NH", "NM", "OP", "PQ", "SM", "TC", "UQ"), "character"=c("BC", "BQ", "BZ", "CB", "CC", "CO", "CQ", "CR", "CS", "CT", "CY", "E2", "FS", "LB", "MC", "MD", "MI", "OA", "OC", "OQ", "OX", "PG", "PT", "PU", "Q2", "QT", "QX", "R2", "RG", "RX", "SA", "TS", "U2"))
    bamTop100 <- scanBam(BamFile(bamfile, yieldSize = 100), param = ScanBamParam(tag=unlist(possibleTag)))[[1]]\$tag
    tags <- names(bamTop100)[lengths(bamTop100)>0]
    
    outPath <- "splited"
    if (!dir.exists(outPath)) {
      dir.create(outPath)
    }
    
    seqlev <- "chr1"
    seqinformation <- seqinfo(TxDb.Hsapiens.UCSC.hg19.knownGene)
    which <- as(seqinformation[seqlev], "GRanges")
    gal <- readBamFile(bamfile, tag=tags, which=which, asMates=TRUE, bigFile=TRUE)
    shiftedBamfile <- file.path(outPath, "shifted.bam")
    gal1 <- shiftGAlignmentsList(gal, outbam=shiftedBamfile)
    
    # 4. Calculate Promoter/Transcript body (PT) score
    txs <- transcripts(TxDb.Hsapiens.UCSC.hg19.knownGene)
    pt <- PTscore(gal1, txs)
    plot(pt\$log2meanCoverage, pt\$PT_score, xlab="log2 mean coverage", ylab="Promoter vs Transcript")
    write.csv(as.data.frame(pt), "pt_score.csv", row.names=FALSE)
    
    # 5. Calculate Nucleosome Free Regions (NFR) score
    nfr <- NFRscore(gal1, txs)
    plot(nfr\$log2meanCoverage, nfr\$NFR_score, xlab="log2 mean coverage", ylab="Nucleosome Free Regions score", main="NFRscore for 200bp flanking TSSs", xlim=c(-10, 0), ylim=c(-5, 5))
    write.csv(as.data.frame(nfr), "nfr_score.csv", row.names=FALSE)
    
    # 6. Calculate Transcription Start Site (TSS) Enrichment Score
    tsse <- TSSEscore(gal1, txs)
    plot(100*(-9:10-.5), tsse\$values, type="b", xlab="distance to TSS", ylab="aggregate TSS score")
    write.csv(as.data.frame(tsse\$values), "tsse_score_values.csv", row.names=FALSE)
    saveRDS(tsse, "tsse_score.rds")
    
    # 7. Split shifted reads into nucleosome-free and nucleosome-bound fractions
    txs <- txs[seqnames(txs) %in% "chr1"]
    genome <- Hsapiens
    objs <- splitGAlignmentsByCut(gal1, txs=txs, genome=genome, outPath = outPath, conservation=phastCons100way.UCSC.hg19)
    saveRDS(objs, "split_alignments.rds")
    
    # 8. Plot cumulative percentage and TSS enrichment of split fractions
    bamfiles <- file.path(outPath, c("NucleosomeFree.bam", "mononucleosome.bam", "dinucleosome.bam", "trinucleosome.bam"))
    cumulativePercentage(bamfiles[1:2], as(seqinformation["chr1"], "GRanges"))
    TSS <- promoters(txs, upstream=0, downstream=1)
    TSS <- unique(TSS)
    librarySize <- estLibSize(bamfiles)
    NTILE <- 101
    dws <- ups <- 1010
    sigs <- enrichedFragments(gal=objs[c("NucleosomeFree", "mononucleosome", "dinucleosome", "trinucleosome")], TSS=TSS, librarySize=librarySize, seqlev=seqlev, TSS.filter=0.5, n.tile = NTILE, upstream = ups, downstream = dws)
    sigs.log2 <- lapply(sigs, function(.ele) log2(.ele+1))
    featureAlignedHeatmap(sigs.log2, reCenterPeaks(TSS, width=ups+dws), zeroAt=.5, n.tile=NTILE)
    out <- featureAlignedDistribution(sigs, reCenterPeaks(TSS, width=ups+dws), zeroAt=.5, n.tile=NTILE, type="l", ylab="Averaged coverage")
    range01 <- function(x){(x-min(x))/(max(x)-min(x))}
    out <- apply(out, 2, range01)
    matplot(out, type="l", xaxt="n", xlab="Position (bp)", ylab="Fraction of signal")
    axis(1, at=seq(0, 100, by=10)+1, labels=c("-1K", seq(-800, 800, by=200), "1K"), las=2)
    abline(v=seq(0, 100, by=10)+1, lty=2, col="gray")
    write.csv(as.data.frame(out), "tss_enrichment_distribution.csv", row.names=FALSE)
    
    # 9. Generate transcription factor footprints
    CTCF <- query(MotifDb, c("CTCF"))
    CTCF <- as.list(CTCF)
    sigs <- factorFootprints(shiftedBamfile, pfm=CTCF[[1]], genome=genome, min.score="90%", seqlev=seqlev, upstream=100, downstream=100)
    featureAlignedHeatmap(sigs\$signal, feature.gr=reCenterPeaks(sigs\$bindingSites, width=200+width(sigs\$bindingSites[1])), annoMcols="score", sortBy="score", n.tile=ncol(sigs\$signal[[1]]))
    saveRDS(sigs, "ctcf_footprints.rds")
    
    # 10. Generate V-plots
    vp <- vPlot(shiftedBamfile, pfm=CTCF[[1]], genome=genome, min.score="90%", seqlev=seqlev, upstream=200, downstream=200, ylim=c(30, 250), bandwidth=c(2, 1))
    distanceDyad(vp, pch=20, cex=.5)
    saveRDS(vp, "ctcf_vplot.rds")
    
    # Close PDF device
    dev.off()

    cat <<-END_VERSIONS > versions.yml
    "BIOC_ATACSEQQC_ATAC_SEQ_QC_AND_PREPROCESSING":
        atacseqqc: \$(Rscript -e 'cat(as.character(packageVersion("atacseqqc")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_atac_seq_qc_and_preprocessing.csv versions.yml
    """
}

workflow BIOC_ATACSEQQC_ATAC_SEQ_QC_AND_PREPROCESSING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sample.bam, sample.bam.bai ] ]

    main:
    BIOC_ATACSEQQC_ATAC_SEQ_QC_AND_PREPROCESSING(ch_input)

    emit:
    tables   = BIOC_ATACSEQQC_ATAC_SEQ_QC_AND_PREPROCESSING.out.tables
    plots    = BIOC_ATACSEQQC_ATAC_SEQ_QC_AND_PREPROCESSING.out.plots
    objects  = BIOC_ATACSEQQC_ATAC_SEQ_QC_AND_PREPROCESSING.out.objects
    versions = BIOC_ATACSEQQC_ATAC_SEQ_QC_AND_PREPROCESSING.out.versions
}
