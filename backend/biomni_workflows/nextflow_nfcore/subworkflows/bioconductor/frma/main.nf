#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: frma
// Preprocessing and analysis for single microarrays and microarray batches.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/frma/inst/doc/frma.R
// Upstream  : frmaExampleData
// Downstream: none
//
// Install: BiocManager::install("frma")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FRMA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-frma"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-frma:1.58.0--r44_0' :
        'quay.io/biocontainers/bioconductor-frma:1.58.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_frma_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_frma_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_frma_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GNUSE)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    library(frmaExampleData)
    data(AffyBatchExample)
    # --- Frma [] ---
    # Key functions: frma
    object <- frma(AffyBatchExample)
    # --- Gnuse [] ---
    # Key functions: GNUSE
    GNUSE(object,type="stats")
    # --- Data [] ---
    # Key functions: frma
    library(frmaExampleData)
    data(AffyBatchExample)
    object <- frma(AffyBatchExample)
    # --- Barcode [] ---
    # Key functions: barcode
    bc <- barcode(object)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_frma_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_frma_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_frma_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FRMA:", paste0("    frma: ", packageVersion("frma"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_frma_results.csv
    touch ${prefix}_frma_output.rds
    echo "BIOC_FRMA:" > versions.yml
    echo "    frma: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FRMA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FRMA(ch_input)

    emit:
    results  = BIOC_FRMA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FRMA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FRMA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FRMA.out.versions  // channel: path(versions.yml)
}
