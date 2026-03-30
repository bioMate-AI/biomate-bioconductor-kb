#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SparseSignatures
// Point mutations occurring in a genome can be divided into 96 categories based on the base being muta
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SparseSignatures/inst/doc/v2_using_the_package.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("SparseSignatures")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPARSESIGNATURES {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sparsesignatures"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-sparsesignatures:2.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-sparsesignatures:2.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_sparsesignatures_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sparsesignatures_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sparsesignatures_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SparseSignatures)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    library("SparseSignatures")
    data(ssm560_reduced)
    head(ssm560_reduced)
    # --- Counts [] ---
    # Key functions: counts
    ---------------------------------------------------------------------
    imported_data = import.trinucleotides.counts(data=ssm560_reduced,reference=bsg)
    head(imported_data)
    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data(patients)
    head(patients)
    # --- Nmflasso [] ---
    # Key functions: nmfLasso
    ---------------------------------------------------------------------
    beta = starting_betas_example[["5_signatures","Value"]]
    res = nmfLasso(x = patients, K = 5, beta = beta, background_signature = background, seed = 12345)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_sparsesignatures_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_sparsesignatures_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_sparsesignatures_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPARSESIGNATURES:", paste0("    sparsesignatures: ", packageVersion("SparseSignatures"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sparsesignatures_results.csv
    touch ${prefix}_sparsesignatures_output.rds
    echo "BIOC_SPARSESIGNATURES:" > versions.yml
    echo "    sparsesignatures: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SPARSESIGNATURES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SPARSESIGNATURES(ch_input)

    emit:
    results  = BIOC_SPARSESIGNATURES.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SPARSESIGNATURES.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SPARSESIGNATURES.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SPARSESIGNATURES.out.versions  // channel: path(versions.yml)
}
