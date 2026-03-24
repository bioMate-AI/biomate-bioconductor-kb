#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Sconify
// This package does k-nearest neighbor based statistics and visualizations with flow and mass cytomete
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Sconify/inst/doc/DataQuality.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("Sconify")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCONIFY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sconify"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-sconify:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-sconify:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_sconify_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sconify_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sconify_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(IgM)
    library(MakeHist)
    library(TsneVis)
    library(jsonlite)

    # --- Makehist [] ---
    # Key functions: MakeHist
    ---------------------------------------------------------------------
    # Visualization
    MakeHist(wand.final, 30, "IL7.fraction.cond.2", "fraction IL7")
    # Characteristics of the visualization
    median(wand.final$IL7.fraction.cond.2)
    # --- Function [] ---
    # Key functions: sample, frame
    ---------------------------------------------------------------------
    # Compare to a coin toss distribution
    # Flips a coin k number of times, n repetitions, and returns the vector
    # containing the per-k percent heads
    KFlip <- function(k, n) {
    # --- Tsnevis [] ---
    # Key functions: TsneVis, IgM
    ---------------------------------------------------------------------
    # Raw per-cell IgM levels
    TsneVis(wand.final, "IgM(Eu153)Di", "Raw IgM expression")
    TsneVis(wand.final, "IL7.fraction.cond.2", "Fraction cells in Il7 condition")
    # --- Makehist [] ---
    # Key functions: MakeHist
    ---------------------------------------------------------------------
    # Before normalization
    MakeHist(bz.gmcsf.final, 100, "fraction.cond2", "fraction GM-CSF")
    # Characteristics of the visualization
    median(bz.gmcsf.final$fraction.cond2)
    # --- Tsnevis [] ---
    # Key functions: TsneVis
    ---------------------------------------------------------------------
    # t-SNE map colored by KNN-based fraction GM-CSF
    TsneVis(bz.gmcsf.final, "fraction.cond2", "Fraction GM-CSF")
    # t-SNE map colored by KNN-based fraction GM-CSF
    TsneVis(bz.gmcsf.final.norm.scale, "fraction.cond2", "Fraction GM-CSF")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_sconify_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_sconify_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_sconify_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCONIFY:", paste0("    sconify: ", packageVersion("Sconify"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sconify_results.csv
    touch ${prefix}_sconify_output.rds
    echo "BIOC_SCONIFY:" > versions.yml
    echo "    sconify: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCONIFY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SCONIFY(ch_input)

    emit:
    results  = BIOC_SCONIFY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCONIFY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCONIFY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCONIFY.out.versions  // channel: path(versions.yml)
}
