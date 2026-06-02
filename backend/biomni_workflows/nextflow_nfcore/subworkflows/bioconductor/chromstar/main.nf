#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: chromstaR
// This package implements functions for combinatorial and differential analysis of ChIP-seq data. It i
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/chromstaR/inst/doc/chromstaR.R
// Upstream  : biomaRt
// Downstream: none
//
// Install: BiocManager::install("chromstaR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CHROMSTAR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-chromstar"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-chromstar:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-chromstar:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_chromstar_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_chromstar_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_chromstar_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Chromstar)
    library(GRanges)
    library(jsonlite)

    # --- univariate narrow peak calling [] ---
    # Key functions: callPeaksUnivariate
    model <- callPeaksUnivariate(binned.data, verbosity=0)
    # --- univariate narrow plotting [] ---
    # Key functions: plotHistogram
    plotHistogram(model) + ggtitle('H3K4me3')
    # --- univariate narrow plotting2 [] ---
    # Key functions: plotGenomeBrowser
    plotGenomeBrowser(model, chr='chr12', start=1, end=1e6)[[1]]
    # --- univariate narrow posterior [] ---
    # Key functions: changeMaxPostCutoff
    length(model$peaks); mean(width(model$peaks))
    model <- changeMaxPostCutoff(model, maxPost.cutoff=0.9999)
    length(model$peaks); mean(width(model$peaks))
    # --- univariate narrow export [] ---
    # Key functions: exportPeaks, exportCounts
    exportPeaks(model, filename=tempfile())
    exportCounts(model, filename=tempfile())
    # --- univariate broad peak calling [] ---
    # Key functions: callPeaksUnivariate
    model <- callPeaksUnivariate(binned.data, verbosity=0)
    # --- univariate broad plotting [] ---
    # Key functions: plotHistogram
    plotHistogram(model) + ggtitle('H3K27me3')
    # --- univariate broad plotting2 [] ---
    # Key functions: plotGenomeBrowser
    plotGenomeBrowser(model, chr='chr12', start=1, end=1e6)[[1]]
    # --- univariate broad posterior [] ---
    # Key functions: changeMaxPostCutoff
    length(peaks); mean(width(peaks))
    model <- changeMaxPostCutoff(model, maxPost.cutoff=0.9999)
    length(peaks); mean(width(peaks))
    # --- univariate broad export [] ---
    # Key functions: exportPeaks, exportCounts
    exportPeaks(model, filename=tempfile())
    exportCounts(model, filename=tempfile())
    # --- univariate broad H4K20me1 [] ---
    # Key functions: callPeaksUnivariate, plotHistogram
    file <- system.file("extdata","euratrans","lv-H4K20me1-BN-male-bio1-tech1.bam",
    data(rn4_chrominfo)
    binned.data <- binReads(file, assembly=rn4_chrominfo, binsizes=1000,
    # --- univariate braod H4K20me1.2 [] ---
    # Key functions: plotGenomeBrowser
    plotGenomeBrowser(model, chr='chr12', start=1, end=1e6)[[1]]
    # --- multivariate replicate preparation [] ---
    # Key functions: Chromstar
    Let's get some example data with 3 replicates in spontaneous hypertensive rat (SHR)
    file.path <- system.file("extdata","euratrans", package='chromstaRData')
    files.good <- list.files(file.path, pattern="H3K27me3.*SHR.*bam$", full.names=TRUE)[1:3]
    # --- multivariate replicate univariate [] ---
    # Key functions: plotHistogram
    models <- list()
    for (i1 in 1:length(binned.data)) {
    models[[i1]] <- callPeaksUnivariate(binned.data[[i1]], max.time=60)
    # --- multivariate replicate export [] ---
    # Key functions: exportPeaks, exportCounts
    exportPeaks(multi.model, filename=tempfile())
    exportCounts(multi.model, filename=tempfile())

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_chromstar_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_chromstar_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_chromstar_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CHROMSTAR:", paste0("    chromstar: ", packageVersion("chromstaR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chromstar_results.csv
    touch ${prefix}_chromstar_output.rds
    echo "BIOC_CHROMSTAR:" > versions.yml
    echo "    chromstar: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CHROMSTAR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CHROMSTAR(ch_input)

    emit:
    results  = BIOC_CHROMSTAR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CHROMSTAR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CHROMSTAR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CHROMSTAR.out.versions  // channel: path(versions.yml)
}
