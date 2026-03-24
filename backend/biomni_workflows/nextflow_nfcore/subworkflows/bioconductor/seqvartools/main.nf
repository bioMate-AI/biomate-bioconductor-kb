#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SeqVarTools
// An interface to the fast-access storage format for VCF data provided in SeqArray, with tools for com
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SeqVarTools/inst/doc/Iterators.R
// Upstream  : Biobase, GenomicRanges
// Downstream: none
//
// Install: BiocManager::install("SeqVarTools")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SEQVARTOOLS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-seqvartools"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-seqvartools:1.44.0--r44_0' :
        'quay.io/biocontainers/bioconductor-seqvartools:1.44.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_seqvartools_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_seqvartools_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_seqvartools_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GRanges)
    library(GRangesList)
    library(IRanges)
    library(SeqVarBlockIterator)
    library(SeqVarData)
    library(SeqVarListIterator)
    library(SeqVarRangeIterator)
    library(SeqVarWindowIterator)
    library(jsonlite)

    # --- Seqopen [] ---
    # Key functions: seqOpen, seqExampleFileName, SeqVarData, SeqVarBlockIterator, variantInfo
    library(SeqVarTools)
    gds <- seqOpen(seqExampleFileName("gds"))
    seqData <- SeqVarData(gds)
    iterator <- SeqVarBlockIterator(seqData, variantBlock=500)
    var.info <- list(variantInfo(iterator))
    # --- Seqsetfilter [] ---
    # Key functions: seqSetFilter, SeqVarBlockIterator, variantInfo, iterateFilter, seqResetFilter
    seqSetFilter(seqData, variant.sel=1:100)
    iterator <- SeqVarBlockIterator(seqData, variantBlock=500)
    var.info <- variantInfo(iterator)
    nrow(var.info)
    iterateFilter(iterator)
    # --- Granges [] ---
    # Key functions: GRanges, IRanges, SeqVarRangeIterator, variantInfo
    library(GenomicRanges)
    gr <- GRanges(seqnames=rep(1,3),
                  ranges=IRanges(start=c(1e6, 2e6, 3e6), width=1e6))
    iterator <- SeqVarRangeIterator(seqData, variantRanges=gr)
    var.info <- list(variantInfo(iterator))
    # --- Seqsetfilterchrom [] ---
    # Key functions: seqSetFilterChrom, SeqVarWindowIterator, variantInfo, iterateFilter, seqResetFilter
    seqSetFilterChrom(seqData, include="22")
    iterator <- SeqVarWindowIterator(seqData, windowSize=10000,
                                     windowShift=5000)
    var.info <- list(variantInfo(iterator))
    i <- 2
    # --- Grangeslist [] ---
    # Key functions: GRangesList, GRanges, IRanges, SeqVarListIterator, variantInfo
    gr <- GRangesList(
      GRanges(seqnames=rep(22,2),
              ranges=IRanges(start=c(16e6, 17e6), width=1e6)),
      GRanges(seqnames=rep(22,2),
              ranges=IRanges(start=c(18e6, 20e6), width=1e6)))
    # --- Variantinfo [] ---
    # Key functions: variantInfo, resetIterator
    variantInfo(iterator)
    resetIterator(iterator)
    variantInfo(iterator)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_seqvartools_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_seqvartools_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_seqvartools_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SEQVARTOOLS:", paste0("    seqvartools: ", packageVersion("SeqVarTools"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_seqvartools_results.csv
    touch ${prefix}_seqvartools_output.rds
    echo "BIOC_SEQVARTOOLS:" > versions.yml
    echo "    seqvartools: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SEQVARTOOLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SEQVARTOOLS(ch_input)

    emit:
    results  = BIOC_SEQVARTOOLS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SEQVARTOOLS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SEQVARTOOLS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SEQVARTOOLS.out.versions  // channel: path(versions.yml)
}
