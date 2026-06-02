#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: NPARC
// Perform non-parametric analysis of response curves as described by Childs, Bach, Franken et al. (201
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/NPARC/inst/doc/NPARC.R
// Upstream  : broom, dplyr, ggplot2, knitr, magrittr
// Downstream: none
//
// Install: BiocManager::install("NPARC")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NPARC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-nparc"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-nparc:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-nparc:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_nparc_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_nparc_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_nparc_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(NPARC)
    library(NPARCfit)
    library(NPARCtest)
    library(SerialParam)
    library(jsonlite)

    # --- Non-parametric Curve Fitting [] ---
    # Key functions: NPARCfit
    BPPARAM <- BiocParallel::SerialParam(progressbar = FALSE)
    fits <- NPARCfit(
        x = df$temperature,
        y = df$relAbundance,
        id = df$uniqueID,
        groupsNull = NULL,
        groupsAlt = df$compoundConcentration,
        BPPARAM = BPPARAM,
        returnModels = FALSE
    )
    metrics <- fits$metrics
    predictions <- fits$predictions


    # --- Statistical Significance Testing [] ---
    # Key functions: NPARCtest
    fStats_theo <- NPARCtest(metrics, dfType = "theoretical")
    fStats_emp <- NPARCtest(metrics, dfType = "empirical")
    significant_proteins <- fStats_emp %>%
        dplyr::filter(!is.na(pAdj)) %>%
        dplyr::filter(pAdj < 0.05) %>%
        dplyr::arrange(pAdj)


    # --- Visualisation of Response Curves [] ---
    # Key functions: NPARCfit
    stk4_predictions <- dplyr::filter(
        predictions,
        id == "STK4_IPI00011488"
    )
    stk4_plot <- ggplot2::ggplot(stk4_predictions) +
        ggplot2::geom_line(
            ggplot2::aes(x = x, y = .fitted, color = factor(group))
        ) +
        ggplot2::theme_bw() +
        ggplot2::labs(
            title = "STK4 Response Curves",
            x = "Temperature",
            y = "Relative Abundance"
        )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_nparc_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_nparc_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_nparc_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_NPARC:", paste0("    nparc: ", packageVersion("NPARC"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_nparc_results.csv
    touch ${prefix}_nparc_output.rds
    echo "BIOC_NPARC:" > versions.yml
    echo "    nparc: 0.0.0" >> versions.yml
    """
}


workflow BIOC_NPARC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_NPARC(ch_input)

    emit:
    results  = BIOC_NPARC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_NPARC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_NPARC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_NPARC.out.versions  // channel: path(versions.yml)
}
