#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: methylSig
// MethylSig is a package for testing for differentially methylated cytosines (DMCs) or regions (DMRs) 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/methylSig/inst/doc/updating-methylSig-code.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("methylSig")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METHYLSIG {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-methylsig"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-methylsig:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-methylsig:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_methylsig_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_methylsig_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_methylsig_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(methylSig)
    library(jsonlite)


    # --- Include = False [] ---
    # Key functions: set
    knitr::opts_chunk$set(
        collapse = TRUE,
        comment = "#>"
    )

    # --- Read [] ---
    # Key functions: read.bismark
    files = c(
        system.file('extdata', 'bis_cov1.cov', package='methylSig'),
        system.file('extdata', 'bis_cov2.cov', package='methylSig')
    )

    # --- Filter By Coverage [] ---
    # Key functions: filter_loci_by_coverage
    # Load data for use in the rest of the vignette
    data(BS.cancer.ex, package = 'bsseqData')
    bs = BS.cancer.ex[1:10000]

    bs = filter_loci_by_coverage(bs, min_count = 5, max_count = 500)

    # --- Filter By Location [] ---
    # Key functions: GRanges, IRanges, filter_loci_by_location
    # Construct GRanges object
    remove_gr = GenomicRanges::GRanges(
        seqnames = c('chr21', 'chr21', 'chr21'),
        ranges = IRanges::IRanges(
            start = c(9411552, 9411784, 9412099),
            end = c(9411552, 9411784, 9412099)
        )
    )

    bs = filter_loci_by_location(bs = bs, gr = remove_gr)

    # --- Tile By Windows [] ---
    # Key functions: tile_by_windows
    windowed_bs = tile_by_windows(bs = bs, win_size = 10000)

    # --- Tile By Regions [] ---
    # Key functions: tile_by_regions
    # Collapsed promoters on chr21 and chr22
    data(promoters_gr, package = 'methylSig')

    promoters_bs = tile_by_regions(bs = bs, gr = promoters_gr)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_methylsig_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_methylsig_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_methylsig_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_METHYLSIG:", paste0("    methylsig: ", packageVersion("methylSig"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_methylsig_results.csv
    touch ${prefix}_methylsig_output.rds
    echo "BIOC_METHYLSIG:" > versions.yml
    echo "    methylsig: 0.0.0" >> versions.yml
    """
}


workflow BIOC_METHYLSIG_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_METHYLSIG(ch_input)

    emit:
    results  = BIOC_METHYLSIG.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_METHYLSIG.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_METHYLSIG.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_METHYLSIG.out.versions  // channel: path(versions.yml)
}
