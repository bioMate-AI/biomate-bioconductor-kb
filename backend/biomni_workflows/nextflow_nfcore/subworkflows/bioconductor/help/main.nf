#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: HELP
// The package contains a modular pipeline for analysis of HELP microarray data, and includes graphical
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/HELP/inst/doc/HELP.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("HELP")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HELP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-help"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-help:1.64.0--r44_0' :
        'quay.io/biocontainers/bioconductor-help:1.64.0--r44_0'}"

    input:
    tuple val(meta), path(plot_object)

    output:
    tuple val(meta), path("${meta.id}_help_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_help_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_help_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(HELP)
    library(Density)
    library(SAMPLEs)
    library(jsonlite)

    # --- Spatial Quality Control [plotChip] ---
    # Key functions: plotChip
    # Visualizing spatial intensity to detect chip manufacturing or hybridization artifacts
    # Using simulated coordinates to demonstrate spatial plotting
    x_coords <- rep(1:100, 100)
    y_coords <- rep(1:100, each = 100)
    z_values <- x_coords * (1001:11000 / 1000)
    plotChip(
        x_coords,
        y_coords,
        z_values,
        main = "Curved gradient",
        xlab = "x",
        ylab = "y"
    )

    # --- Feature-Level Signal Distribution [plotFeature] ---
    # Key functions: plotFeature
    # Plotting feature-level signal distribution for a specific sample
    # 'pairs' is a pre-loaded data object containing sample measurements
    plotFeature(
        pairs[, "Brain2"],
        cex = 0.5
    )

    # --- Quantile Normalization [quantileNormalize] ---
    # Key functions: quantileNormalize
    # Performing quantile normalization to correct for spatial bias
    # x represents signal intensities, y represents spatial bins
    x_signal <- rep(1:100, 100)
    y_bins <- rep(1:100, each = 100)
    norm_signal <- quantileNormalize(
        x_signal,
        y_bins,
        num.bins = 20,
        num.steps = 1,
        mode = "discrete"
    )

    # --- Pairwise Sample Comparison [plotPairs] ---
    # Key functions: plotPairs
    # Generating pairwise scatter plots to compare samples
    # 'pairs' is a multi-sample data object
    plotPairs(
        pairs,
        element = "exprs2"
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_help_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_help_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_help_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HELP:", paste0("    help: ", packageVersion("HELP"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_help_results.csv
    touch ${prefix}_help_output.rds
    echo "BIOC_HELP:" > versions.yml
    echo "    help: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HELP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(plot_object) ]

    main:
    BIOC_HELP(ch_input)

    emit:
    results  = BIOC_HELP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HELP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HELP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HELP.out.versions  // channel: path(versions.yml)
}
