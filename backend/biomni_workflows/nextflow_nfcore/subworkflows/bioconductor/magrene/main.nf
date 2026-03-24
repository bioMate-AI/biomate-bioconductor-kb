#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: magrene
// magrene allows the identification and analysis of graph motifs in (duplicated) gene regulatory netwo
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/magrene/inst/doc/magrene.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("magrene")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MAGRENE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-magrene"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-magrene:1.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-magrene:1.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_magrene_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_magrene_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_magrene_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(magrene)
    library(jsonlite)

    # --- Ppi v analysis [] ---
    # Key functions: include_graphics, find_ppi_v, find_v, find_lambda, find_delta, find_bifan, generate_nulls, calculate_Z
    delta <- find_delta(edgelist_ppi = gma_ppi, lambda_vec = lambda)
    head(delta)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_magrene_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_magrene_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_magrene_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MAGRENE:", paste0("    magrene: ", packageVersion("magrene"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_magrene_results.csv
    touch ${prefix}_magrene_output.rds
    echo "BIOC_MAGRENE:" > versions.yml
    echo "    magrene: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MAGRENE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MAGRENE(ch_input)

    emit:
    results  = BIOC_MAGRENE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MAGRENE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MAGRENE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MAGRENE.out.versions  // channel: path(versions.yml)
}
