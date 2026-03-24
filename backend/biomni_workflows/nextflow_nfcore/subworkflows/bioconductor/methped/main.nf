#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MethPed
// Classification of pediatric tumors into biologically defined subtypes is challenging and multifacete
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MethPed/inst/doc/MethPed-vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("MethPed")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METHPED {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-methped"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-methped:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-methped:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_methped_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_methped_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_methped_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MethPed)
    library(jsonlite)

    # --- Check missing probe data [] ---
    # Key functions: checkNA
    missingIndex <- checkNA(MethPed_sample)
    # --- Run MethPed classifier [] ---
    # Key functions: MethPed
    myClassification <- MethPed(MethPed_sample)
    # --- Function to get missing probes [] ---
    # Key functions: probeMis
    probeMis(myClassification)
    data(MethPed_sample)
    class(MethPed_sample)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_methped_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_methped_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_methped_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_METHPED:", paste0("    methped: ", packageVersion("MethPed"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_methped_results.csv
    touch ${prefix}_methped_output.rds
    echo "BIOC_METHPED:" > versions.yml
    echo "    methped: 0.0.0" >> versions.yml
    """
}


workflow BIOC_METHPED_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_METHPED(ch_input)

    emit:
    results  = BIOC_METHPED.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_METHPED.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_METHPED.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_METHPED.out.versions  // channel: path(versions.yml)
}
