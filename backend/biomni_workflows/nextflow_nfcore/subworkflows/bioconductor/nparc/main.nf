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
    library(NPARCfit)
    library(NPARCtest)
    library(SerialParam)
    library(jsonlite)

    # --- count curves per protein [] ---
    # Key functions: group_by
    group_by(dataset, uniqueID) %>%
    mutate(n = n()) %>%
    group_by(dataset) %>%
    # --- plot stk4 [] ---
    # Key functions: ggplot, geom_point, theme_bw, ggtitle, scale_color_manual
    stk4_plot_orig <- ggplot(stk4, aes(x = temperature, y = relAbundance)) +
    geom_point(aes(shape = factor(replicate), color = factor(compoundConcentration)), size = 2) +
    theme_bw() +
    # --- augment null stk4 [] ---
    # Key functions: augment
    nullPredictions <- broom::augment(nullFit)
    # --- fit alternative stk4 [] ---
    # Key functions: group_by, augment, rename
    group_by(compoundConcentration) %>%
    do({
    fit = NPARC:::fitSingleSigmoid(x = .$temperature, y = .$relAbundance, start=c(Pl = 0, a = 550, b = 10))
    # --- add alternative resids stk4 [] ---
    # Key functions: left_join, distinct
    left_join(alternativePredictions,
    by = c("relAbundance", "temperature",
    distinct()
    # --- plot Fig 2 A B [] ---
    # Key functions: geom_line, aes
    geom_line(data = distinct(stk4, temperature, compoundConcentration, alternativePrediction),
    aes(y = alternativePrediction, color = factor(compoundConcentration)))
    print(stk4_plot)
    # --- compute rss stk4 [] ---
    # Key functions: summarise, SerialParam
    summarise(rssNull = sum(nullResiduals^2),
    rssAlternative = sum(alternativeResiduals^2))
    kable(rssPerModel, digits = 4)
    # --- fit all proteins [] ---
    # Key functions: NPARCfit
    fits <- NPARCfit(x = df$temperature,
    str(fits, 1)
    # --- plot stk4 results [] ---
    # Key functions: geom_line, aes
    stk4Predictions <- filter(fits$predictions, modelType == "alternative", id == "STK4_IPI00011488")
    geom_line(data = filter(stk4Predictions, modelType == "alternative"),
    aes(x = x, y = .fitted, color = factor(group))) +
    # --- N P A R Ctest [] ---
    # Key functions: NPARCtest
    fStats <- NPARCtest(modelMetrics, dfType = "theoretical")
    # --- plotF DOFiid [] ---
    # Key functions: distinct
    filter(!is.na(pAdj)) %>%
    distinct(nFittedNull, nFittedAlt, nCoeffsNull, nCoeffsAlt, df1, df2) %>%
    kable()
    # --- Custom ggplot2 visualization [] ---
    # Key functions: ggplot, geom_density, geom_line, theme_bw, xlim
    ggplot(filter(fStats, !is.na(pAdj))) +
    geom_density(aes(x = fStat), fill = "steelblue", alpha = 0.5) +
    geom_line(aes(x = fStat, y = df(fStat, df1 = df1, df2 = df2)), color = "darkred", size = 1.5) +
    # --- Custom ggplot2 visualization [] ---
    # Key functions: ggplot, geom_histogram, geom_line, theme_bw
    ggplot(filter(fStats, !is.na(pAdj))) +
    geom_histogram(aes(x = pVal, y = ..density..), fill = "steelblue", alpha = 0.5, boundary = 0, bins = 30) +
    geom_line(aes(x = pVal, y = dunif(pVal)), color = "darkred", size = 1.5) +
    # --- N P A R Ctest [] ---
    # Key functions: NPARCtest
    fStats <- NPARCtest(modelMetrics, dfType = "empirical")
    # --- Custom ggplot2 visualization [] ---
    # Key functions: ggplot, geom_density, geom_line, theme_bw, xlim
    ggplot(filter(fStats, !is.na(pAdj))) +
    geom_density(aes(x = fStat), fill = "steelblue", alpha = 0.5) +
    geom_line(aes(x = fStat, y = df(fStat, df1 = df1, df2 = df2)), color = "darkred", size = 1.5) +

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
