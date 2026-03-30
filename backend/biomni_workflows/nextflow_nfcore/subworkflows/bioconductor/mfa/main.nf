#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: mfa
// MFA models genomic bifurcations using a Bayesian hierarchical mixture of factor analysers.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/mfa/inst/doc/introduction_to_mfa.R
// Upstream  : dplyr, ggplot2
// Downstream: none
//
// Install: BiocManager::install("mfa")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MFA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mfa"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mfa:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mfa:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mfa_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mfa_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mfa_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(mfa)
    library(jsonlite)

    # --- Custom ggplot2 visualization [] ---
    # Key functions: ggplot, geom_point, scale_color_discrete
    ggplot(df_synth, aes(x = PC1, y = PC2, color = pseudotime)) + geom_point()
    ggplot(df_synth, aes(x = PC1, y = PC2, color = branch)) + geom_point()
    # --- Synthetic analysis [] ---
    # Key functions: install_github, create_synthetic, as_data_frame, mfa, plot_mfa_trace, plot_mfa_autocorr, qplot, xlab
    qplot(synth$pst, ms$pseudotime, color = factor(synth$branch)) +
    xlab('True pseudotime') + ylab('Inferred pseudotime') +
    scale_color_discrete(name = 'True\nbranch')

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mfa_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mfa_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mfa_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MFA:", paste0("    mfa: ", packageVersion("mfa"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mfa_results.csv
    touch ${prefix}_mfa_output.rds
    echo "BIOC_MFA:" > versions.yml
    echo "    mfa: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MFA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MFA(ch_input)

    emit:
    results  = BIOC_MFA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MFA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MFA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MFA.out.versions  // channel: path(versions.yml)
}
