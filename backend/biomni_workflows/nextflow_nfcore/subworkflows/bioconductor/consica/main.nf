#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: consICA
// consICA implements a data-driven deconvolution method – consensus independent component analysis (IC
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/consICA/inst/doc/ConsICA.R
// Upstream  : SummarizedExperiment
// Downstream: none
//
// Install: BiocManager::install("consICA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CONSICA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-consica"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-consica:2.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-consica:2.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_consica_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_consica_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_consica_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(consICA)
    library(jsonlite)

    # --- Getfeatures [] ---
    # Key functions: getFeatures
    ---------------------------------------------------------------------
    features <- getFeatures(cica, alpha = 0.05, sort = TRUE)
    #Positive and negative affecting features for first components are
    head(features$ic.1$pos)
    head(features$ic.1$neg)
    # --- Estimatevarianceexplained [] ---
    # Key functions: estimateVarianceExplained, plotICVarianceExplained
    ---------------------------------------------------------------------
    var_ic <- estimateVarianceExplained(cica)
    p <- plotICVarianceExplained(cica)
    # --- Frame [] ---
    # Key functions: frame, colData, anovaIC
    ---------------------------------------------------------------------
    ## Run ANOVA for components 1 and 5
    # Get metadata from SummarizedExperiment object
    # Var <- data.frame(SummarizedExperiment::colData(samples_data))
    var_ic1 <- anovaIC(cica, Var, icomp = 1, color_by_pv = TRUE, plot = TRUE)
    # --- Survivalanalysis [] ---
    # Key functions: survivalAnalysis
    ---------------------------------------------------------------------
    RS <- survivalAnalysis(cica, surv = Sur)
    cat("Hazard score for significant components")
    RS$hazard.score
    # --- Unlink [] ---
    # Key functions: unlink
    ---------------------------------------------------------------------
    # delete loaded file after vignette run
    unlink("cica_GOs_20_s2022.rds")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_consica_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_consica_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_consica_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CONSICA:", paste0("    consica: ", packageVersion("consICA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_consica_results.csv
    touch ${prefix}_consica_output.rds
    echo "BIOC_CONSICA:" > versions.yml
    echo "    consica: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CONSICA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CONSICA(ch_input)

    emit:
    results  = BIOC_CONSICA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CONSICA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CONSICA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CONSICA.out.versions  // channel: path(versions.yml)
}
