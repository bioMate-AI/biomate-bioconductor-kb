#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: IgGeneUsage
// Detection of biases in the usage of immunoglobulin (Ig) genes is an important task in immune reperto
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/IgGeneUsage/inst/doc/User_Manual.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("IgGeneUsage")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_IGGENEUSAGE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-iggeneusage"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-iggeneusage:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-iggeneusage:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_iggeneusage_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_iggeneusage_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_iggeneusage_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(IgGeneUsage)
    library(DGU)
    library(LOO)
    library(jsonlite)

    # --- Differential Gene Usage Analysis [] ---
    # Key functions: DGU
    M <- IgGeneUsage::DGU(ud = d_zibb_3,
                          mcmc_warmup = 300,
                          mcmc_steps = 1500,
                          mcmc_chains = 3,
                          mcmc_cores = 1,
                          hdi_lvl = 0.95,
                          adapt_delta = 0.8,
                          max_treedepth = 10)


    # --- Posterior Predictive Checks [] ---
    # Key functions: DGU
    ppc_rep <- M$ppc$ppc_rep
    ppc_plot <- ggplot2::ggplot(data = ppc_rep) +
        ggplot2::facet_wrap(facets = ~individual_id, ncol = 5) +
        ggplot2::geom_abline(intercept = 0, slope = 1,
                             linetype = "dashed", col = "darkgray") +
        ggplot2::geom_errorbar(ggplot2::aes(x = observed_count,
                                            y = ppc_mean_count,
                                            ymin = ppc_L_count,
                                            ymax = ppc_H_count),
                               col = "darkgray") +
        ggplot2::geom_point(ggplot2::aes(x = observed_count,
                                         y = ppc_mean_count),
                            size = 1) +
        ggplot2::theme_bw(base_size = 11) +
        ggplot2::xlab(label = "Observed usage [counts]") +
        ggplot2::ylab(label = "PPC usage [counts]")


    # --- Extract and Visualise DGU Statistics [] ---
    # Key functions: DGU
    stats <- M$dgu
    stats <- stats[order(abs(stats$es_mean), decreasing = FALSE), ]
    stats$gene_fac <- factor(x = stats$gene_name,
                             levels = unique(stats$gene_name))
    promising_genes <- stats$gene_name[stats$pmax >= 0.95]
    
    gu_plot <- ggplot2::ggplot(data = M$gu) +
        ggplot2::geom_errorbar(ggplot2::aes(x = gene_name,
                                            y = prob_mean,
                                            ymin = prob_L,
                                            ymax = prob_H,
                                            col = condition),
                               width = 0.1,
                               position = ggplot2::position_dodge(width = 0.4)) +
        ggplot2::geom_point(ggplot2::aes(x = gene_name,
                                         y = prob_mean,
                                         col = condition),
                            size = 1,
                            position = ggplot2::position_dodge(width = 0.4)) +
        ggplot2::theme_bw(base_size = 11) +
        ggplot2::ylab(label = "GU [probability]") +
        ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 90,
                                                           hjust = 1,
                                                           vjust = 0.4))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_iggeneusage_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_iggeneusage_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_iggeneusage_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_IGGENEUSAGE:", paste0("    iggeneusage: ", packageVersion("IgGeneUsage"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_iggeneusage_results.csv
    touch ${prefix}_iggeneusage_output.rds
    echo "BIOC_IGGENEUSAGE:" > versions.yml
    echo "    iggeneusage: 0.0.0" >> versions.yml
    """
}


workflow BIOC_IGGENEUSAGE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_IGGENEUSAGE(ch_input)

    emit:
    results  = BIOC_IGGENEUSAGE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_IGGENEUSAGE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_IGGENEUSAGE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_IGGENEUSAGE.out.versions  // channel: path(versions.yml)
}
