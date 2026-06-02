#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: vsclust
// Feature-based variance-sensitive clustering of omics data. Optimizes cluster assignment by taking in
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/vsclust/inst/doc/Integrate_With_Bioconductor_Objects.R
// Upstream  : MultiAssayExperiment, clusterProfiler, matrixStats
// Downstream: none
//
// Install: BiocManager::install("vsclust")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_VSCLUST {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-vsclust"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-vsclust:1.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-vsclust:1.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_vsclust_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_vsclust_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_vsclust_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(vsclust)
    library(jsonlite)

    # --- Calculation [] ---
    # Key functions: calculation, 0
    ---------------------------------------------------------------------
    #### Input parameters, only read when now parameter file was provided #####
    ## All principal parameters for running VSClust can be defined as in the
    ## shiny app at computproteomics.bmb.sdu.dk/Apps/VSClust
    # name of study
    # --- Clustering [] ---
    # Key functions: clustering, runClustWrapper
    ---------------------------------------------------------------------

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_vsclust_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_vsclust_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_vsclust_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_VSCLUST:", paste0("    vsclust: ", packageVersion("vsclust"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_vsclust_results.csv
    touch ${prefix}_vsclust_output.rds
    echo "BIOC_VSCLUST:" > versions.yml
    echo "    vsclust: 0.0.0" >> versions.yml
    """
}


workflow BIOC_VSCLUST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_VSCLUST(ch_input)

    emit:
    results  = BIOC_VSCLUST.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_VSCLUST.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_VSCLUST.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_VSCLUST.out.versions  // channel: path(versions.yml)
}
