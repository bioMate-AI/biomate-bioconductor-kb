#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: scifer
// Have you ever index sorted cells in a 96 or 384-well plate and then sequenced using Sanger sequencin
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/scifer/inst/doc/scifer_walkthrough.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("scifer")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCIFER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-scifer"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-scifer:1.8.1--r44_0' :
        'quay.io/biocontainers/bioconductor-scifer:1.8.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_scifer_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_scifer_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_scifer_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(scifer)
    library(jsonlite)

    # --- fcs_processing [] ---
    # Key functions: fcs_processing, fcs_plot

    # --- check fcs noprobe [] ---
    # Key functions: fcs_processing, fcs_plot

    # --- check fcs probe [] ---
    # Key functions: fcs_processing, fcs_plot

    # --- check fcs probe compensated [] ---
    # Key functions: fcs_processing, fcs_plot

    # --- summarise_abi_file [] ---
    # Key functions: summarise_abi_file

    # --- bcr sequences [] ---
    # Key functions: summarise_quality


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_scifer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_scifer_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_scifer_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCIFER:", paste0("    scifer: ", packageVersion("scifer"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scifer_results.csv
    touch ${prefix}_scifer_output.rds
    echo "BIOC_SCIFER:" > versions.yml
    echo "    scifer: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCIFER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SCIFER(ch_input)

    emit:
    results  = BIOC_SCIFER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCIFER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCIFER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCIFER.out.versions  // channel: path(versions.yml)
}
