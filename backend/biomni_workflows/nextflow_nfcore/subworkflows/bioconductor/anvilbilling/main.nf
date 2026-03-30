#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: AnVILBilling
// AnVILBilling helps monitor AnVIL-related costs in R, using queries to a BigQuery table to which cost
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/AnVILBilling/inst/doc/billing.R
// Upstream  : BiocStyle, dplyr, magrittr
// Downstream: none
//
// Install: BiocManager::install("AnVILBilling")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ANVILBILLING {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-anvilbilling"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-anvilbilling:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-anvilbilling:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_anvilbilling_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_anvilbilling_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_anvilbilling_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(AnVILBilling)
    library(jsonlite)

    # --- get Submission Cost [] ---
    # Key functions: getSubmissionCost
    data(demo_rec) # makes rec
    v = getValues(demo_rec@reckoning, "terra-submission-id")[1] # for instance
    getSubmissionCost(demo_rec@reckoning,v)
    # --- get Submission Ram [] ---
    # Key functions: getSubmissionRam
    data(demo_rec) # makes rec
    v = getValues(demo_rec@reckoning, "terra-submission-id")[1] # for instance
    getSubmissionRam(demo_rec@reckoning,v)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_anvilbilling_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_anvilbilling_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_anvilbilling_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ANVILBILLING:", paste0("    anvilbilling: ", packageVersion("AnVILBilling"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_anvilbilling_results.csv
    touch ${prefix}_anvilbilling_output.rds
    echo "BIOC_ANVILBILLING:" > versions.yml
    echo "    anvilbilling: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ANVILBILLING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ANVILBILLING(ch_input)

    emit:
    results  = BIOC_ANVILBILLING.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ANVILBILLING.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ANVILBILLING.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ANVILBILLING.out.versions  // channel: path(versions.yml)
}
