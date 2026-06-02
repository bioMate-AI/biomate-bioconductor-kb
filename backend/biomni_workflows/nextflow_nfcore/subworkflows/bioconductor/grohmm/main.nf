#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: groHMM
// A pipeline for the analysis of GRO-seq data.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/groHMM/inst/doc/groHMM.R
// Upstream  : GenomicFeatures, edgeR
// Downstream: none
//
// Install: BiocManager::install("groHMM")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GROHMM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-grohmm"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-grohmm:1.40.3--r44_0' :
        'quay.io/biocontainers/bioconductor-grohmm:1.40.3--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_grohmm_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_grohmm_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_grohmm_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GRanges)
    library(IRanges)
    library(NROW)
    library(Position)
    library(jsonlite)

    # --- Install Grohmm [] ---
    # Key functions: requireNamespace, packages
    ## if (!requireNamespace("BiocManager", quietly=TRUE))
    ##     install.packages("BiocManager")
    ## BiocManager::install("groHMM")
    ##
    # --- Use Grohmm [] ---
    # Key functions: getCores
    library(groHMM)
    options(mc.cores=getCores(4))
    # --- Load Data [] ---
    # Key functions: readGAlignments
    S0mR1 <- as(readGAlignments(system.file("extdata", "S0mR1.bam",
            package="groHMM")), "GRanges")
    S0mR2 <- as(readGAlignments(system.file("extdata", "S0mR1.bam",
            package="groHMM")), "GRanges") # Use R1 as R2
    # --- Write Wiggle Files [] ---
    # Key functions: writeWiggle, seqinfo, NROW
    ## writeWiggle(reads=S0m, file="S0m_Plus.wig", fileType="wig", strand="+",
    ##         reverse=FALSE)
    ## writeWiggle(reads=S0m, file="S0m_Minus.wig", fileType="wig", strand="-",
    ##         reverse=TRUE)
    ##
    # --- Transcript Calling [] ---
    # Key functions: detectTranscripts
    Sall <- sort(c(S0m, S40m))
    # hmmResult <- detectTranscripts(Sall, LtProbB=-200, UTS=5,
    #                   threshold=1)
    # Load hmmResult from the saved previous run
    load(system.file("extdata", "Vignette.RData", package="groHMM"))
    # --- Use Ucsc Genes [] ---
    # Key functions: makeTxDbFromUCSC, saveDb, loadDb, transcripts, seqlevels
    library(TxDb.Hsapiens.UCSC.hg19.knownGene)
    kgdb <- TxDb.Hsapiens.UCSC.hg19.knownGene
    library(GenomicFeatures)
    # For refseq annotations:
    # rgdb <- makeTxDbFromUCSC(genome="hg19", tablename="refGene")
    # --- Make Consensus Annotations [] ---
    # Key functions: makeConsensusAnnotations, getOption, select, unlist, mcols
    # Collapse overlapping annotations
    kgConsensus <- makeConsensusAnnotations(kgChr7, keytype="gene_id",
            mc.cores=getOption("mc.cores"))
    library(org.Hs.eg.db)
    # --- Evaluation Of Transcript Calling [] ---
    # Key functions: evaluateHMMInAnnotations
    e <- evaluateHMMInAnnotations(txHMM, kgConsensus)
    e$eval
    # --- Tuning Hmm [] ---
    # Key functions: frame, windowAnalysis, mclapply, detectTranscripts
    tune <- data.frame(LtProbB=c(rep(-100,3), rep(-200,3), rep(-300,3)),
               UTS=rep(c(5,10,15), 3))
    Fp <- windowAnalysis(Sall, strand="+", windowSize=50)
    Fm <- windowAnalysis(Sall, strand="-", windowSize=50)
    # --- Expressed Genes [] ---
    # Key functions: limitToXkb, countOverlaps, width, getExpressedAnnotations

    # --- get Tx Density [] ---
    # Key functions: getTxDensity, getOption
    td <- getTxDensity(txHMM, conExpressed, mc.cores=getOption("mc.cores"))
    u <- par("usr")
    lines(c(u[1], 0, 0, 1000, 1000, u[2]), c(0,0,u[4]-.04,u[4]-.04,0,0),
          col="red")
    legend("topright", lty=c(1,1), col=c(2,1), c("ideal", "groHMM"))
    # --- Fig2 [] ---
    # Key functions: getTxDensity, getOption
    td <- getTxDensity(txHMM, conExpressed, mc.cores=getOption("mc.cores"))
    u <- par("usr")
    lines(c(u[1], 0, 0, 1000, 1000, u[2]), c(0,0,u[4]-.04,u[4]-.04,0,0),
          col="red")
    legend("topright", lty=c(1,1), col=c(2,1), c("ideal", "groHMM"))
    # --- Non Mammalian [] ---
    # Key functions: GRanges, IRanges, makeConsensusAnnotations, getOption
    ## # mysql --user=genome --host=genome-mysql.cse.ucsc.edu ce10 -e \
    ## #  "select chrom, txStart, txEnd, name, exonCount, strand, name2 from refGene \
    ## #   where chrom not like chrom!='chrM' and cdsStart != cdsEnd" | tail -n +1 > refgene.bed
    ##
    ## # G <- read.table("refgene.bed", header=TRUE, stringsAsFactors=FALSE, sep="\t")
    # --- Repairing Called Transcripts [] ---
    # Key functions: breakTranscriptsOnGenes, combineTranscripts
    bPlus <- breakTranscriptsOnGenes(txHMM, kgConsensus, strand="+")
    bMinus <- breakTranscriptsOnGenes(txHMM, kgConsensus, strand="-")
    txBroken <- c(bPlus, bMinus)
    txFinal <- combineTranscripts(txBroken, kgConsensus)
    # --- Plottxdensity Final [] ---
    # Key functions: getTxDensity, getOption
    ## tdFinal <- getTxDensity(txFinal, conExpressed, mc.cores=getOption("mc.cores"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_grohmm_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_grohmm_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_grohmm_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GROHMM:", paste0("    grohmm: ", packageVersion("groHMM"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_grohmm_results.csv
    touch ${prefix}_grohmm_output.rds
    echo "BIOC_GROHMM:" > versions.yml
    echo "    grohmm: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GROHMM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GROHMM(ch_input)

    emit:
    results  = BIOC_GROHMM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GROHMM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GROHMM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GROHMM.out.versions  // channel: path(versions.yml)
}
