#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: alabaster.mae
// Save MultiAssayExperiments into file artifacts, and load them back into memory. This is a more porta
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/alabaster.mae/inst/doc/userguide.R
// Upstream  : BiocStyle, MultiAssayExperiment, SummarizedExperiment
// Downstream: none
//
// Install: BiocManager::install("alabaster.mae")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ALABASTER_MAE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-alabaster_mae"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-alabaster.mae:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-alabaster.mae:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(input_file)

    output:
    tuple val(meta), path("${meta.id}_alabaster_mae_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_alabaster_mae_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_alabaster_mae_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SummarizedExperiment)
    library(jsonlite)

    # --- Matrix [] ---
    # Key functions: rpois, SummarizedExperiment
    ---------------------------------------------------------------------
    library(SummarizedExperiment)
    rna.counts <- matrix(rpois(60, 10), ncol=6)
    colnames(rna.counts) <- c("disease1", "disease2", "disease3", "control1", "control2", "control3")
    rownames(rna.counts) <- c("ENSMUSG00000000001", "ENSMUSG00000000003", "ENSMUSG00000000028",
    # --- Readobject [] ---
    # Key functions: readObject
    ---------------------------------------------------------------------
    roundtrip <- readObject(tmp)
    class(roundtrip)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_alabaster_mae_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_alabaster_mae_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_alabaster_mae_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ALABASTER_MAE:", paste0("    alabaster_mae: ", packageVersion("alabaster.mae"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_alabaster_mae_results.csv
    touch ${prefix}_alabaster_mae_output.rds
    echo "BIOC_ALABASTER_MAE:" > versions.yml
    echo "    alabaster_mae: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ALABASTER_MAE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input_file) ]

    main:
    BIOC_ALABASTER_MAE(ch_input)

    emit:
    results  = BIOC_ALABASTER_MAE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ALABASTER_MAE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ALABASTER_MAE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ALABASTER_MAE.out.versions  // channel: path(versions.yml)
}
