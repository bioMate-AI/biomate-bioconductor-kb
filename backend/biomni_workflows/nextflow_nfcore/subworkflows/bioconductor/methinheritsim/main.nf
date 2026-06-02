#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: methInheritSim
// Simulate a multigeneration methylation case versus control experiment with inheritance relation usin
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/methInheritSim/inst/doc/methInheritSim.R
// Upstream  : knitr
// Downstream: none
//
// Install: BiocManager::install("methInheritSim")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METHINHERITSIM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-methinheritsim"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-methinheritsim:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-methinheritsim:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_methinheritsim_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_methinheritsim_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_methinheritsim_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(methInheritSim)
    library(jsonlite)

    # --- run Sim [] ---
    # Key functions: runSim

    # --- unlink [] ---
    # Key functions: unlink


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_methinheritsim_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_methinheritsim_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_methinheritsim_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_METHINHERITSIM:", paste0("    methinheritsim: ", packageVersion("methInheritSim"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_methinheritsim_results.csv
    touch ${prefix}_methinheritsim_output.rds
    echo "BIOC_METHINHERITSIM:" > versions.yml
    echo "    methinheritsim: 0.0.0" >> versions.yml
    """
}


workflow BIOC_METHINHERITSIM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_METHINHERITSIM(ch_input)

    emit:
    results  = BIOC_METHINHERITSIM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_METHINHERITSIM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_METHINHERITSIM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_METHINHERITSIM.out.versions  // channel: path(versions.yml)
}
