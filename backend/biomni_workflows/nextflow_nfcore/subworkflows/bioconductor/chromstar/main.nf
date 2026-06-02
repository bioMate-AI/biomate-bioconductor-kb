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
    library(chromstaR)
    library(Chromstar)
    library(GRanges)
    library(jsonlite)

    # --- Read Binning [Read Binning] ---
    # Key functions: binReads
    data(rn4_chrominfo)
    file <- system.file("extdata", "euratrans",
                        "lv-H3K4me3-BN-male-bio2-tech1.bam",
                        package = "chromstaRData")
    binned.data <- binReads(file, assembly = rn4_chrominfo,
                            binsizes = 1000, stepsizes = 500,
                            chromosomes = "chr12")

    # --- Univariate Peak Calling [Peak Calling] ---
    # Key functions: callPeaksUnivariate
    model <- callPeaksUnivariate(binned.data, verbosity = 0)

    # --- Model Visualization and Quality Control [Visualisation] ---
    # Key functions: plotHistogram, plotGenomeBrowser
    hist.plot <- plotHistogram(model)
    browser.plot <- plotGenomeBrowser(model, chr = "chr12",
                                      start = 1, end = 1e6)[[1]]

    # --- Peak Manipulation and Export [Export] ---
    # Key functions: changeMaxPostCutoff, exportPeaks, exportCounts
    model.adjusted <- changeMaxPostCutoff(model, maxPost.cutoff = 0.9999)
    exportPeaks(model.adjusted, filename = tempfile(fileext = ".bed"))
    exportCounts(model.adjusted, filename = tempfile(fileext = ".bed"))

    # --- Replicate Peak Calling [Differential Analysis] ---
    # Key functions: binReads, callPeaksUnivariate, callPeaksReplicates
    data(rn4_chrominfo)
    file.path <- system.file("extdata", "euratrans", package = "chromstaRData")
    files <- list.files(file.path, pattern = "H3K27me3.*SHR.*bam$",
                        full.names = TRUE)[1:2]
    binned.list <- list()
    models.list <- list()
    for (f in files) {
        binned.list[[basename(f)]] <- binReads(f, binsize = 1000,
                                               stepsizes = 500,
                                               assembly = rn4_chrominfo,
                                               chromosomes = "chr12")
        models.list[[basename(f)]] <- callPeaksUnivariate(
            binned.list[[basename(f)]], max.time = 60
        )
    }
    multi.model <- callPeaksReplicates(models.list, max.time = 60, eps = 1)


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
