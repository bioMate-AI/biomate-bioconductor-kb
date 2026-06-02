#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: fCCAC
// Computational evaluation of variability across DNA or RNA sequencing datasets is a crucial step in g
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/fCCAC/inst/doc/fCCAC.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("fCCAC")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FCCAC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-fccac"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-fccac:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-fccac:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_fccac_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_fccac_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_fccac_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(fCCAC)
    library(jsonlite)

    # --- Heatmapplot [] ---
    # Key functions: heatmapfCCAC
    options(width=50)
    if (.Platform$OS.type == "windows") { print("...rtracklayer is unable to read bigWig format files in Windows...") }
    if (.Platform$OS.type == "unix" ){ heatmapfCCAC(fc) }

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_fccac_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_fccac_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_fccac_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FCCAC:", paste0("    fccac: ", packageVersion("fCCAC"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fccac_results.csv
    touch ${prefix}_fccac_output.rds
    echo "BIOC_FCCAC:" > versions.yml
    echo "    fccac: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FCCAC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FCCAC(ch_input)

    emit:
    results  = BIOC_FCCAC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FCCAC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FCCAC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FCCAC.out.versions  // channel: path(versions.yml)
}
