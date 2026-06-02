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

    # --- Initialization and Contextual Mutation [Initialization] ---
    # Key functions: new_plyxp, mutate, cols, rows
    airway_ply <- new_plyxp(airway)
    airway_mutated <- airway_ply |>
        mutate(
            log_counts = log1p(counts),
            cols(treated = dex == "trt"),
            rows(new_id = paste0("gene-", gene_name))
        )

    # --- Assay Scaling and Normalisation [Normalisation] ---
    # Key functions: mutate, rows
    airway_ply$sizeFactor <- runif(ncol(airway_ply), 0.9, 1.1)
    airway_scaled <- airway_ply |>
        mutate(
            scaled_counts = counts / .cols$sizeFactor,
            rows(ave_scl_cts = rowMeans(.assays_asis$scaled_counts))
        )

    # --- Grouping and Summarisation [Aggregation] ---
    # Key functions: group_by, summarize, rows, pull
    summary_se <- airway_ply |>
        group_by(rows(gene_biotype)) |>
        summarize(
            col_sums = colSums(counts),
            rows(.features = unique(gene_biotype))
        )
    col_sums_df <- summary_se |>
        pull(col_sums)

    # --- Feature and Sample Renaming [Metadata Management] ---
    # Key functions: mutate, rows, cols
    se_renamed <- airway_ply |>
        mutate(
            orig_names = sprintf("%s-%s", .rows$.features, .cols$.samples),
            rows(.features = gene_name),
            cols(.samples = Sample)
        )


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
