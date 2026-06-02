#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MethReg
// Epigenome-wide association studies (EWAS) detects a large number of DNA methylation differences, oft
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MethReg/inst/doc/MethReg.R
// Upstream  : GSVA, ReMapEnrich, dplyr, sesameData
// Downstream: none
//
// Install: BiocManager::install("MethReg")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METHREG {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-methreg"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-methreg:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-methreg:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_methreg_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_methreg_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_methreg_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MethReg)
    library(jsonlite)

    # --- read P N G [] ---
    # Key functions: readPNG
    png::readPNG("workflow_methReg.png") %>% grid::grid.raster()
    # --- plot interaction model [] ---
    # Key functions: plot_interaction_model

    # --- read P N G [] ---
    # Key functions: readPNG
    png::readPNG("scenarios.png")  %>% grid::grid.raster()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_methreg_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_methreg_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_methreg_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_METHREG:", paste0("    methreg: ", packageVersion("MethReg"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_methreg_results.csv
    touch ${prefix}_methreg_output.rds
    echo "BIOC_METHREG:" > versions.yml
    echo "    methreg: 0.0.0" >> versions.yml
    """
}


workflow BIOC_METHREG_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_METHREG(ch_input)

    emit:
    results  = BIOC_METHREG.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_METHREG.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_METHREG.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_METHREG.out.versions  // channel: path(versions.yml)
}
