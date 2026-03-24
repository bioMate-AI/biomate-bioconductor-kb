#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: densvis
// Implements the density-preserving modification to t-SNE and UMAP described by Narayan et al. (2020) 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/densvis/inst/doc/densvis.R
// Upstream  : BiocStyle
// Downstream: OSCA.advanced
//
// Install: BiocManager::install("densvis")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DENSVIS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-densvis"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-densvis:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-densvis:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_densvis_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_densvis_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_densvis_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Rtsne)
    library(jsonlite)

    # --- Custom ggplot2 visualization [] ---
    # Key functions: ggplot, aes, geom_point, scale_colour_discrete, ggtitle
    data <- data.frame(
    x = c(rnorm(1000, 5), rnorm(1000, 0, 0.2)),
    y = c(rnorm(1000, 5), rnorm(1000, 0, 0.2)),
    # --- Custom ggplot2 visualization [] ---
    # Key functions: densne, ggplot, aes, geom_point, scale_colour_discrete
    fit1 <- densne(data[, 1:2], dens_frac = 0.5, dens_lambda = 0.5)
    ggplot() +
    aes(fit1[, 1], fit1[, 2], colour = data$class) +
    # --- Custom ggplot2 visualization [] ---
    # Key functions: Rtsne, ggplot, aes, geom_point, scale_colour_discrete
    fit2 <- Rtsne(data[, 1:2])
    ggplot() +
    aes(fit2$Y[, 1], fit2$Y[, 2], colour = data$class) +
    # --- Custom ggplot2 visualization [] ---
    # Key functions: densmap, ggplot, aes, geom_point, scale_colour_discrete
    fit1 <- densmap(data[, 1:2], dens_frac = 0.5, dens_lambda = 0.5)
    ggplot() +
    aes(fit1[, 1], fit1[, 2], colour = data$class) +
    # --- Custom ggplot2 visualization [] ---
    # Key functions: umap, ggplot, aes, geom_point, scale_colour_discrete
    fit2 <- umap(data[, 1:2])
    ggplot() +
    aes(fit2[, 1], fit2[, 2], colour = data$class) +

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_densvis_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_densvis_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_densvis_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DENSVIS:", paste0("    densvis: ", packageVersion("densvis"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_densvis_results.csv
    touch ${prefix}_densvis_output.rds
    echo "BIOC_DENSVIS:" > versions.yml
    echo "    densvis: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DENSVIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DENSVIS(ch_input)

    emit:
    results  = BIOC_DENSVIS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DENSVIS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DENSVIS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DENSVIS.out.versions  // channel: path(versions.yml)
}
