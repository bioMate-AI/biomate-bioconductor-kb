#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: diffuStats
// Label propagation approaches are a widely used procedure in computational biology for giving context
//
// Source : https://bioconductor.org/packages/3.20/bioc/https://bioconductor.org/packages/3.20/bioc/vignettes/diffuStats/inst/doc/intro.html
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("diffuStats")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DIFFUSTATS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-diffustats"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-diffustats:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-diffustats:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_diffustats_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_diffustats_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_diffustats_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(diffuStats)
    library(jsonlite)

    # --- Visualisation of Diffusion Scores [] ---
    # Key functions: scores2colours, scores2shapes
    score_col = 4
    v_color = diffuStats::scores2colours(output_mc[, score_col])
    v_shape = diffuStats::scores2shapes(graph_toy$input_mat[, score_col])
    igraph::plot.igraph(graph_toy,
                        vertex.color = v_color,
                        vertex.shape = v_shape)


    # --- Performance Evaluation [] ---
    # Key functions: perf
    df_perf = perf(graph = graph_toy,
                   scores = graph_toy$input_mat,
                   validation = graph_toy$input_mat[1:15, ],
                   grid_param = expand.grid(method = c("raw", "ml")))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_diffustats_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_diffustats_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_diffustats_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DIFFUSTATS:", paste0("    diffustats: ", packageVersion("diffuStats"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_diffustats_results.csv
    touch ${prefix}_diffustats_output.rds
    echo "BIOC_DIFFUSTATS:" > versions.yml
    echo "    diffustats: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DIFFUSTATS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DIFFUSTATS(ch_input)

    emit:
    results  = BIOC_DIFFUSTATS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DIFFUSTATS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DIFFUSTATS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DIFFUSTATS.out.versions  // channel: path(versions.yml)
}
