#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ncdfFlow
// Provides HDF5 storage based methods and functions for manipulation of flow cytometry data.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ncdfFlow/inst/doc/ncdfFlow.R
// Upstream  : flowStats
// Downstream: ggcyto
//
// Install: BiocManager::install("ncdfFlow")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NCDFFLOW {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ncdfflow"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ncdfflow:2.52.1--r44_0' :
        'quay.io/biocontainers/bioconductor-ncdfflow:2.52.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ncdfflow_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ncdfflow_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ncdfflow_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ncdfFlow)
    library(jsonlite)

    # --- Phenotype data inspection [] ---
    # Key functions: sampleNames, unlink, ncdfFlowSet, phenoData, pData, varLabels, varMetadata, eval
    cfile <- system.file("extdata","compdata","compmatrix", package="flowCore")
    comp.mat <- read.table(cfile, header=TRUE, skip=2, check.names = FALSE)
    comp <- compensation(comp.mat)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ncdfflow_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ncdfflow_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ncdfflow_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_NCDFFLOW:", paste0("    ncdfflow: ", packageVersion("ncdfFlow"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ncdfflow_results.csv
    touch ${prefix}_ncdfflow_output.rds
    echo "BIOC_NCDFFLOW:" > versions.yml
    echo "    ncdfflow: 0.0.0" >> versions.yml
    """
}


workflow BIOC_NCDFFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_NCDFFLOW(ch_input)

    emit:
    results  = BIOC_NCDFFLOW.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_NCDFFLOW.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_NCDFFLOW.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_NCDFFLOW.out.versions  // channel: path(versions.yml)
}
