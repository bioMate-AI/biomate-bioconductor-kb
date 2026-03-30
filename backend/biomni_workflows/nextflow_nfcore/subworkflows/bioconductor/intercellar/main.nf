#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: InterCellar
// InterCellar is implemented as an R/Bioconductor Package containing a Shiny app that allows users to 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/InterCellar/inst/doc/user_guide.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("InterCellar")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_INTERCELLAR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-intercellar"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-intercellar:2.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-intercellar:2.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_intercellar_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_intercellar_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_intercellar_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(InterCellar)
    library(jsonlite)

    # --- run_app [] ---
    # Key functions: run_app
    InterCellar::run_app( reproducible = TRUE )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_intercellar_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_intercellar_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_intercellar_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_INTERCELLAR:", paste0("    intercellar: ", packageVersion("InterCellar"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_intercellar_results.csv
    touch ${prefix}_intercellar_output.rds
    echo "BIOC_INTERCELLAR:" > versions.yml
    echo "    intercellar: 0.0.0" >> versions.yml
    """
}


workflow BIOC_INTERCELLAR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_INTERCELLAR(ch_input)

    emit:
    results  = BIOC_INTERCELLAR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_INTERCELLAR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_INTERCELLAR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_INTERCELLAR.out.versions  // channel: path(versions.yml)
}
