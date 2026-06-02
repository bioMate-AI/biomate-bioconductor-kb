#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GladiaTOX
// GladiaTOX R package is an open-source, flexible solution to high-content screening data processing a
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GladiaTOX/inst/doc/GladiaTOX.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("GladiaTOX")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GLADIATOX {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gladiatox"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gladiatox:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gladiatox:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gladiatox_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gladiatox_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gladiatox_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GladiaTOX)
    library(jsonlite)

    # --- fig=TRUE [] ---
    # Key functions: gtoxPlotPlate
    gtoxPlotPlate(dat = l2, apid = apid, id = acid)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gladiatox_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gladiatox_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gladiatox_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GLADIATOX:", paste0("    gladiatox: ", packageVersion("GladiaTOX"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gladiatox_results.csv
    touch ${prefix}_gladiatox_output.rds
    echo "BIOC_GLADIATOX:" > versions.yml
    echo "    gladiatox: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GLADIATOX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GLADIATOX(ch_input)

    emit:
    results  = BIOC_GLADIATOX.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GLADIATOX.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GLADIATOX.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GLADIATOX.out.versions  // channel: path(versions.yml)
}
