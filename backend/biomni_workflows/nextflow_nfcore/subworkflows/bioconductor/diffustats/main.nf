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

    # --- Code Block 1 [] ---
    # Key functions: data
    library(diffuStats)
    data("graph_toy")
    # --- Code Block 2 [] ---
    # Key functions: name, dimvector, nei, mutual, asp
    ## IGRAPH 9a7b9df UN-- 48 82 -- Lattice graph
    ## + attr: name (g/c), dimvector (g/n), nei (g/n), mutual (g/l), circular
    ## | (g/l), layout (g/n), asp (g/n), input_vec (g/n), input_mat (g/n),
    ## | output_vec (g/n), output_mat (g/n), input_list (g/x), name (v/c),
    ## | class (v/c), color (v/c), shape (v/c), frame.color (v/c), label.color
    # --- Code Block 4 [] ---
    # Key functions: diffuse
    output_vec <- diffuStats::diffuse(
        graph = graph_toy,
        method = "raw",
        scores = input_vec)
    head(output_vec, 15)
    # --- Code Block 6 [] ---
    # Key functions: diffuse
    output_mc <- diffuStats::diffuse(
        graph = graph_toy,
        method = "mc",
        scores = input_mat)
    head(output_mc)
    # --- Code Block 7 [] ---
    # Key functions: igraph, scores2colours, scores2shapes
    score_col <- 4
    igraph::plot.igraph(
        graph_toy,
        vertex.color = diffuStats::scores2colours(output_mc[, score_col]),
        vertex.shape = diffuStats::scores2shapes(input_mat[, score_col]),
    # --- Code Block 8 [] ---
    # Key functions: perf, grid
    df_perf <- perf(
        graph = graph_toy,
        scores = graph_toy$input_mat,
        validation = graph_toy$input_mat[1:15, ],
        grid_param = expand.grid(method = c("raw", "ml")))
    # --- Code Block 9 [] ---
    # Key functions: perf, grid
    df_perf <- perf(
        graph = graph_toy,
        scores = graph_toy$input_mat[1:20, 3:4],
        validation = graph_toy$input_mat[21:48, 3:4],
        grid_param = expand.grid(method = c("raw", "ml")))
    # --- Code Block 10 [] ---
    # Key functions: 1, namespace
    ## R version 4.4.1 (2024-06-14)
    ## Platform: x86_64-pc-linux-gnu
    ## Running under: Ubuntu 24.04.1 LTS
    ##
    ## Matrix products: default

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
