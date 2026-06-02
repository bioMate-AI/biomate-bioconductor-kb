#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SCArray.sat
// Extends the Seurat classes and functions to support Genomic Data Structure (GDS) files as a DelayedA
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SCArray.sat/inst/doc/SCArray.sat.R
// Upstream  : SCArray, Seurat
// Downstream: none
//
// Install: BiocManager::install("SCArray.sat")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCARRAY_SAT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-scarray_sat"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-scarray.sat:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-scarray.sat:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_scarray_sat_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_scarray_sat_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_scarray_sat_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SCArray.sat)
    library(jsonlite)

    # --- Load saved R data object [] ---
    # Key functions: include_graphics, tempfile, remove
    knitr::include_graphics("benchmark.svg")
    save_fn <- tempfile(fileext=".rds")  # or specify an appropriate location
    saveRDS(d, save_fn)  # save to a RDS file

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_scarray_sat_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_scarray_sat_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_scarray_sat_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCARRAY_SAT:", paste0("    scarray_sat: ", packageVersion("SCArray.sat"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scarray_sat_results.csv
    touch ${prefix}_scarray_sat_output.rds
    echo "BIOC_SCARRAY_SAT:" > versions.yml
    echo "    scarray_sat: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCARRAY_SAT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SCARRAY_SAT(ch_input)

    emit:
    results  = BIOC_SCARRAY_SAT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCARRAY_SAT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCARRAY_SAT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCARRAY_SAT.out.versions  // channel: path(versions.yml)
}
