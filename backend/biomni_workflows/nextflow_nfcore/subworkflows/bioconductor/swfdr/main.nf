#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: swfdr
// This package allows users to estimate the science-wise false discovery rate from Jager and Leek, "Em
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/swfdr/inst/doc/swfdrQ.R
// Upstream  : BiocManager, ggplot2, qvalue
// Downstream: none
//
// Install: BiocManager::install("swfdr")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SWFDR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-swfdr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-swfdr:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-swfdr:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_swfdr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_swfdr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_swfdr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(swfdr)
    library(jsonlite)

    # --- Pi0 Estimation with Study Covariates ---
    # Key functions: lm_pi0
    gwas_data <- swfdr::BMI_GIANT_GWAS_sample
    gwas_clean <- na.omit(gwas_data)
    pi0_fit <- lm_pi0(
        p = gwas_clean$p,
        X = gwas_clean[, c("N", "Freq_MAF_Hapmap")]
    )
    pi0_estimates <- pi0_fit$pi0

    # --- FDR Control and Q-value Calculation ---
    # Key functions: lm_qvalue
    gwas_data <- swfdr::BMI_GIANT_GWAS_sample
    gwas_clean <- na.omit(gwas_data)
    qval_fit <- lm_qvalue(
        p = gwas_clean$p,
        X = gwas_clean[, c("N", "Freq_MAF_Hapmap")]
    )
    q_values <- qval_fit$qvalues

    # --- Spline Smoothed FDR Estimation ---
    # Key functions: lm_qvalue
    gwas_data <- swfdr::BMI_GIANT_GWAS_sample
    gwas_clean <- na.omit(gwas_data)
    qval_smooth <- lm_qvalue(
        p = gwas_clean$p,
        X = gwas_clean[, c("N", "Freq_MAF_Hapmap")],
        smoothing = "smooth.spline"
    )
    pi0_smooth <- qval_smooth$pi0


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_swfdr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_swfdr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_swfdr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SWFDR:", paste0("    swfdr: ", packageVersion("swfdr"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_swfdr_results.csv
    touch ${prefix}_swfdr_output.rds
    echo "BIOC_SWFDR:" > versions.yml
    echo "    swfdr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SWFDR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SWFDR(ch_input)

    emit:
    results  = BIOC_SWFDR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SWFDR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SWFDR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SWFDR.out.versions  // channel: path(versions.yml)
}
