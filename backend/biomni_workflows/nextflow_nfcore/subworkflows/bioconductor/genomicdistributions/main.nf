#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GenomicDistributions
// If you have a set of genomic ranges, this package can help you with visualization and comparison. It
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GenomicDistributions/inst/doc/intro.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("GenomicDistributions")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENOMICDISTRIBUTIONS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-genomicdistributions"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-genomicdistributions:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-genomicdistributions:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_genomicdistributions_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_genomicdistributions_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_genomicdistributions_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GenomicDistributions)
    library(jsonlite)

    # --- ChromBins analysis [] ---
    # Key functions: install_github, plotChromBins, plotFeatureDist, plotPartitions, plotExpectedPartitions, plotCumulativePartitions, plotSummarySignal, plotNeighborDist
    exampleCellMatrixFile = system.file("extdata", "example_cell_matrix.txt", package="GenomicDistributions")
    cellMatrix = data.table::fread(exampleCellMatrixFile)
    op = calcSummarySignal(query, cellMatrix)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_genomicdistributions_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_genomicdistributions_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_genomicdistributions_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GENOMICDISTRIBUTIONS:", paste0("    genomicdistributions: ", packageVersion("GenomicDistributions"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genomicdistributions_results.csv
    touch ${prefix}_genomicdistributions_output.rds
    echo "BIOC_GENOMICDISTRIBUTIONS:" > versions.yml
    echo "    genomicdistributions: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GENOMICDISTRIBUTIONS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GENOMICDISTRIBUTIONS(ch_input)

    emit:
    results  = BIOC_GENOMICDISTRIBUTIONS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GENOMICDISTRIBUTIONS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GENOMICDISTRIBUTIONS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GENOMICDISTRIBUTIONS.out.versions  // channel: path(versions.yml)
}
