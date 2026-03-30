#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MetMashR
// A package to merge, filter sort, organise and otherwise mash together metabolite annotation tables. 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MetMashR/inst/doc/Extending_MetMashR.R
// Upstream  : BiocStyle, DT, dplyr, ggplot2, metabolomicsWorkbenchR
// Downstream: none
//
// Install: BiocManager::install("MetMashR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METMASHR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-metmashr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-metmashr:1.0.0--r44_0' :
        'quay.io/biocontainers/bioconductor-metmashr:1.0.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_metmashr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_metmashr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_metmashr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MetMashR)
    library(jsonlite)

    # --- set_struct_obj [] ---
    # Key functions: set_struct_obj, drop_empty_columns, show, set_obj_method
    set_struct_obj(
    params = character(0),
    outputs = c(updated = "annotation_source"),

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_metmashr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_metmashr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_metmashr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_METMASHR:", paste0("    metmashr: ", packageVersion("MetMashR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_metmashr_results.csv
    touch ${prefix}_metmashr_output.rds
    echo "BIOC_METMASHR:" > versions.yml
    echo "    metmashr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_METMASHR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_METMASHR(ch_input)

    emit:
    results  = BIOC_METMASHR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_METMASHR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_METMASHR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_METMASHR.out.versions  // channel: path(versions.yml)
}
