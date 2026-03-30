#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: scp
// Utility functions for manipulating, processing, and analyzing mass spectrometry-based single-cell pr
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/scp/inst/doc/QFeatures_nutshell.R
// Upstream  : ggplot2
// Downstream: none
//
// Install: BiocManager::install("scp")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-scp"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-scp:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-scp:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_scp_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_scp_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_scp_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(scp)
    library(jsonlite)

    # --- Custom ggplot2 visualization [] ---
    # Key functions: rbindRowData, ggplot, aes, geom_boxplot, longFormat
    lf <- longFormat(scp1[, , 1],
    colvars = c("SampleType", "Channel"))
    ggplot(data.frame(lf)) +
    # --- Assay data access [] ---
    # Key functions: assay, rowData, rbindRowData, subsetByAssay, subsetByColData, subsetByFeature, filterFeatures, filterNA
    anyNA(assay(scp1, "proteins"))
    scp1 <- impute(scp1, i = "proteins", method ="knn", k = 3)
    anyNA(assay(scp1, "proteins"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_scp_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_scp_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_scp_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCP:", paste0("    scp: ", packageVersion("scp"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scp_results.csv
    touch ${prefix}_scp_output.rds
    echo "BIOC_SCP:" > versions.yml
    echo "    scp: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SCP(ch_input)

    emit:
    results  = BIOC_SCP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCP.out.versions  // channel: path(versions.yml)
}
