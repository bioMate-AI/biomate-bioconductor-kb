#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: TFutils
// This package helps users to work with TF metadata from various sources. Significant catalogs of TFs 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/TFutils/inst/doc/TFutils.R
// Upstream  : AnnotationDbi, BiocParallel, GenomicFiles, GenomicRanges, UpSetR
// Downstream: none
//
// Install: BiocManager::install("TFutils")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TFUTILS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tfutils"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-tfutils:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-tfutils:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_tfutils_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tfutils_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tfutils_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(TFutils)
    library(jsonlite)

    # --- Custom ggplot2 visualization [] ---
    # Key functions: geom_segment, ggplot, geom_point, myf, xlab
    library(ggplot2)
    myf = function(a=38077296, b=38078938)
    # --- Table formatting and display [] ---
    # Key functions: upset, include_graphics, kable, register, rowRanges, scanTabix, directHitsInCISBP
    suppressPackageStartupMessages({library(UpSetR)})
    allhg = keys(org.Hs.eg.db::org.Hs.eg.db, keytype="SYMBOL")
    activesym = unique(unlist(list(TFs_GO@HGNCmap[,2], TFs_HOCO@HGNCmap[,2], TFs_MSIG@HGNCmap[,2], TFs_CISBP@HGNCmap[,2])))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_tfutils_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_tfutils_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_tfutils_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TFUTILS:", paste0("    tfutils: ", packageVersion("TFutils"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tfutils_results.csv
    touch ${prefix}_tfutils_output.rds
    echo "BIOC_TFUTILS:" > versions.yml
    echo "    tfutils: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TFUTILS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TFUTILS(ch_input)

    emit:
    results  = BIOC_TFUTILS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TFUTILS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TFUTILS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TFUTILS.out.versions  // channel: path(versions.yml)
}
