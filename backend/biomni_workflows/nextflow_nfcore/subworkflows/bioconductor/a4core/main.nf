#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: a4Core
// Utility functions for the Automated Affymetrix Array Analysis set of packages.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/a4Core/inst/doc/a4Core-vignette.R
// Upstream  : none
// Downstream: a4, a4Base, a4Classif, nlcv
//
// Install: BiocManager::install("a4Core")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_A4CORE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-a4core"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-a4core:1.54.0--r44_0' :
        'quay.io/biocontainers/bioconductor-a4core:1.54.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_a4core_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_a4core_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_a4core_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(a4Core)
    library(jsonlite)


    # --- Simulate Data [] ---
    # Key functions: simulateData
    eSet <- simulateData(
    	nCols = 40, nRows = 1000, 
    	nEffectRows = 5, nNoEffectCols = 5,
    	betweenClassDifference = 1, withinClassSd = 0.5
    )
    print(eSet)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_a4core_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_a4core_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_a4core_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_A4CORE:", paste0("    a4core: ", packageVersion("a4Core"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_a4core_results.csv
    touch ${prefix}_a4core_output.rds
    echo "BIOC_A4CORE:" > versions.yml
    echo "    a4core: 0.0.0" >> versions.yml
    """
}


workflow BIOC_A4CORE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_A4CORE(ch_input)

    emit:
    results  = BIOC_A4CORE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_A4CORE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_A4CORE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_A4CORE.out.versions  // channel: path(versions.yml)
}
