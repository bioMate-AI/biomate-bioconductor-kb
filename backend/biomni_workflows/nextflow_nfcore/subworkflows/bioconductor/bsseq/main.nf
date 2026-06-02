#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: bsseq
// A collection of tools for analyzing and visualizing whole-genome methylation data from sequencing. T
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/bsseq/inst/doc/bsseq.R
// Upstream  : bsseqData
// Downstream: biscuiteer, dmrseq, DSS, bsseqData
//
// Install: BiocManager::install("bsseq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BSSEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-bsseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-bsseq:1.42.0--r44_0' :
        'quay.io/biocontainers/bioconductor-bsseq:1.42.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_bsseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_bsseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_bsseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BSseq)
    library(GRanges)
    library(jsonlite)

    # --- Create GenomicRanges object [] ---
    # Key functions: sampleNames, pData, subsetByOverlaps, GRanges
    head(start(BS.chr22), n = 4)
    head(seqnames(BS.chr22), n = 4)
    sampleNames(BS.chr22)
    # --- B Sseq [] ---
    # Key functions: BSseq
    M <- matrix(0:8, 3, 3)
    Cov <- matrix(1:9, 3, 3)
    BStmp <- BSseq(chr = c("chr1", "chrX", "chr1"), pos = 1:3,
    # --- granges [] ---
    # Key functions: granges, orderBSseq
    granges(BStmp)
    BStmp <- orderBSseq(BStmp, seqOrder = c("chr1", "chrX"))
    granges(BStmp)
    # --- chr Select B Sseq [] ---
    # Key functions: chrSelectBSseq
    chrSelectBSseq(BStmp, seqnames = "chr1", order = TRUE)
    # --- combine [] ---
    # Key functions: combine, granges, getCoverage
    BStmp2 <- combine(BStmp, BS.chr22[1:3,])
    granges(BStmp2)
    getCoverage(BStmp2)
    # --- collapse B Sseq [] ---
    # Key functions: collapseBSseq
    collapseBSseq(BStmp, group = c("A", "A", "B"))
    # --- Create GenomicRanges object [] ---
    # Key functions: GRanges, getCoverage
    regions <- GRanges(seqnames = c("chr22", "chr22"),
    ranges = IRanges(start = 1.5 * 10^7 + c(0,200000),
    getCoverage(BS.chr22, regions = regions, what = "perRegionTotal")
    # --- get Coverage [] ---
    # Key functions: getCoverage
    getCoverage(BS.chr22, regions = regions, what = "perBase")
    # --- get Meth [] ---
    # Key functions: getMeth
    getMeth(BS.chr22, regions, type = "raw")
    getMeth(BS.chr22, regions[2], type = "raw", what = "perBase")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_bsseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_bsseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_bsseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BSSEQ:", paste0("    bsseq: ", packageVersion("bsseq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bsseq_results.csv
    touch ${prefix}_bsseq_output.rds
    echo "BIOC_BSSEQ:" > versions.yml
    echo "    bsseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BSSEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BSSEQ(ch_input)

    emit:
    results  = BIOC_BSSEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BSSEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BSSEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BSSEQ.out.versions  // channel: path(versions.yml)
}
