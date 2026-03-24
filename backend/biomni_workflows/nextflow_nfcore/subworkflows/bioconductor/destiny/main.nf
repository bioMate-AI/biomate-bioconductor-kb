#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: destiny
// Create and plot diffusion maps.
//
// Source : https://bioconductor.org/packages/3.20/bioc/https://bioconductor.org/packages/3.20/bioc/vignettes/destiny/inst/doc/DPT.html
// Upstream  : gridExtra
// Downstream: none
//
// Install: BiocManager::install("destiny")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DESTINY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-destiny"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-destiny:3.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-destiny:3.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_destiny_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_destiny_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_destiny_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DPT)
    library(jsonlite)

    # --- Code Block 1 [] ---
    # Key functions: data
    library(destiny)    # load destiny…
    data(guo)           # …and sample data
    library(gridExtra)  # Also we need grid.arrange
    # --- Code Block 2 [] ---
    # Key functions: graph_from_literal
    par(mar = rep(0, 4))
    graph <- igraph::graph_from_literal(
        data - + 'transition probabilities' - + DiffusionMap,
        'transition probabilities' - + DPT)
    plot(
    # --- Code Block 4 [] ---
    # Key functions: DPT, sample
    set.seed(4)
    dpt_random <- DPT(dm, tips = sample(ncol(guo), 3L))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_destiny_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_destiny_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_destiny_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DESTINY:", paste0("    destiny: ", packageVersion("destiny"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_destiny_results.csv
    touch ${prefix}_destiny_output.rds
    echo "BIOC_DESTINY:" > versions.yml
    echo "    destiny: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DESTINY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DESTINY(ch_input)

    emit:
    results  = BIOC_DESTINY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DESTINY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DESTINY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DESTINY.out.versions  // channel: path(versions.yml)
}
