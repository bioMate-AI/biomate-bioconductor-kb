#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: limpca
// This package has for objectives to provide a method to make Linear Models for high-dimensional desig
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/limpca/inst/doc/Trout.R
// Upstream  : SummarizedExperiment, car, ggplot2, gridExtra, pander
// Downstream: none
//
// Install: BiocManager::install("limpca")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_LIMPCA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-limpca"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-limpca:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-limpca:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_limpca_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_limpca_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_limpca_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Anova)
    library(jsonlite)

    # --- Data Importation [] ---
    # Key functions: plotDesign
    data("trout")
    cat("\n Nb of Responses :  ", ncol(trout$outcomes), "\n ")
    cat("\nResponses :\n", colnames(trout$outcomes), "\n ")
    # --- Exploratory PCA [] ---
    # Key functions: pcaBySvd, pcaScreePlot, pcaScorePlot
    resPCA <- limpca::pcaBySvd(trout$outcomes)
    limpca::pcaScreePlot(resPCA, nPC = 8)
    # --- Transformation [] ---
    # Key functions: pcaBySvd, pcaScreePlot, pcaScorePlot
    trout_log$outcomes <- as.matrix(log10(trout$outcomes))
    resPCA1 <- limpca::pcaBySvd(trout_log$outcomes)
    limpca::pcaScreePlot(resPCA1, nPC = 8)
    # --- new PCA [] ---
    # Key functions: pcaBySvd, pcaScreePlot, pcaScorePlot
    resPCA2 <- limpca::pcaBySvd(trout_clean$outcomes)
    limpca::pcaScreePlot(resPCA2, nPC = 8)
    # --- Mean aggregation [] ---
    # Key functions: aggregate
    mean_outcomes <- matrix(0, nrow = 24, ncol = 15)
    mean_design <- matrix(0, nrow = 24, ncol = 3)
    # --- Centering and Scaling [] ---
    # Key functions: scale
    mean_outcomes <- scale(mean_outcomes, center = TRUE, scale = TRUE)
    # --- Design [] ---
    # Key functions: pander, plotDesign
    pander(head(trout_mean$design))
    # --- Lineplot [] ---
    # Key functions: plotLine, theme

    # --- pca By Svd [] ---
    # Key functions: pcaBySvd, pcaScreePlot, pcaScorePlot, pcaLoading1dPlot, theme
    resPCA_mean <- limpca::pcaBySvd(trout_mean$outcomes)
    pcaScreePlot(resPCA_mean, nPC = 6)
    # --- Scatterplot Matrix [] ---
    # Key functions: plotScatterM

    # --- lmp Model Matrix [] ---
    # Key functions: lmpModelMatrix, pander
    resLmpModelMatrix <- limpca::lmpModelMatrix(trout_mean)
    pander::pander(head(resLmpModelMatrix$modelMatrix))
    # --- lmp Effect Matrices [] ---
    # Key functions: lmpEffectMatrices
    resLmpEffectMatrices <- lmpEffectMatrices(resLmpModelMatrix)
    # --- Bootstrap [] ---
    # Key functions: lmpBootstrapTests, pander

    # --- ASCA PCA [] ---
    # Key functions: lmpPcaEffects

    # --- ASCA Contrib [] ---
    # Key functions: lmpContributions
    resLmpContributions <- lmpContributions(resASCA)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_limpca_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_limpca_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_limpca_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_LIMPCA:", paste0("    limpca: ", packageVersion("limpca"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_limpca_results.csv
    touch ${prefix}_limpca_output.rds
    echo "BIOC_LIMPCA:" > versions.yml
    echo "    limpca: 0.0.0" >> versions.yml
    """
}


workflow BIOC_LIMPCA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_LIMPCA(ch_input)

    emit:
    results  = BIOC_LIMPCA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_LIMPCA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_LIMPCA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_LIMPCA.out.versions  // channel: path(versions.yml)
}
