#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ClusterSignificance
// The ClusterSignificance package provides tools to assess if class clusters in dimensionality reduced
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ClusterSignificance/inst/doc/ClusterSignificance-vignette.R
// Upstream  : ggplot2
// Downstream: none
//
// Install: BiocManager::install("ClusterSignificance")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CLUSTERSIGNIFICANCE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-clustersignificance"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-clustersignificance:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-clustersignificance:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_clustersignificance_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_clustersignificance_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_clustersignificance_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ClusterSignificance)
    library(jsonlite)

    # --- Retrieve data from repository [] ---
    # Key functions: classify, getData
    cl <- classify(prj)
    plot(cl)
    getData(cl, "AUC")
    # --- Principal component analysis [] ---
    # Key functions: prcomp, sample

    # --- Dimnames analysis [] ---
    # Key functions: dimnames, pcp, permute, classify, pvalue
    classes <- rownames(mlpMatrix)
    pe1 <- permute(mat=mat, iter=iterations, classes=classes, projmethod="pcp")
    pe2 <- permute(mat=mat, iter=iterations, classes=classes, projmethod="pcp")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_clustersignificance_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_clustersignificance_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_clustersignificance_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CLUSTERSIGNIFICANCE:", paste0("    clustersignificance: ", packageVersion("ClusterSignificance"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_clustersignificance_results.csv
    touch ${prefix}_clustersignificance_output.rds
    echo "BIOC_CLUSTERSIGNIFICANCE:" > versions.yml
    echo "    clustersignificance: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CLUSTERSIGNIFICANCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CLUSTERSIGNIFICANCE(ch_input)

    emit:
    results  = BIOC_CLUSTERSIGNIFICANCE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CLUSTERSIGNIFICANCE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CLUSTERSIGNIFICANCE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CLUSTERSIGNIFICANCE.out.versions  // channel: path(versions.yml)
}
