#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: TRONCO
// The TRONCO (TRanslational ONCOlogy) R package collects algorithms to infer progression models via th
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/TRONCO/inst/doc/f3_data_visualization.R
// Upstream  : rWikiPathways
// Downstream: none
//
// Install: BiocManager::install("TRONCO")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TRONCO {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tronco"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-tronco:2.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-tronco:2.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_tronco_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tronco_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tronco_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(TRONCO)
    library(jsonlite)

    # --- oncoprint [] ---
    # Key functions: oncoprint
    oncoprint(pathway, title = 'Custom pathway',  font.row = 8, cellheight = 15, cellwidth = 4)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_tronco_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_tronco_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_tronco_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TRONCO:", paste0("    tronco: ", packageVersion("TRONCO"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tronco_results.csv
    touch ${prefix}_tronco_output.rds
    echo "BIOC_TRONCO:" > versions.yml
    echo "    tronco: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TRONCO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TRONCO(ch_input)

    emit:
    results  = BIOC_TRONCO.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TRONCO.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TRONCO.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TRONCO.out.versions  // channel: path(versions.yml)
}
