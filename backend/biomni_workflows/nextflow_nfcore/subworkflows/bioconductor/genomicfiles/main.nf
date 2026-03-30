#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GenomicFiles
// This package provides infrastructure for parallel computations distributed 'by file' or 'by range'. 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GenomicFiles/inst/doc/GenomicFiles.R
// Upstream  : BiocManager, GenomicAlignments
// Downstream: erma, IntEREst
//
// Install: BiocManager::install("GenomicFiles")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENOMICFILES {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-genomicfiles"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-genomicfiles:1.42.0--r44_0' :
        'quay.io/biocontainers/bioconductor-genomicfiles:1.42.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_genomicfiles_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_genomicfiles_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_genomicfiles_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BamFile)
    library(GRanges)
    library(GenomicFiles)
    library(ScanBamParam)
    library(jsonlite)

    # --- Create GenomicRanges object [] ---
    # Key functions: GRanges
    gr <- GRanges("chr14", IRanges(c(19100000, 106000000), width=1e7))
    # --- Count overlapping genomic regions [] ---
    # Key functions: unlist, requireNamespace, countOverlaps, BamFile
    FUN <- function(file, gr, YIELD, MAP, REDUCE, tiles, ...) {
    requireNamespace("GenomicAlignments") ## for BamFile, readGAlignments()
    requireNamespace("GenomicFiles") ## for reduceByYield()
    # --- Compute genomic coverage [] ---
    # Key functions: requireNamespace, ScanBamParam, coverage
    MAP = function(range, file, ...) {
    requireNamespace("GenomicAlignments")  ## for ScanBamParam() and coverage()
    GenomicAlignments::coverage(
    # --- Sequence level inspection [] ---
    # Key functions: requireNamespace, pileup, reduceByFile, xtabs, reduceByRange, GenomicFiles, include_graphics, bam2R
    MAP = function(range, file, ...) {
    requireNamespace("GenomicAlignments") ## for ScanBamParam() and coverage()
    param = Rsamtools::ScanBamParam(which=range)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_genomicfiles_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_genomicfiles_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_genomicfiles_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GENOMICFILES:", paste0("    genomicfiles: ", packageVersion("GenomicFiles"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genomicfiles_results.csv
    touch ${prefix}_genomicfiles_output.rds
    echo "BIOC_GENOMICFILES:" > versions.yml
    echo "    genomicfiles: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GENOMICFILES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GENOMICFILES(ch_input)

    emit:
    results  = BIOC_GENOMICFILES.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GENOMICFILES.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GENOMICFILES.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GENOMICFILES.out.versions  // channel: path(versions.yml)
}
