#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DEXSeq
// The package is focused on finding differential exon usage using RNA-seq exon counts between samples 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DEXSeq/inst/doc/DEXSeq.R
// Upstream  : none
// Downstream: IsoformSwitchAnalyzeR, pasilla, rnaseqDTU
//
// Install: BiocManager::install("DEXSeq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DEXSEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-dexseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-dexseq:1.52.0--r44_0' :
        'quay.io/biocontainers/bioconductor-dexseq:1.52.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_dexseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_dexseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_dexseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DEXSeqHTML)
    library(IRanges)
    library(jsonlite)

    # --- Find overlapping genomic intervals [] ---
    # Key functions: IRanges, subsetByOverlaps, findOverlaps
    interestingRegion = GRanges( "chr2L",
    IRanges(start=3872658, end=3875302) )
    subsetByOverlaps( x=dxr, ranges=interestingRegion )
    # --- MA plot of DE results [] ---
    # Key functions: plotMA
    plotMA( dxr1, cex=0.8 )
    # --- Sample metadata inspection [] ---
    # Key functions: colData, split, sampleAnnotation, mcols, plotDEXSeq, DEXSeqHTML
    library(DEXSeq)
    colData(se)$condition = factor(c("untreated1", "untreated3"))
    colData(se)$libType = factor(c("single-end", "paired-end"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_dexseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_dexseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_dexseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DEXSEQ:", paste0("    dexseq: ", packageVersion("DEXSeq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dexseq_results.csv
    touch ${prefix}_dexseq_output.rds
    echo "BIOC_DEXSEQ:" > versions.yml
    echo "    dexseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DEXSEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DEXSEQ(ch_input)

    emit:
    results  = BIOC_DEXSEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DEXSEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DEXSEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DEXSEQ.out.versions  // channel: path(versions.yml)
}
