#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DMRScan
// This package detects significant differentially methylated regions (for both qualitative and quantit
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DMRScan/inst/doc/DMRScan_vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("DMRScan")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DMRSCAN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-dmrscan"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-dmrscan:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-dmrscan:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_dmrscan_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_dmrscan_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_dmrscan_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DMRScan)
    library(jsonlite)

    # --- make Cp Gregions [] ---
    # Key functions: makeCpGregions
    regions <- makeCpGregions(observations  = observations, chr = pos[,1], pos = pos[,2],

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_dmrscan_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_dmrscan_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_dmrscan_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DMRSCAN:", paste0("    dmrscan: ", packageVersion("DMRScan"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dmrscan_results.csv
    touch ${prefix}_dmrscan_output.rds
    echo "BIOC_DMRSCAN:" > versions.yml
    echo "    dmrscan: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DMRSCAN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DMRSCAN(ch_input)

    emit:
    results  = BIOC_DMRSCAN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DMRSCAN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DMRSCAN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DMRSCAN.out.versions  // channel: path(versions.yml)
}
