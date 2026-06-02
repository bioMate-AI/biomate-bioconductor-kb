#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: vidger
// The aim of vidger is to rapidly generate information-rich visualizations for the interpretation of d
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/vidger/inst/doc/vidger.R
// Upstream  : DESeq2, edgeR
// Downstream: none
//
// Install: BiocManager::install("vidger")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_VIDGER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-vidger"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-vidger:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-vidger:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_vidger_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_vidger_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_vidger_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(vidger)
    library(jsonlite)

    # --- Vsdegmatrix [] ---
    # Key functions: vsDEGMatrix
    ---------------------------------------------------------------------
    vsDEGMatrix(data = df.deseq, d.factor = "condition", type = "deseq",
        grey.scale = TRUE
    )
    # --- Data [] ---
    # Key functions: vsScatterPlot
    ---------------------------------------------------------------------
    # Extract data frame from visualization
    data("df.cuff")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_vidger_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_vidger_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_vidger_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_VIDGER:", paste0("    vidger: ", packageVersion("vidger"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_vidger_results.csv
    touch ${prefix}_vidger_output.rds
    echo "BIOC_VIDGER:" > versions.yml
    echo "    vidger: 0.0.0" >> versions.yml
    """
}


workflow BIOC_VIDGER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_VIDGER(ch_input)

    emit:
    results  = BIOC_VIDGER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_VIDGER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_VIDGER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_VIDGER.out.versions  // channel: path(versions.yml)
}
