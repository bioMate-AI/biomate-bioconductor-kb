#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: AnVILBase
// Provides generic functions for interacting with the AnVIL ecosystem. Packages that use either GCP or
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/AnVILBase/inst/doc/AnVILBaseIntroduction.R
// Upstream  : none
// Downstream: AnVIL, AnVILWorkflow
//
// Install: BiocManager::install("AnVILBase")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ANVILBASE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-anvilbase"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-anvilbase:1.0.0--r44_0' :
        'quay.io/biocontainers/bioconductor-anvilbase:1.0.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_anvilbase_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_anvilbase_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_anvilbase_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(AnVILBase)
    library(jsonlite)


    # --- Eval=false [] ---
    # Key functions: cloud_platform, avplatform_namespace, sessionInfo
    #  cloud_platform()

    ## -----------------------------------------------------------------------------
    avplatform_namespace()

    ## -----------------------------------------------------------------------------
    sessionInfo()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_anvilbase_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_anvilbase_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_anvilbase_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ANVILBASE:", paste0("    anvilbase: ", packageVersion("AnVILBase"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_anvilbase_results.csv
    touch ${prefix}_anvilbase_output.rds
    echo "BIOC_ANVILBASE:" > versions.yml
    echo "    anvilbase: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ANVILBASE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ANVILBASE(ch_input)

    emit:
    results  = BIOC_ANVILBASE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ANVILBASE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ANVILBASE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ANVILBASE.out.versions  // channel: path(versions.yml)
}
