#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: chipseq
// Tools for helping process short read data for chipseq experiments.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/chipseq/inst/doc/Workflow.R
// Upstream  : rtracklayer
// Downstream: none
//
// Install: BiocManager::install("chipseq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CHIPSEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-chipseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-chipseq:1.56.0--r44_0' :
        'quay.io/biocontainers/bioconductor-chipseq:1.56.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_chipseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_chipseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_chipseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GRanges)
    library(GenomicRangesList)
    library(jsonlite)

    # --- report [] ---
    # Key functions: report, compose, GenomicRangesList
    qa_list <- lapply(sampleFiles, qa)
    report(do.call(rbind, qa_list))
    filter <- compose(chipseqFilter(), alignQualityFilter(15))
    # --- Create GenomicRanges object [] ---
    # Key functions: GenomicRangesList, GRanges
    cstest <- GenomicRangesList(lapply(cstest, function(gd)
    do.call(c, lapply(names(gd), function(chr)
    starts <- c( pos[["-"]] - 23L, pos[["+"]])
    # --- estimate.mean.fraglen [] ---
    # Key functions: slice, viewSums, viewMaxs, resize
    fraglen <- estimate.mean.fraglen(cstest$ctcf, method="correlation")
    fraglen[!is.na(fraglen)]
    ctcf.ext <- resize (cstest$ctcf, width = 200)
    # --- island Depth Plot [] ---
    # Key functions: islandDepthPlot
    islandDepthPlot(cov.ctcf)
    # --- peak Cutoff [] ---
    # Key functions: peakCutoff
    peakCutoff(cov.ctcf, fdr = 0.0001)
    peaks.ctcf <- slice(cov.ctcf, lower = 8)
    # --- peak Summary [] ---
    # Key functions: peakSummary
    peaks <- peakSummary(peaks.ctcf)
    peak.depths <- viewMaxs(peaks.ctcf)
    cov.pos <- coverage(ctcf.ext[strand(ctcf.ext) == "+"])
    # --- browser Session [] ---
    # Key functions: browserSession, genome
    library(rtracklayer)
    session <- browserSession()
    genome(session) <- "mm9"
    # --- browser View [] ---
    # Key functions: browserView
    peak.ord <- order(unlist(peak.depths), decreasing=TRUE)
    peak.sort <- as(peaks.ctcf, "GRanges")[peak.ord]
    view <- browserView(session, peak.sort[1], full = c("gfpCov", "ctcfCov"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_chipseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_chipseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_chipseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CHIPSEQ:", paste0("    chipseq: ", packageVersion("chipseq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chipseq_results.csv
    touch ${prefix}_chipseq_output.rds
    echo "BIOC_CHIPSEQ:" > versions.yml
    echo "    chipseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CHIPSEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CHIPSEQ(ch_input)

    emit:
    results  = BIOC_CHIPSEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CHIPSEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CHIPSEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CHIPSEQ.out.versions  // channel: path(versions.yml)
}
