#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: cardelino
// Methods to infer clonal tree configuration for a population of cells using single-cell RNA-seq data 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/cardelino/inst/doc/vignette-cloneid.R
// Upstream  : ggplot2
// Downstream: none
//
// Install: BiocManager::install("cardelino")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CARDELINO {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cardelino"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cardelino:1.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cardelino:1.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cardelino_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cardelino_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cardelino_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(cardelino)
    library(jsonlite)

    # --- De Novo Clone Inference [] ---
    # Key functions: clone_id
    assign_mtClones <- cardelino::clone_id(
        A = AD,
        D = DP,
        Config = NULL,
        n_clone = 3,
        keep_base_clone = FALSE
    )
    cell_prob <- assign_mtClones$prob
    config_prob <- assign_mtClones$Config_prob


    # --- Clonal Visualization [] ---
    # Key functions: vc_heatmap
    AF_mt <- as.matrix(AD / DP)
    Config_mt <- assign_mtClones$Config_prob
    Config_mt[Config_mt >= 0.5] <- 1
    Config_mt[Config_mt < 0.5] <- 0
    vc_plot <- cardelino::vc_heatmap(
        AF_mt,
        assign_mtClones$prob,
        Config_mt,
        show_legend = TRUE
    )


    # --- Clonal Configuration Analysis [] ---
    # Key functions: heat_matrix
    config_diff <- assign_mtClones$Config_prob - Config_mt
    diff_plot <- cardelino::heat_matrix(t(config_diff)) +
        ggplot2::scale_fill_gradient2() +
        ggplot2::ggtitle("Changes of clonal Config") +
        ggplot2::labs(x = "Clones", y = "Variants")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cardelino_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cardelino_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cardelino_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CARDELINO:", paste0("    cardelino: ", packageVersion("cardelino"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cardelino_results.csv
    touch ${prefix}_cardelino_output.rds
    echo "BIOC_CARDELINO:" > versions.yml
    echo "    cardelino: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CARDELINO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CARDELINO(ch_input)

    emit:
    results  = BIOC_CARDELINO.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CARDELINO.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CARDELINO.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CARDELINO.out.versions  // channel: path(versions.yml)
}
