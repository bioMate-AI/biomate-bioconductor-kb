#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: QuasR
// This package provides a framework for the quantification and analysis of Short Reads. It covers a co
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/QuasR/inst/doc/QuasR.R
// Upstream  : BSgenome, BiocManager, Biostrings, GenomicFeatures, Gviz
// Downstream: none
//
// Install: BiocManager::install("QuasR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_QUASR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-quasr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-quasr:1.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-quasr:1.46.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_quasr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_quasr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_quasr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(QuasR)
    library(DataTrack)
    library(GeneRegionTrack)
    library(GenomeAxisTrack)
    library(IRanges)
    library(jsonlite)

    # --- Sequence Alignment [] ---
    # Key functions: qAlign
    sampleFile <- "extdata/samples_chip_single.txt"
    genomeFile <- "extdata/hg19sub.fa"
    auxFile <- "extdata/auxiliaries.txt"
    proj <- qAlign(
        sampleFile = sampleFile,
        genome = genomeFile,
        auxiliaryFile = auxFile
    )


    # --- Quality Control and Statistics [] ---
    # Key functions: qQCReport, alignmentStats
    qc_stats <- alignmentStats(proj)
    qcdat <- qQCReport(
        proj,
        pdfFilename = "qc_report.pdf"
    )


    # --- Genomic Feature Quantification [] ---
    # Key functions: qCount
    query_regions <- GenomicRanges::GRanges(
        seqnames = c("chr3", "chr3"),
        ranges = IRanges::IRanges(
            start = c(1000, 5000),
            end = c(2000, 6000)
        )
    )
    cnt <- qCount(proj, query = query_regions)


    # --- Export to Wiggle Format [] ---
    # Key functions: qExportWig
    qExportWig(
        proj,
        binsize = 100L,
        scaling = TRUE,
        collapseBySample = TRUE
    )


    # --- Signal Profiling [] ---
    # Key functions: qProfile
    tssRegions <- GenomicRanges::GRanges(
        seqnames = c("chr3"),
        ranges = IRanges::IRanges(
            start = c(1500, 5500),
            width = 1
        )
    )
    prS <- qProfile(
        proj,
        tssRegions,
        upstream = 3000,
        downstream = 3000,
        orientation = "same"
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_quasr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_quasr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_quasr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_QUASR:", paste0("    quasr: ", packageVersion("QuasR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_quasr_results.csv
    touch ${prefix}_quasr_output.rds
    echo "BIOC_QUASR:" > versions.yml
    echo "    quasr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_QUASR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_QUASR(ch_input)

    emit:
    results  = BIOC_QUASR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_QUASR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_QUASR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_QUASR.out.versions  // channel: path(versions.yml)
}
