#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: gpuMagic
// The package aims to help users write openCL code with little or no effort. It is able to compile an 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/gpuMagic/inst/doc/Customized-openCL-code.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("gpuMagic")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GPUMAGIC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gpumagic"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gpumagic:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gpumagic:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gpumagic_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gpumagic_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gpumagic_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(gpuMagic)
    library(jsonlite)

    # --- Vecadd [] ---
    # Key functions: vecAdd, get_global_id, getDeviceList, setDevice, runif, gpuMatrix, gpuEmptMatrix, kernel
    ---------------------------------------------------------------------
    #The kernel code
    src="
    kernel void vecAdd(global double* A, global double* B, global double* res){
    uint id=get_global_id(0);
    # --- Vecadd [] ---
    # Key functions: vecAdd, get_global_id, gpuMatrix, gpuEmptMatrix, kernel, download
    ---------------------------------------------------------------------
    #Use auto macro to declare the function argument
    #The first argument has auto1, second has auto2 and so on.
    #gAuto is short for global auto
    src="

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gpumagic_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gpumagic_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gpumagic_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GPUMAGIC:", paste0("    gpumagic: ", packageVersion("gpuMagic"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gpumagic_results.csv
    touch ${prefix}_gpumagic_output.rds
    echo "BIOC_GPUMAGIC:" > versions.yml
    echo "    gpumagic: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GPUMAGIC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GPUMAGIC(ch_input)

    emit:
    results  = BIOC_GPUMAGIC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GPUMAGIC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GPUMAGIC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GPUMAGIC.out.versions  // channel: path(versions.yml)
}
