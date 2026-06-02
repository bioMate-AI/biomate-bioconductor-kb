#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: sechm
// sechm provides a simple interface between SummarizedExperiment objects and the ComplexHeatmap packag
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/sechm/inst/doc/sechm.R
// Upstream  : ComplexHeatmap, SummarizedExperiment
// Downstream: SEtools
//
// Install: BiocManager::install("sechm")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SECHM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sechm"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-sechm:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-sechm:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_sechm_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sechm_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sechm_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(sechm)
    library(jsonlite)

    # --- colors in object [] ---
    # Key functions: metadata, sechm
    metadata(SE)$hmcols <- c("darkred","white","darkblue")
    sechm(SE, g, do.scale = TRUE)
    # --- anno in object [] ---
    # Key functions: metadata

    # --- colors in options [] ---
    # Key functions: setSechmOption, sechm, resetAllSechmOptions, metadata
    setSechmOption("hmcols", value=c("white","grey","black"))
    sechm(SE, g, do.scale = TRUE)
    resetAllSechmOptions()
    # --- sechm [] ---
    # Key functions: sechm
    sechm(SE, features=g) + sechm(SE, features=g)
    # --- assays [] ---
    # Key functions: assays, crossHm
    assays(SE2)$logcpm <- jitter(assays(SE2)$logcpm, factor=1000)
    crossHm(list(SE1=SE, SE2=SE2), g, do.scale = TRUE,
    top_annotation=c("Condition","Time"))
    # --- cross Hm [] ---
    # Key functions: crossHm
    crossHm(list(SE1=SE, SE2=SE2), g, do.scale = TRUE,
    top_annotation=c("Condition","Time"), uniqueScale = TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_sechm_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_sechm_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_sechm_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SECHM:", paste0("    sechm: ", packageVersion("sechm"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sechm_results.csv
    touch ${prefix}_sechm_output.rds
    echo "BIOC_SECHM:" > versions.yml
    echo "    sechm: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SECHM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SECHM(ch_input)

    emit:
    results  = BIOC_SECHM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SECHM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SECHM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SECHM.out.versions  // channel: path(versions.yml)
}
