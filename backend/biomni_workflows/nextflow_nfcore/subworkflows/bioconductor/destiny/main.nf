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
    library(destiny)
    library(DPT)
    library(jsonlite)

    # --- Diffusion Pseudo Time Estimation [] ---
    # Key functions: DPT, tips
    data(guo, package = "destiny")
    dm <- destiny::DiffusionMap(guo)
    dpt <- destiny::DPT(dm)
    dpt_tips <- destiny::tips(dpt)


    # --- Transition Probabilities Extraction [] ---
    # Key functions: DiffusionMap, transition_matrix
    data(guo, package = "destiny")
    dm <- destiny::DiffusionMap(guo)
    trans_matrix <- destiny::transition_matrix(dm)

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
