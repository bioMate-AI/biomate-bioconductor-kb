#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: AnVILWorkflow
// The AnVIL is a cloud computing resource developed in part by the National Human Genome Research Inst
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/AnVILWorkflow/inst/doc/salmon.R
// Upstream  : AnVIL, AnVILGCP, BiocManager
// Downstream: none
//
// Install: BiocManager::install("AnVILWorkflow")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ANVILWORKFLOW {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-anvilworkflow"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-anvilworkflow:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-anvilworkflow:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_anvilworkflow_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_anvilworkflow_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_anvilworkflow_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Terra)
    library(jsonlite)

    # --- Terra [] ---
    # Key functions: Terra

    # --- get Output [] ---
    # Key functions: getOutput


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_anvilworkflow_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_anvilworkflow_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_anvilworkflow_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ANVILWORKFLOW:", paste0("    anvilworkflow: ", packageVersion("AnVILWorkflow"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_anvilworkflow_results.csv
    touch ${prefix}_anvilworkflow_output.rds
    echo "BIOC_ANVILWORKFLOW:" > versions.yml
    echo "    anvilworkflow: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ANVILWORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ANVILWORKFLOW(ch_input)

    emit:
    results  = BIOC_ANVILWORKFLOW.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ANVILWORKFLOW.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ANVILWORKFLOW.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ANVILWORKFLOW.out.versions  // channel: path(versions.yml)
}
