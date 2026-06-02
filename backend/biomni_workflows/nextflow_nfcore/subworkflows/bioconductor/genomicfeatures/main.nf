#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GenomicFeatures
// Extract the genomic locations of genes, transcripts, exons, introns, and CDS, for the gene models st
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GenomicFeatures/inst/doc/GenomicFeatures.R
// Upstream  : none
// Downstream: Cogito, cpvSNP, ensembldb, GSReg, Guitar
//
// Install: BiocManager::install("GenomicFeatures")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENOMICFEATURES {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-genomicfeatures"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-genomicfeatures:1.58.0--r44_0' :
        'quay.io/biocontainers/bioconductor-genomicfeatures:1.58.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_genomicfeatures_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_genomicfeatures_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_genomicfeatures_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GenomicFeatures)
    library(jsonlite)


    # --- Loadgenomicfeatures [] ---
    # Key functions: suppressPackageStartupMessages, loadDb, extdata, hg19_knownGene_sample.sqlite, shorthand
    suppressPackageStartupMessages(library(GenomicFeatures))
    samplefile <- system.file("extdata", "hg19_knownGene_sample.sqlite",
                              package="GenomicFeatures")
    txdb <- loadDb(samplefile)
    txdb
    library(TxDb.Hsapiens.UCSC.hg19.knownGene)
    hg19_txdb <- TxDb.Hsapiens.UCSC.hg19.knownGene  # shorthand (for convenience)
    hg19_txdb

    # --- Seqlevels [] ---
    # Key functions: seqlevels, chr1, seqlevels0
    head(seqlevels(hg19_txdb))
    seqlevels(hg19_txdb) <- "chr1"
    seqlevels(hg19_txdb) <- seqlevels0(hg19_txdb)

    # --- Seqlevels4 [] ---
    # Key functions: seqlevels, chr15, columns, keytypes, select
    seqlevels(hg19_txdb) <- "chr15"
    seqlevels(hg19_txdb)
    keys <- c("100033416", "100033417", "100033420")
    columns(hg19_txdb)
    keytypes(hg19_txdb)
    select(hg19_txdb, keys = keys, columns="TXNAME", keytype="GENEID")
    columns(hg19_txdb)
    cols <- c("TXNAME", "TXSTRAND", "TXCHROM")
    select(hg19_txdb, keys=keys, columns=cols, keytype="GENEID")

    # --- Transcripts1 [] ---
    # Key functions: transcripts, strand, runLength, chr15
    GR <- transcripts(hg19_txdb)
    GR[1:3]
    tx_strand <- strand(GR)
    tx_strand
    sum(runLength(tx_strand))
    length(GR)
    GR <- transcripts(hg19_txdb, filter=list(tx_chrom = "chr15", tx_strand = "+"))
    length(GR)
    unique(strand(GR))

    # --- Transcripts4 [] ---
    # Key functions: promoters, exons, transcriptsBy, gene
    PR <- promoters(hg19_txdb, upstream=2000, downstream=400)
    PR
    EX <- exons(hg19_txdb)
    EX[1:4]
    length(EX)
    length(GR)
    GRList <- transcriptsBy(hg19_txdb, by = "gene")
    length(GRList)
    names(GRList)[10:13]
    GRList[11:12]

    # --- Exons By [] ---
    # Key functions: exonsBy, select, intronsByTranscript, fiveUTRsByTranscript, threeUTRsByTranscript, suppressPackageStartupMessages, shorthand, extractTranscriptSeqs
    GRList <- exonsBy(hg19_txdb, by = "tx")
    length(GRList)
    names(GRList)[10:13]
    GRList[[12]]
    GRList <- exonsBy(hg19_txdb, by = "tx")
    tx_ids <- names(GRList)
    head(select(hg19_txdb, keys=tx_ids, columns="TXNAME", keytype="TXID"))

    ## ----introns-UTRs-------------------------------------------------------------
    length(intronsByTranscript(hg19_txdb))
    length(fiveUTRsByTranscript(hg19_txdb))
    length(threeUTRsByTranscript(hg19_txdb))
    suppressPackageStartupMessages(library(BSgenome.Hsapiens.UCSC.hg19))
    genome <- BSgenome.Hsapiens.UCSC.hg19  # shorthand (for convenience)
    tx_seqs1 <- extractTranscriptSeqs(genome, hg19_txdb, use.names=TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_genomicfeatures_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_genomicfeatures_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_genomicfeatures_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GENOMICFEATURES:", paste0("    genomicfeatures: ", packageVersion("GenomicFeatures"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genomicfeatures_results.csv
    touch ${prefix}_genomicfeatures_output.rds
    echo "BIOC_GENOMICFEATURES:" > versions.yml
    echo "    genomicfeatures: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GENOMICFEATURES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GENOMICFEATURES(ch_input)

    emit:
    results  = BIOC_GENOMICFEATURES.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GENOMICFEATURES.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GENOMICFEATURES.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GENOMICFEATURES.out.versions  // channel: path(versions.yml)
}
