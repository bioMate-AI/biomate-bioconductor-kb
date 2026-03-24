#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ivygapSE
// Define a SummarizedExperiment and exploratory app for Ivy-GAP glioblastoma image, expression, and cl
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ivygapSE/inst/doc/ivygapSE.R
// Upstream  : DT, SummarizedExperiment, ggplot2, grid, limma
// Downstream: none
//
// Install: BiocManager::install("ivygapSE")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_IVYGAPSE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ivygapse"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ivygapse:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ivygapse:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ivygapse_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ivygapse_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ivygapse_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ivygapSE)
    library(jsonlite)

    # --- Get top DE genes table (limma) [] ---
    # Key functions: topTable
    library(limma)
    refex = ivySE[, grep("reference", ivySE$structure_acronym)]
    refmat = assay(refex)
    # --- Datatable analysis [] ---
    # Key functions: datatable, varImpPlot
    refex = ivySE[, grep("reference", ivySE$structure_acronym)]
    refex$struc = factor(refex$structure_acronym)
    iqrs = rowIQRs(assay(refex))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ivygapse_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ivygapse_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ivygapse_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_IVYGAPSE:", paste0("    ivygapse: ", packageVersion("ivygapSE"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ivygapse_results.csv
    touch ${prefix}_ivygapse_output.rds
    echo "BIOC_IVYGAPSE:" > versions.yml
    echo "    ivygapse: 0.0.0" >> versions.yml
    """
}


workflow BIOC_IVYGAPSE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_IVYGAPSE(ch_input)

    emit:
    results  = BIOC_IVYGAPSE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_IVYGAPSE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_IVYGAPSE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_IVYGAPSE.out.versions  // channel: path(versions.yml)
}
