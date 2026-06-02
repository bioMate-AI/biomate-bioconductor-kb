#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: weitrix
// Data type and tools for working with matrices having precision weights and missing data. This packag
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/weitrix/inst/doc/V2_tail_length.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("weitrix")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_WEITRIX {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-weitrix"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-weitrix:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-weitrix:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(marraylm)

    output:
    tuple val(meta), path("${meta.id}_weitrix_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_weitrix_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_weitrix_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(weitrix)
    library(jsonlite)

    # --- Calibration and Weight Adjustment [] ---
    # Key functions: weitrix_components, weitrix_calibrate_all, well_knotted_spline
    design <- model.matrix(~ 1, data = colData(wei))
    fit <- weitrix_components(wei, design = design)
    cal <- weitrix_calibrate_all(
        wei,
        design = fit,
        trend_formula = ~ well_knotted_spline(mu, 3)
    )


    # --- Differential Expression Analysis [] ---
    # Key functions: weitrix_confects, weitrix_elist
    design_de <- model.matrix(~ factor(rep(c("A", "B"), each = 5)))
    colnames(design_de) <- c("Intercept", "GroupB")
    confects <- weitrix_confects(
        cal,
        design_de,
        coef = "GroupB",
        fdr = 0.05
    )
    elist <- weitrix_elist(cal)


    # --- Component Analysis and Visualization [] ---
    # Key functions: weitrix_components_seq, components_seq_screeplot, matrix_long
    comp_seq <- weitrix_components_seq(cal, p = 2)
    scree_p <- components_seq_screeplot(comp_seq)
    comp <- comp_seq[[1]]
    long_df <- matrix_long(
        comp$col,
        varnames = c("sample", "component")
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_weitrix_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_weitrix_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_weitrix_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_WEITRIX:", paste0("    weitrix: ", packageVersion("weitrix"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_weitrix_results.csv
    touch ${prefix}_weitrix_output.rds
    echo "BIOC_WEITRIX:" > versions.yml
    echo "    weitrix: 0.0.0" >> versions.yml
    """
}


workflow BIOC_WEITRIX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(marraylm) ]

    main:
    BIOC_WEITRIX(ch_input)

    emit:
    results  = BIOC_WEITRIX.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_WEITRIX.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_WEITRIX.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_WEITRIX.out.versions  // channel: path(versions.yml)
}
