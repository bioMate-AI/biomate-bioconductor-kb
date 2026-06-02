#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: similaRpeak
// This package calculates metrics which quantify the level of similarity between ChIP-Seq profiles. Mo
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/similaRpeak/inst/doc/similaRpeak.R
// Upstream  : GenomicAlignments, Rsamtools, knitr, rtracklayer
// Downstream: none
//
// Install: BiocManager::install("similaRpeak")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SIMILARPEAK {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-similarpeak"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-similarpeak:1.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-similarpeak:1.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_similarpeak_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_similarpeak_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_similarpeak_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(similaRpeak)
    library(GRanges)
    library(ScanBamParam)
    library(jsonlite)

    # --- Profile Loading [] ---
    # Key functions: demoProfiles
    data("demoProfiles", package = "similaRpeak")
    profile1 <- demoProfiles$chr2.70360770.70361098$H3K27ac
    profile2 <- demoProfiles$chr2.70360770.70361098$H3K4me1


    # --- Similarity Metric Calculation [] ---
    # Key functions: similarity
    metrics <- similaRpeak::similarity(
        profile1,
        profile2
    )
    ratio_area <- metrics$metric$RATIO_AREA
    diff_pos_max <- metrics$metric$DIFF_POS_MAX

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_similarpeak_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_similarpeak_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_similarpeak_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SIMILARPEAK:", paste0("    similarpeak: ", packageVersion("similaRpeak"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_similarpeak_results.csv
    touch ${prefix}_similarpeak_output.rds
    echo "BIOC_SIMILARPEAK:" > versions.yml
    echo "    similarpeak: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SIMILARPEAK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SIMILARPEAK(ch_input)

    emit:
    results  = BIOC_SIMILARPEAK.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SIMILARPEAK.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SIMILARPEAK.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SIMILARPEAK.out.versions  // channel: path(versions.yml)
}
