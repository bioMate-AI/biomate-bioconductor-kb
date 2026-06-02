#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: biovizBase
// The biovizBase package is designed to provide a set of utilities, color schemes and conventions for 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/biovizBase/inst/doc/intro.R
// Upstream  : GenomicRanges, Rsamtools, dichromat, rtracklayer, scales
// Downstream: CAFE
//
// Install: BiocManager::install("biovizBase")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIOVIZBASE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-biovizbase"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-biovizbase:1.54.0--r44_0' :
        'quay.io/biocontainers/bioconductor-biovizbase:1.54.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_biovizbase_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_biovizbase_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_biovizbase_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(biovizBase)
    library(GCcontent)
    library(GRanges)
    library(IRanges)
    library(jsonlite)

    # --- Gap Calculation [] ---
    # Key functions: maxGap
    gr_temp <- GenomicRanges::GRanges(
        seqnames = "chr1",
        ranges = IRanges::IRanges(start = c(100, 250), end = c(200, 300))
    )
    temp_gaps <- BiocGenerics::gaps(
        gr_temp,
        start = min(BiocGenerics::start(gr_temp))
    )
    gap_val <- maxGap(temp_gaps)
    gap_val_ratio <- maxGap(temp_gaps, ratio = 0.5)


    # --- Coordinate Shrinkage [] ---
    # Key functions: shrinkageFun, maxGap
    gr1 <- GenomicRanges::GRanges(
        "chr1",
        IRanges::IRanges(start = c(10, 300, 800), end = c(150, 400, 850))
    )
    gr2 <- GenomicRanges::GRanges(
        "chr1",
        IRanges::IRanges(start = c(100, 350, 550), end = c(220, 500, 900))
    )
    gaps_gr <- BiocGenerics::intersect(
        BiocGenerics::gaps(gr1, start = min(BiocGenerics::start(gr1))),
        BiocGenerics::gaps(gr2, start = min(BiocGenerics::start(gr2)))
    )
    shrink_fun <- shrinkageFun(gaps_gr, max.gap = maxGap(gaps_gr))
    shrunk_gr1 <- shrink_fun(gr1)
    shrunk_gr2 <- shrink_fun(gr2)


    # --- Gene Symbol Annotation [] ---
    # Key functions: genesymbol
    utils::data("genesymbol", package = "biovizBase")
    rbm17_coords <- genesymbol["RBM17"]
    all_symbols <- names(genesymbol)
    subset_symbols <- genesymbol[1:10]
    chromosomes <- GenomeInfoDb::seqnames(genesymbol)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_biovizbase_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_biovizbase_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_biovizbase_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BIOVIZBASE:", paste0("    biovizbase: ", packageVersion("biovizBase"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biovizbase_results.csv
    touch ${prefix}_biovizbase_output.rds
    echo "BIOC_BIOVIZBASE:" > versions.yml
    echo "    biovizbase: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BIOVIZBASE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BIOVIZBASE(ch_input)

    emit:
    results  = BIOC_BIOVIZBASE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BIOVIZBASE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BIOVIZBASE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BIOVIZBASE.out.versions  // channel: path(versions.yml)
}
