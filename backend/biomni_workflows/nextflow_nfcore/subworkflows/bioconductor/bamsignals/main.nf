#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: bamsignals
// This package allows to efficiently obtain count vectors from indexed bam files. It counts the number
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/bamsignals/inst/doc/bamsignals.R
// Upstream  : GenomicRanges, Rsamtools
// Downstream: none
//
// Install: BiocManager::install("bamsignals")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BAMSIGNALS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-bamsignals"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-bamsignals:1.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-bamsignals:1.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_bamsignals_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_bamsignals_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_bamsignals_plots.pdf"),    emit: plots, optional: true
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

    # --- Seqinfo [] ---
    # Key functions: seqinfo, BamFile
    ---------------------------------------------------------------------
    #sequence names of the GenomicRanges object
    seqinfo(genes)
    #sequence names in the bam file
    bf <- Rsamtools::BamFile(bampath)
    # --- Promoters [] ---
    # Key functions: promoters, bamCount
    ---------------------------------------------------------------------
    proms <- GenomicRanges::promoters(genes, upstream=100, downstream=100)
    counts <- bamCount(bampath, proms, verbose=FALSE)
    str(counts)
    # --- Bamcount [] ---
    # Key functions: bamCount
    ---------------------------------------------------------------------
    counts <- bamCount(bampath, proms, verbose=FALSE, shift=75)
    str(counts)
    # --- Strand [] ---
    # Key functions: strand, bamCount
    ---------------------------------------------------------------------
    strand(proms)
    counts <- bamCount(bampath, proms, verbose=FALSE, ss=TRUE)
    str(counts)
    # --- Bamprofile [] ---
    # Key functions: bamProfile
    ---------------------------------------------------------------------
    sigs <- bamProfile(bampath, genes, verbose=FALSE)
    sigs
    # --- Stopifnot [] ---
    # Key functions: all, width
    ---------------------------------------------------------------------
    stopifnot(all(width(sigs)==width(genes)))
    # --- Bamprofile [] ---
    # Key functions: bamProfile
    ---------------------------------------------------------------------
    sssigs <- bamProfile(bampath, genes, verbose=FALSE, ss=TRUE)
    sssigs
    # --- Str [] ---
    # Key functions: colSums, width
    ---------------------------------------------------------------------
    str(sssigs[1])
    #summing up the counts from the two strands is the same as using ss=FALSE
    stopifnot(colSums(sssigs[1])==sigs[1])
    #the width function takes into account that now the signals are strand-specific
    # --- Pair [] ---
    # Key functions: pair, seqnames, start, end
    ---------------------------------------------------------------------
    xlab <- "offset from start of the region"
    ylab <- "counts per base pair (negative means antisense)"
    main <- paste0("read profile of the region ",
      seqnames(genes)[1], ":", start(genes)[1], "-", end(genes)[1])
    # --- Bamprofile [] ---
    # Key functions: bamProfile, alignSignals
    ---------------------------------------------------------------------
    #The promoter regions have all the same width
    sigs <- bamProfile(bampath, proms, ss=FALSE, verbose=FALSE)
    sssigs <- bamProfile(bampath, proms, ss=TRUE, verbose=FALSE)
    sigsMat <- alignSignals(sigs)
    # --- Rowmeans [] ---
    # Key functions: rowMeans
    ---------------------------------------------------------------------
    avgSig <- rowMeans(sigsMat)
    avgSenseSig <- rowMeans(sigsArr["sense",,])
    avgAntisenseSig <- rowMeans(sigsArr["antisense",,])
    ylab <- "average counts per base pair"
    # --- Bamprofile [] ---
    # Key functions: bamProfile, all, width
    ---------------------------------------------------------------------
    binsize <- 20
    binnedSigs <- bamProfile(bampath, proms, binsize=binsize, verbose=FALSE)
    stopifnot(all(width(binnedSigs)==ceiling(width(sigs)/binsize)))
    binnedSigs
    # --- Rowmeans [] ---
    # Key functions: rowMeans, alignSignals, equal, colSums
    ---------------------------------------------------------------------
    avgBinnedSig <- rowMeans(alignSignals(binnedSigs))
    #the counts in the bin are the sum of the counts in each base pair
    stopifnot(all.equal(colSums(matrix(avgSig, nrow=binsize)),avgBinnedSig))
    #let's plot it
    # --- Bamcoverage [] ---
    # Key functions: bamCoverage, bamProfile, seqnames, start, end
    ---------------------------------------------------------------------
    covSigs <- bamCoverage(bampath, genes, verbose=FALSE)
    puSigs <- bamProfile(bampath, genes, verbose=FALSE)
    xlab <- "offset from start of the region"
    ylab <- "reads per base pair"
    # --- Bamcount [] ---
    # Key functions: bamCount
    ---------------------------------------------------------------------
    counts.all <- bamCount(bampath, proms, verbose=FALSE)
    summary(counts.all)
    counts.mapq <- bamCount(bampath, proms, mapq=20, verbose=FALSE)
    summary(counts.mapq)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_bamsignals_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_bamsignals_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_bamsignals_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BAMSIGNALS:", paste0("    bamsignals: ", packageVersion("bamsignals"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bamsignals_results.csv
    touch ${prefix}_bamsignals_output.rds
    echo "BIOC_BAMSIGNALS:" > versions.yml
    echo "    bamsignals: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BAMSIGNALS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BAMSIGNALS(ch_input)

    emit:
    results  = BIOC_BAMSIGNALS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BAMSIGNALS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BAMSIGNALS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BAMSIGNALS.out.versions  // channel: path(versions.yml)
}
