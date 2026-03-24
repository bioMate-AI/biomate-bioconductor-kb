#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: spatialDE
// SpatialDE is a method to find spatially variable genes (SVG) from spatial transcriptomics data. This
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/spatialDE/inst/doc/spatialDE.R
// Upstream  : SpatialExperiment
// Downstream: none
//
// Install: BiocManager::install("spatialDE")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPATIALDE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-spatialde"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-spatialde:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-spatialde:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_spatialde_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_spatialde_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_spatialde_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(FSV_sig)
    library(jsonlite)

    # --- Custom ggplot2 visualization [] ---
    # Key functions: ggplot, geom_point, ggtitle, scale_color_viridis_c, labs
    ggplot(data = MOB_sample_info, aes(x = x, y = y, color = norm_expr[gene, ])) +
    geom_point(size = 7) +
    ggtitle(gene) +
    # --- Stabilize analysis [] ---
    # Key functions: stabilize, regress_out, run, model_search, spatial_patterns, multiGenePlots, FSV_sig, modelSearch
    sample_resid_expr <- head(resid_expr, 1000)
    results <- spatialDE::run(sample_resid_expr, coordinates = X)
    head(results[order(results$qval), ])

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_spatialde_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_spatialde_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_spatialde_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPATIALDE:", paste0("    spatialde: ", packageVersion("spatialDE"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spatialde_results.csv
    touch ${prefix}_spatialde_output.rds
    echo "BIOC_SPATIALDE:" > versions.yml
    echo "    spatialde: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SPATIALDE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SPATIALDE(ch_input)

    emit:
    results  = BIOC_SPATIALDE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SPATIALDE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SPATIALDE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SPATIALDE.out.versions  // channel: path(versions.yml)
}
