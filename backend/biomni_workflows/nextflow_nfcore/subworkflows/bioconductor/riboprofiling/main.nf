#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RiboProfiling
// Starting with a BAM file, this package provides the necessary functions for quality assessment, read
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RiboProfiling/inst/doc/RiboProfiling.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("RiboProfiling")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RIBOPROFILING {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-riboprofiling"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-riboprofiling:1.36.0--r44_0' :
        'quay.io/biocontainers/bioconductor-riboprofiling:1.36.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_riboprofiling_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_riboprofiling_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_riboprofiling_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BamFile)
    library(jsonlite)

    # --- Import library noEcho [] ---
    # Key functions: BamFile, riboSeqFromBAM
    library(RiboProfiling)
    listInputBam <- c(
    BamFile("http://genomique.info/data/public/RiboProfiling/ctrl.bam"),
    # --- ribo Seq From B A M [] ---
    # Key functions: riboSeqFromBAM
    myFileCtrl <- system.file("extdata", "ctrl_sample.bam", package="RiboProfiling")
    myFileNutlin2h <- system.file("extdata", "nutlin2h_sample.bam", package="RiboProfiling")
    listeInputBam <- c(myFileCtrl, myFileNutlin2h)
    # --- GAlignments from BAM [] ---
    # Key functions: readGAlignments, BamFile
    aln <- readGAlignments(
    BamFile("http://genomique.info/data/public/RiboProfiling/ctrl.bam")
    # --- Hist quick [] ---
    # Key functions: histMatchLength
    data(ctrlGAlignments)
    matchLenDistr <- histMatchLength(aln, 0)
    # --- CovAroundTSS quick [] ---
    # Key functions: readsToStartOrEnd, aroundPromoter, readStartCov, plotSummarizedCov
    alnGRanges <- readsToStartOrEnd(aln, what="start")
    oneBinRanges <- aroundPromoter(txdb, alnGRanges, percBestExpressed=0.001)
    readStartCov(
    # --- TSS Cov [] ---
    # Key functions: readsToStartOrEnd, renameSeqlevels, aroundPromoter, readStartCov
    (faster processing of the object)
    alnGRanges <- readsToStartOrEnd(aln, what="start")
    of the alignment files ("chr" particle)
    # --- CountReads echo [] ---
    # Key functions: cdsBy, exonsBy, orfRelativePos, countShiftReads, countsPlot
    alnGRanges <- alnGRanges[which(!is.na(match(alnGRanges$score,30:33)))]
    cds <- cdsBy(txdb, by="tx", use.names=TRUE)
    exonGRanges <- exonsBy(txdb, by="tx", use.names=TRUE)
    # --- cds By [] ---
    # Key functions: cdsBy, exonsBy, orfRelativePos, countShiftReads, countsPlot
    cds <- GenomicFeatures::cdsBy(txdb, by="tx", use.names=TRUE)
    exonGRanges <- GenomicFeatures::exonsBy(txdb, by="tx", use.names=TRUE)
    cdsPosTransc <- orfRelativePos(cds, exonGRanges)
    # --- CodonAnalysis echo [] ---
    # Key functions: cdsBy, codonInfo
    cds <- cdsBy(txdb, use.names=TRUE)
    orfCoord <- cds[names(cds) %in% names(listReadsCodon)]
    codonData <- codonInfo(listReadsCodon, genomeSeq, orfCoord)
    # --- cds By [] ---
    # Key functions: cdsBy, codonInfo
    cds <- GenomicFeatures::cdsBy(txdb, use.names=TRUE)
    orfCoord <- cds[names(cds) %in% names(listReadsCodon)]
    codonData <- codonInfo(listReadsCodon, genomeSeq, orfCoord)
    # --- codon P C A [] ---
    # Key functions: codonPCA
    nbrReadsGene <- apply(codonCovMatrix, 1, sum)
    ixExpGenes <- which(nbrReadsGene >= 50)
    codonCovMatrixTransp <- t(codonCovMatrix)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_riboprofiling_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_riboprofiling_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_riboprofiling_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RIBOPROFILING:", paste0("    riboprofiling: ", packageVersion("RiboProfiling"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_riboprofiling_results.csv
    touch ${prefix}_riboprofiling_output.rds
    echo "BIOC_RIBOPROFILING:" > versions.yml
    echo "    riboprofiling: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RIBOPROFILING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RIBOPROFILING(ch_input)

    emit:
    results  = BIOC_RIBOPROFILING.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RIBOPROFILING.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RIBOPROFILING.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RIBOPROFILING.out.versions  // channel: path(versions.yml)
}
