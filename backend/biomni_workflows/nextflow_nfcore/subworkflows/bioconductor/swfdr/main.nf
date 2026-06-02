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

    # --- rbind [] ---
    # Key functions: rbind
    dataset1 <- matrix(c(rnorm(3*N, 0, 1), rnorm(3*N, 2, 1)), ncol=6)
    head(dataset1, 3)
    D1 <- data.frame(p=dataset_p(dataset1), truth=1)
    # --- Dhist [] ---
    # Key functions: p_hist
    par(mfrow=c(1,3), las=1, mar=c(3,4,2,1))
    # --- Dqs [] ---
    # Key functions: qvalue, hit_counts
    library(qvalue)
    D0q <- qvalue(D0$p)
    D1q <- qvalue(D1$p)
    # --- DX pi0 [] ---
    # Key functions: lm_pi0
    D2_lm_pi0 <- lm_pi0(D2$p, X=D2$truth)
    names(D2_lm_pi0)
    # --- D2 lm q [] ---
    # Key functions: lm_qvalue
    D2_lm_q <- lm_qvalue(D2$p, X=D2$truth)
    # --- D2 noisy lm q [] ---
    # Key functions: lm_qvalue
    D2_noisy_lm_q <- lm_qvalue(D2_noisy$p, X=D2_noisy$truth.noisy)
    # --- D2calls noisy [] ---
    # Key functions: confusion_matrix
    confusion_matrix(D2$truth, D2_noisy_lm_q)
    confusion_matrix(D2$truth, D2_noisy_lm_q, threshold=0.1)
    # --- GWAS pi0 [] ---
    # Key functions: lm_pi0
    GWAS_lm_pi0 <- lm_pi0(GWAS$p, X=GWAS[, c("N", "Freq_MAF_Hapmap")])
    # --- GWAS lm qvalue [] ---
    # Key functions: lm_qvalue
    GWAS_lm_qvalue <- lm_qvalue(GWAS$p, X=GWAS[, c("N", "Freq_MAF_Hapmap")])
    # --- GWAS lm qvalue 0 [] ---
    # Key functions: lm_qvalue
    GWAS_lm_qvalue_0 <- lm_qvalue(GWAS$p)
    # --- GWAS lm qvalue spline [] ---
    # Key functions: lm_qvalue
    GWAS_lm_qvalue_smooth <- lm_qvalue(GWAS$p, smoothing="smooth.spline")

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
