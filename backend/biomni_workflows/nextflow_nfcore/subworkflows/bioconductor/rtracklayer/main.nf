#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: rtracklayer
// Extensible framework for interacting with multiple genome browsers (currently UCSC built-in) and man
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/rtracklayer/inst/doc/rtracklayer.R
// Upstream  : GenomicRanges, genefilter, humanStemCell, limma, microRNA
// Downstream: BSgenome, CAGEfightR, CoverageView, CSSQ, cummeRbund
//
// Install: BiocManager::install("rtracklayer")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RTRACKLAYER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rtracklayer"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rtracklayer:1.66.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rtracklayer:1.66.0--r44_0'}"

    input:
    tuple val(meta), path(marraylm)

    output:
    tuple val(meta), path("${meta.id}_rtracklayer_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rtracklayer_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rtracklayer_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GRanges)
    library(GRangesForUCSCGenome)
    library(GenomicData)
    library(IRanges)
    library(jsonlite)

    # --- Rtl Init [] ---
    # Key functions: nsFilter, lmFit, eBayes, topTable
    library("humanStemCell")
    data(fhesc)
    library("genefilter")
    filtFhesc <- nsFilter(fhesc)[[1]]
    library("limma")
    # --- Rtl Mirna Track [] ---
    # Key functions: IRanges, with, GRangesForUCSCGenome
    library(rtracklayer)
    library(GenomicRanges)
    ## call data(targets) if skipping first block
    head(targets)
    targetRanges <- IRanges(targets$start, targets$end)
    # --- Rtl Mirna Track Seqinfo [] ---
    # Key functions: genome, seqlengths
    genome(targetTrack)
    head(seqlengths(targetTrack))
    # --- Feature Data Accessors [] ---
    # Key functions: seqnames, start
    head(seqnames(targetTrack))
    head(start(targetTrack))
    # --- Sol 1 [] ---
    # Key functions: strand, width, frame, factor, seqnames, start, end
    head(strand(targetTrack))
    head(width(targetTrack))
    data.frame(chrom = as.factor(seqnames(targetTrack)),
               start = start(targetTrack), end = end(targetTrack),
               strand = as.factor(strand(targetTrack)))
    # --- Subset Features [] ---
    # Key functions: strand, seqnames
    ## get the first 10 targets
    first10 <- targetTrack[1:10]
    ## get pos strand targets
    posTargets <- targetTrack[strand(targetTrack) == "+"]
    ## get the targets on chr1
    # --- Sol 2 [] ---
    # Key functions: strand, seqnames
    negChr2Targets <- targetTrack[strand(targetTrack) == "-" &
                                  seqnames(targetTrack) == "chr2"]
    # --- Export [] ---
    # Key functions: export
    ## export(targetTrack, "targets.bed")
    # --- Import [] ---
    # Key functions: import
    ## restoredTrack <- import("targets.bed")
    # --- Sol 3 [] ---
    # Key functions: export, import
    export(targetTrack, "targets.gff")
    targetGff <- import("targets.gff")
    targetChar <- export(targetTrack, format = "gff1")
    # --- Browsersession [] ---
    # Key functions: browserSession
    ## session <- browserSession("UCSC")
    # --- Laytrack [] ---
    # Key functions: track
    ## track(session, "targets") <- targetTrack
    # --- View Subset [] ---
    # Key functions: browserView
    ## view <- browserView(session, subTargetTrack * -10, pack = "targets")
    # --- View Subset Multi [] ---
    # Key functions: browserView
    ## view <- browserView(session, targetTrack[1:5] * -10, pack = "targets")
    # --- Sol 6 [] ---
    # Key functions: browserView
    ## viewOut <- browserView(session, range(view) * -2)
    ## viewFull <- browserView(session, full = "targets")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rtracklayer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rtracklayer_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rtracklayer_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RTRACKLAYER:", paste0("    rtracklayer: ", packageVersion("rtracklayer"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rtracklayer_results.csv
    touch ${prefix}_rtracklayer_output.rds
    echo "BIOC_RTRACKLAYER:" > versions.yml
    echo "    rtracklayer: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RTRACKLAYER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(marraylm) ]

    main:
    BIOC_RTRACKLAYER(ch_input)

    emit:
    results  = BIOC_RTRACKLAYER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RTRACKLAYER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RTRACKLAYER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RTRACKLAYER.out.versions  // channel: path(versions.yml)
}
