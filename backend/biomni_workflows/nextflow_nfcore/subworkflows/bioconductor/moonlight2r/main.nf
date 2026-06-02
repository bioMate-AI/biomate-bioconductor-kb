#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Moonlight2R
// The understanding of cancer mechanism requires the identification of genes playing a role in the dev
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Moonlight2R/inst/doc/Moonlight2R.R
// Upstream  : dplyr, magrittr
// Downstream: none
//
// Install: BiocManager::install("Moonlight2R")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MOONLIGHT2R {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-moonlight2r"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-moonlight2r:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-moonlight2r:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_moonlight2r_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_moonlight2r_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_moonlight2r_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Moonlight2R)
    library(jsonlite)

    # --- Kable [] ---
    # Key functions: kable
    ---------------------------------------------------------------------
    knitr::kable(LOC_transcription)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_moonlight2r_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_moonlight2r_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_moonlight2r_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MOONLIGHT2R:", paste0("    moonlight2r: ", packageVersion("Moonlight2R"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_moonlight2r_results.csv
    touch ${prefix}_moonlight2r_output.rds
    echo "BIOC_MOONLIGHT2R:" > versions.yml
    echo "    moonlight2r: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MOONLIGHT2R_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MOONLIGHT2R(ch_input)

    emit:
    results  = BIOC_MOONLIGHT2R.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MOONLIGHT2R.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MOONLIGHT2R.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MOONLIGHT2R.out.versions  // channel: path(versions.yml)
}
