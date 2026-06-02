#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ATACseqQC
// ATAC-seq, an assay for Transposase-Accessible Chromatin using sequencing, is a rapid and sensitive m
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ATACseqQC/inst/doc/ATACseqQC.R
// Upstream  : ChIPpeakAnno, GenomicAlignments, MotifDb, Rsamtools
// Downstream: none
//
// Install: BiocManager::install("ATACseqQC")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ATACSEQQC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-atacseqqc"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-atacseqqc:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-atacseqqc:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_atacseqqc_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_atacseqqc_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_atacseqqc_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ATACseqQC)
    library(BamFile)
    library(NFRscore)
    library(PTscore)
    library(Position)
    library(ScanBamParam)
    library(TSSEscore)
    library(jsonlite)

    # --- Alignment Shifting and Filtering [] ---
    # Key functions: readBamFile, shiftGAlignmentsList
    txdb <- TxDb.Hsapiens.UCSC.hg19.knownGene::TxDb.Hsapiens.UCSC.hg19.knownGene
    seqlev <- "chr1"
    seqinformation <- GenomeInfoDb::seqinfo(txdb)
    which_gr <- as(seqinformation[seqlev], "GRanges")
    gal <- readBamFile(bamfile, which=which_gr, asMates=TRUE, bigFile=TRUE)
    shifted_bam <- tempfile(fileext = ".bam")
    gal_shifted <- shiftGAlignmentsList(gal, outbam=shifted_bam)


    # --- Transcription Start Site and Nucleosome Scoring [] ---
    # Key functions: PTscore, NFRscore, TSSEscore
    txdb <- TxDb.Hsapiens.UCSC.hg19.knownGene::TxDb.Hsapiens.UCSC.hg19.knownGene
    txs <- GenomicFeatures::transcripts(txdb)
    pt <- PTscore(gal_shifted, txs)
    nfr <- NFRscore(gal_shifted, txs)
    tsse <- TSSEscore(gal_shifted, txs)
    plot(pt$log2meanCoverage, pt$PT_score,
         xlab="log2 mean coverage", ylab="PT score")
    plot(nfr$log2meanCoverage, nfr$NFR_score,
         xlab="log2 mean coverage", ylab="NFR score")


    # --- Nucleosome Fraction Splitting [] ---
    # Key functions: splitGAlignmentsByCut
    txdb <- TxDb.Hsapiens.UCSC.hg19.knownGene::TxDb.Hsapiens.UCSC.hg19.knownGene
    txs <- GenomicFeatures::transcripts(txdb)
    txs_chr1 <- txs[GenomeInfoDb::seqnames(txs) %in% "chr1"]
    genome <- BSgenome.Hsapiens.UCSC.hg19::Hsapiens
    conservation <- phastCons100way.UCSC.hg19::phastCons100way.UCSC.hg19
    out_path <- tempdir()
    objs <- splitGAlignmentsByCut(gal_shifted, txs=txs_chr1, genome=genome,
                                  outPath=out_path, conservation=conservation)


    # --- Signal Enrichment and Heatmap Visualization [] ---
    # Key functions: estLibSize, enrichedFragments, featureAlignedHeatmap
    bamfiles <- file.path(out_path,
                          c("NucleosomeFree.bam", "mononucleosome.bam"))
    lib_size <- estLibSize(bamfiles)
    txdb <- TxDb.Hsapiens.UCSC.hg19.knownGene::TxDb.Hsapiens.UCSC.hg19.knownGene
    txs <- GenomicFeatures::transcripts(txdb)
    tss <- GenomicRanges::promoters(txs, upstream=0, downstream=1)
    tss <- unique(tss)
    sigs <- enrichedFragments(gal=objs[c("NucleosomeFree", "mononucleosome")],
                              TSS=tss, librarySize=lib_size, seqlev="chr1",
                              TSS.filter=0.5, n.tile=101, upstream=1010,
                              downstream=1010)
    sigs_log2 <- lapply(sigs, function(x) log2(x + 1))
    ChIPpeakAnno::featureAlignedHeatmap(sigs_log2,
                                        ChIPpeakAnno::reCenterPeaks(tss, width=2020),
                                        zeroAt=0.5, n.tile=101)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_atacseqqc_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_atacseqqc_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_atacseqqc_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ATACSEQQC:", paste0("    atacseqqc: ", packageVersion("ATACseqQC"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_atacseqqc_results.csv
    touch ${prefix}_atacseqqc_output.rds
    echo "BIOC_ATACSEQQC:" > versions.yml
    echo "    atacseqqc: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ATACSEQQC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ATACSEQQC(ch_input)

    emit:
    results  = BIOC_ATACSEQQC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ATACSEQQC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ATACSEQQC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ATACSEQQC.out.versions  // channel: path(versions.yml)
}
