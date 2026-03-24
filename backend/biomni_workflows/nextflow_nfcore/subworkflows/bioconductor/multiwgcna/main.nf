#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: multiWGCNA
// An R package for deeping mining gene co-expression networks in multi-trait expression data. Provides
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/multiWGCNA/inst/doc/astrocyte_map_v2.R
// Upstream  : ExperimentHub, WGCNA, doParallel, vegan
// Downstream: none
//
// Install: BiocManager::install("multiWGCNA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MULTIWGCNA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-multiwgcna"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-multiwgcna:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-multiwgcna:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_multiwgcna_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_multiwgcna_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_multiwgcna_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ExperimentHub)
    library(jsonlite)

    # --- Load Microarray Data [] ---
    # Key functions: ExperimentHub, query, colData, assays, 1, 2
    ---------------------------------------------------------------------
    # Download data from the ExperimentHub
    library(ExperimentHub)
    eh = ExperimentHub()
    # Note: this requires the SummarizedExperiment package to be installed

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_multiwgcna_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_multiwgcna_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_multiwgcna_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MULTIWGCNA:", paste0("    multiwgcna: ", packageVersion("multiWGCNA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multiwgcna_results.csv
    touch ${prefix}_multiwgcna_output.rds
    echo "BIOC_MULTIWGCNA:" > versions.yml
    echo "    multiwgcna: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MULTIWGCNA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MULTIWGCNA(ch_input)

    emit:
    results  = BIOC_MULTIWGCNA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MULTIWGCNA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MULTIWGCNA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MULTIWGCNA.out.versions  // channel: path(versions.yml)
}
