#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: nucleR
// Nucleosome positioning for Tiling Arrays and NGS experiments.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/nucleR/inst/doc/nucleR.R
// Upstream  : GenomicRanges, IRanges, ggplot2
// Downstream: none
//
// Install: BiocManager::install("nucleR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NUCLER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-nucler"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-nucler:2.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-nucler:2.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_nucler_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_nucler_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_nucler_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GRanges)
    library(jsonlite)

    # --- Compute genomic coverage [] ---
    # Key functions: syntheticNucMap, coverage, controlCorrection, ggplot, reduce, GRanges, plotPeaks
    red_calls <- reduce(nuc_calls)
    red_class <- GRanges(red_calls, isFuzzy=width(red_calls) > 140)
    plotPeaks(red_calls, htseq_fft, threshold="25%")
    # --- Custom ggplot2 visualization [] ---
    # Key functions: ggplot, geom_line, xlab, ylab, mkEntry, filterFFT, facet_grid
    tiling_fft <- filterFFT(tiling_raw, pcKeepComp=0.01)
    htseq_raw <- as.vector(cover_trim[[1]])[i]
    htseq_fft <- filterFFT(htseq_raw, pcKeepComp=0.02)
    # --- ProcessTilingArray analysis [] ---
    # Key functions: processTilingArray, readBAM, processReads, filterFFT, peakDetection, plotPeaks, syntheticNucMap
    reads_pair <- processReads(nucleosome_htseq, type="paired", fragmentLen=200)
    reads_trim <- processReads(nucleosome_htseq, type="paired", fragmentLen=200,

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_nucler_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_nucler_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_nucler_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_NUCLER:", paste0("    nucler: ", packageVersion("nucleR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_nucler_results.csv
    touch ${prefix}_nucler_output.rds
    echo "BIOC_NUCLER:" > versions.yml
    echo "    nucler: 0.0.0" >> versions.yml
    """
}


workflow BIOC_NUCLER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_NUCLER(ch_input)

    emit:
    results  = BIOC_NUCLER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_NUCLER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_NUCLER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_NUCLER.out.versions  // channel: path(versions.yml)
}
