#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MOSim
// MOSim package simulates multi-omic experiments that mimic regulatory mechanisms within the cell, all
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MOSim/inst/doc/MOSim.R
// Upstream  : devtools, ggplot2
// Downstream: none
//
// Install: BiocManager::install("MOSim")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MOSIM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mosim"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mosim:2.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mosim:2.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mosim_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mosim_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mosim_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MOSim)
    library(jsonlite)

    # --- Plot theme styling [] ---
    # Key functions: install_github, mosim, omicData, omicSim, omicSettings, omicResults, experimentalDesign, plotProfile
    rnaseq_simulation <- mosim(omics = c("RNA-seq", "ChIP-seq"))
    rnaseq_simulated <- omicResults(rnaseq_simulation, c("RNA-seq", "ChIP-seq"))
    discrete_ChIP <- discretize(rnaseq_simulated, "ChIP-seq")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mosim_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mosim_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mosim_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MOSIM:", paste0("    mosim: ", packageVersion("MOSim"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mosim_results.csv
    touch ${prefix}_mosim_output.rds
    echo "BIOC_MOSIM:" > versions.yml
    echo "    mosim: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MOSIM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MOSIM(ch_input)

    emit:
    results  = BIOC_MOSIM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MOSIM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MOSIM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MOSIM.out.versions  // channel: path(versions.yml)
}
