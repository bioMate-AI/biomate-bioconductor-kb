#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: plyxp
// The package provides `rlang` data masks for the SummarizedExperiment class. The enables the evaluati
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/plyxp/inst/doc/plyxp.R
// Upstream  : airway, dplyr, tibble
// Downstream: none
//
// Install: BiocManager::install("plyxp")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PLYXP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-plyxp"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-plyxp:1.0.1--r44_0' :
        'quay.io/biocontainers/bioconductor-plyxp:1.0.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_plyxp_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_plyxp_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_plyxp_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(plyxp)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: cols, rows, mutate, log1p
    ---------------------------------------------------------------------
    # add data (mutate) to any of the three tables,
    # assay, colData, rowData,
    # ...using contextual helpers cols() and rows()
    airway |>
    # --- Runif [] ---
    # Key functions: runif, mutate, rows, rowMeans
    ---------------------------------------------------------------------
    airway$sizeFactor <- runif(8, .9, 1.1)
    # making scaled counts, then computing row means:
    airway |>
      mutate(scaled_counts = counts / .cols$sizeFactor, #
    # --- Mutate [] ---
    # Key functions: mutate, rows, cols, map_dbl
    ---------------------------------------------------------------------
    airway |>
      mutate(scaled_counts = counts / .cols$sizeFactor,
             # You may expect a list when accessing other contexts
             # from either the rows() or cols() contexts.
    # --- Group By [] ---
    # Key functions: group_by, rows, summarize, colSums, rowData, pull
    ---------------------------------------------------------------------
    summary <- airway |>
      group_by(rows(gene_biotype)) |>
      summarize(col_sums = colSums(counts),
                # may rename rows with .features
    # --- Mutate [] ---
    # Key functions: mutate
    ---------------------------------------------------------------------
    # here the `.cols$` pronoun reshapes the data to fit the `assays` context
    airway |>
      mutate(scaled_counts = counts / .cols$sizeFactor)
    # this is equivalent to the following, where we have to transpose
    # --- Mutate [] ---
    # Key functions: mutate, rows, cols
    ---------------------------------------------------------------------
    se_simple
    # moving data to rownames and colnames
    se_simple |>
      mutate(

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_plyxp_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_plyxp_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_plyxp_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PLYXP:", paste0("    plyxp: ", packageVersion("plyxp"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_plyxp_results.csv
    touch ${prefix}_plyxp_output.rds
    echo "BIOC_PLYXP:" > versions.yml
    echo "    plyxp: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PLYXP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PLYXP(ch_input)

    emit:
    results  = BIOC_PLYXP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PLYXP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PLYXP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PLYXP.out.versions  // channel: path(versions.yml)
}
