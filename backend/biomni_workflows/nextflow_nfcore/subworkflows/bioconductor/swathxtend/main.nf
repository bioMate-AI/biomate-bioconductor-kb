#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SwathXtend
// Contains utility functions for integrating spectral libraries for SWATH and statistical data analysi
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SwathXtend/inst/doc/SwathXtend_vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("SwathXtend")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SWATHXTEND {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-swathxtend"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-swathxtend:2.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-swathxtend:2.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_swathxtend_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_swathxtend_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_swathxtend_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SwathXtend)
    library(jsonlite)

    # --- Quality Control Assessment [] ---
    # Key functions: checkQuality
    qc_results <- checkQuality(
        lib1 = lib2_data,
        lib2 = lib3_data
    )


    # --- Library Comparison Visualization [] ---
    # Key functions: plotAll
    plotAll(
        lib1 = lib2_data,
        lib2 = lib3_data,
        file = "library_comparison_plots.xlsx"
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_swathxtend_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_swathxtend_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_swathxtend_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SWATHXTEND:", paste0("    swathxtend: ", packageVersion("SwathXtend"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_swathxtend_results.csv
    touch ${prefix}_swathxtend_output.rds
    echo "BIOC_SWATHXTEND:" > versions.yml
    echo "    swathxtend: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SWATHXTEND_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SWATHXTEND(ch_input)

    emit:
    results  = BIOC_SWATHXTEND.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SWATHXTEND.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SWATHXTEND.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SWATHXTEND.out.versions  // channel: path(versions.yml)
}
