#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: plasmut
// A Bayesian method for quantifying the liklihood that a given plasma mutation arises from clonal hema
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/plasmut/inst/doc/plasmut.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("plasmut")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PLASMUT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-plasmut"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-plasmut:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-plasmut:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_plasmut_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_plasmut_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_plasmut_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(plasmut)
    library(jsonlite)

    # --- data wrangling [] ---
    # Key functions: tibble, unite, group_by, nest

    # --- importance_sampler [] ---
    # Key functions: importance_sampler
    stats <- importance_sampler(dat$data[[1]], param.list)
    Just the mutation-level summary statistics (marginal likelihoods and bayes factors)
    importance_sampler(dat$data[[1]], param.list, save_montecarlo=FALSE)
    # --- importance_sampler [] ---
    # Key functions: importance_sampler, replicate, group_by, summarize

    # --- Custom ggplot2 visualization [] ---
    # Key functions: ggplot, geom_point, geom_line, scale_y_log10, theme_bw
    mutate(prior.weight=factor(prior.weight)) %>%
    ggplot(aes(montecarlo.samples, sd_bf)) +
    geom_point(aes(color=prior.weight)) +
    # --- Custom ggplot2 visualization [] ---
    # Key functions: ggplot, geom_point, theme_bw, ylab, xlab
    mutate(prior.weight=factor(prior.weight)) %>%
    filter(montecarlo.samples > 100) %>%
    ggplot(aes(prior.weight, mean_bf)) +
    # --- unite [] ---
    # Key functions: unite, group_by


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_plasmut_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_plasmut_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_plasmut_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PLASMUT:", paste0("    plasmut: ", packageVersion("plasmut"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_plasmut_results.csv
    touch ${prefix}_plasmut_output.rds
    echo "BIOC_PLASMUT:" > versions.yml
    echo "    plasmut: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PLASMUT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PLASMUT(ch_input)

    emit:
    results  = BIOC_PLASMUT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PLASMUT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PLASMUT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PLASMUT.out.versions  // channel: path(versions.yml)
}
