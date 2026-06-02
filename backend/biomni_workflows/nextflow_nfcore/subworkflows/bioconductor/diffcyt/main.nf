#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: diffcyt
// Statistical methods for differential discovery analyses in high-dimensional cytometry data (includin
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/diffcyt/inst/doc/diffcyt_workflow.R
// Upstream  : HDCytoData, flowCore
// Downstream: censcyt, cytofWorkflow
//
// Install: BiocManager::install("diffcyt")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DIFFCYT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-diffcyt"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-diffcyt:1.26.1--r44_0' :
        'quay.io/biocontainers/bioconductor-diffcyt:1.26.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_diffcyt_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_diffcyt_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_diffcyt_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(diffcyt)
    library(jsonlite)

    # --- Data Preparation and Transformation [] ---
    # Key functions: prepareData, transformData, generateClusters
    d_se <- diffcyt::prepareData(d_flowSet, experiment_info, marker_info)
    d_se <- diffcyt::transformData(d_se)
    d_se <- diffcyt::generateClusters(d_se, seed_clustering = 123)


    # --- Feature Extraction and Differential Testing [] ---
    # Key functions: calcCounts, calcMedians, testDA_edgeR, testDS_limma
    d_counts <- diffcyt::calcCounts(d_se)
    d_medians <- diffcyt::calcMedians(d_se)
    res_DA <- diffcyt::testDA_edgeR(d_counts, design, contrast)
    res_DS <- diffcyt::testDS_limma(
        d_counts, d_medians, design, contrast, plot = FALSE
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_diffcyt_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_diffcyt_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_diffcyt_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DIFFCYT:", paste0("    diffcyt: ", packageVersion("diffcyt"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_diffcyt_results.csv
    touch ${prefix}_diffcyt_output.rds
    echo "BIOC_DIFFCYT:" > versions.yml
    echo "    diffcyt: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DIFFCYT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DIFFCYT(ch_input)

    emit:
    results  = BIOC_DIFFCYT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DIFFCYT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DIFFCYT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DIFFCYT.out.versions  // channel: path(versions.yml)
}
