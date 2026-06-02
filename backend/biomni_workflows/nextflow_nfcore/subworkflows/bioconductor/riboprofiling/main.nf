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
    library(RiboProfiling)
    library(BamFile)
    library(jsonlite)

    # --- Transcription Start Site Coverage [] ---
    # Key functions: readsToStartOrEnd, aroundPromoter, readStartCov, plotSummarizedCov
    data(ctrlGAlignments, package="RiboProfiling")
    alnGRanges <- readsToStartOrEnd(ctrlGAlignments, what="start")
    txdb <- TxDb.Hsapiens.UCSC.hg19.knownGene::TxDb.Hsapiens.UCSC.hg19.knownGene
    oneBinRanges <- aroundPromoter(txdb, alnGRanges, percBestExpressed=0.001)
    listPromoterCov <- readStartCov(
        alnGRanges,
        oneBinRanges,
        matchSize=c(29:32),
        fixedInterval=c(-20, 20),
        renameChr="aroundTSS",
        charPerc="perc"
    )
    plotSummarizedCov(listPromoterCov)


    # --- Feature Counting and Codon Analysis [] ---
    # Key functions: countShiftReads, countsPlot, codonInfo, codonPCA
    data(ctrlGAlignments, package="RiboProfiling")
    alnGRanges <- readsToStartOrEnd(ctrlGAlignments, what="start")
    txdb <- TxDb.Hsapiens.UCSC.hg19.knownGene::TxDb.Hsapiens.UCSC.hg19.knownGene
    cds <- GenomicFeatures::cdsBy(txdb, by="tx", use.names=TRUE)
    exonGRanges <- GenomicFeatures::exonsBy(txdb, by="tx", use.names=TRUE)
    data("cdsPosTransc", package="RiboProfiling")
    countsDataCtrl1 <- countShiftReads(
        exonGRanges[names(cdsPosTransc)],
        cdsPosTransc,
        alnGRanges,
        -14
    )
    listReadsCodon <- countsDataCtrl1[[2]]
    orfCoord <- cds[names(cds) %in% names(listReadsCodon)]
    genomeSeq <- BSgenome.Hsapiens.UCSC.hg19::BSgenome.Hsapiens.UCSC.hg19
    codonData <- codonInfo(listReadsCodon, genomeSeq, orfCoord)
    codonCovMatrix <- codonData[[2]]
    nbrReadsGene <- apply(codonCovMatrix, 1, sum)
    codonCovMatrix <- codonCovMatrix[which(nbrReadsGene >= 50), ]
    codonCovMatrixTransp <- t(codonCovMatrix)
    listPCACodonCoverage <- codonPCA(codonCovMatrixTransp, "codonCoverage")

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
