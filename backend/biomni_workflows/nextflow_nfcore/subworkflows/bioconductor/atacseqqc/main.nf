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
    library(BamFile)
    library(NFRscore)
    library(PTscore)
    library(Position)
    library(ScanBamParam)
    library(TSSEscore)
    library(jsonlite)

    # --- Bamqc [] ---
    # Key functions: bamQC, estimateLibComplexity, readsDupFreq
    ---------------------------------------------------------------------
    #bamQC(bamfile, outPath=NULL)
    estimateLibComplexity(readsDupFreq(bamfile))
    # --- Fragsizedist [] ---
    # Key functions: fragSizeDist
    ---------------------------------------------------------------------
    ## generate fragement size distribution
    fragSize <- fragSizeDist(bamfile, bamfile.labels)
    # --- List [] ---
    # Key functions: scanBam, BamFile, ScanBamParam, unlist
    ---------------------------------------------------------------------
    ## bamfile tags to be read in
    # --- Transcripts [] ---
    # Key functions: transcripts, PTscore
    ---------------------------------------------------------------------
    library(TxDb.Hsapiens.UCSC.hg19.knownGene)
    txs <- transcripts(TxDb.Hsapiens.UCSC.hg19.knownGene)
    pt <- PTscore(gal1, txs)
    # --- Nfrscore [] ---
    # Key functions: NFRscore
    ---------------------------------------------------------------------
    nfr <- NFRscore(gal1, txs)
    # --- Tssescore [] ---
    # Key functions: TSSEscore
    ---------------------------------------------------------------------
    tsse <- TSSEscore(gal1, txs)
    tsse$TSSEscore
    # --- Seqnames [] ---
    # Key functions: seqnames, splitGAlignmentsByCut
    ---------------------------------------------------------------------
    library(BSgenome.Hsapiens.UCSC.hg19)
    library(phastCons100way.UCSC.hg19)
    ## run program for chromosome 1 only
    txs <- txs[seqnames(txs) %in% "chr1"]
    # --- Function [] ---
    # Key functions: matplot, Position
    ---------------------------------------------------------------------
    ## rescale the nucleosome-free and nucleosome signals to 0~1
    range01 <- function(x){(x-min(x))/(max(x)-min(x))}
    out <- apply(out, 2, range01)
    # --- Query [] ---
    # Key functions: query, factorFootprints
    ---------------------------------------------------------------------
    ## foot prints
    library(MotifDb)
    CTCF <- query(MotifDb, c("CTCF"))
    CTCF <- as.list(CTCF)
    # --- Vplot [] ---
    # Key functions: vPlot, distanceDyad
    ---------------------------------------------------------------------
    vp <- vPlot(shiftedBamfile, pfm=CTCF[[1]],
                genome=genome, min.score="90%", seqlev=seqlev,
                upstream=200, downstream=200,
                ylim=c(30, 250), bandwidth=c(2, 1))

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
