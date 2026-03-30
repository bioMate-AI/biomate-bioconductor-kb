#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MOFA2
// The MOFA2 package contains a collection of tools for training and analysing multi-omic factor analys
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MOFA2/inst/doc/MEFISTO_temporal.R
// Upstream  : ggplot2, pheatmap, tidyverse
// Downstream: none
//
// Install: BiocManager::install("MOFA2")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MOFA2 {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mofa2"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mofa2:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mofa2:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mofa2_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mofa2_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mofa2_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MOFA2)
    library(jsonlite)

    # --- Frame [] ---
    # Key functions: frame, gather, starts_with, ggplot, aes, geom_point, facet_grid
    ---------------------------------------------------------------------
    df <- data.frame(dd$Z, t(time))
    df <- gather(df, key = "factor", value = "value", starts_with("simulated_factor"))
    ggplot(df, aes(x = time, y = value)) + geom_point() + facet_grid(~factor)
    # --- Create Mofa [] ---
    # Key functions: create_mofa
    ---------------------------------------------------------------------
    sm <- create_mofa(data = dd$data)
    # --- Get Scales [] ---
    # Key functions: get_scales
    ---------------------------------------------------------------------
    get_scales(sm)
    # --- Plot Factors Vs Cov [] ---
    # Key functions: plot_factors_vs_cov
    ---------------------------------------------------------------------
    plot_factors_vs_cov(sm, color_by = "time")
    # --- Plot Data Vs Cov [] ---
    # Key functions: plot_data_vs_cov
    ---------------------------------------------------------------------
    plot_data_vs_cov(sm, factor=3,
                             features = 2,
                             color_by = "time",
                             dot_size = 1)
    # --- Interpolate Factors [] ---
    # Key functions: interpolate_factors, plot_interpolation_vs_covariate
    ---------------------------------------------------------------------
    sm <- interpolate_factors(sm, new_values = seq(0,1.1,0.01))
    plot_interpolation_vs_covariate(sm, covariate = "time",
                                    factors = "Factor3")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mofa2_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mofa2_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mofa2_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MOFA2:", paste0("    mofa2: ", packageVersion("MOFA2"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mofa2_results.csv
    touch ${prefix}_mofa2_output.rds
    echo "BIOC_MOFA2:" > versions.yml
    echo "    mofa2: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MOFA2_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MOFA2(ch_input)

    emit:
    results  = BIOC_MOFA2.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MOFA2.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MOFA2.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MOFA2.out.versions  // channel: path(versions.yml)
}
