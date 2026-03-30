#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ExCluster
// ExCluster flattens Ensembl and GENCODE GTF files into GFF files, which are used to count reads per n
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ExCluster/inst/doc/ExCluster.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("ExCluster")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EXCLUSTER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-excluster"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-excluster:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-excluster:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_excluster_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_excluster_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_excluster_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ExCluster)
    library(GRangesFromExClustResults)
    library(jsonlite)

    # --- Samples [] ---
    # Key functions: samples, ExCluster
    # assign condition numbers to your samples (we have 4 samples, 2 replicates per condition)
    condNums <- c(1,1,2,2)
    # now we run ExCluster, assigning its output to the ExClustResults variable
    # we are not writing out the ExClustResults table, nor are we plotting exons
    # we also use combine.Exons=FALSE to discover one 'significant' gene for example plot purposes
    # --- Grangesfromexclustresults [] ---
    # Key functions: GRangesFromExClustResults
    GRanges.ExClustResults <- GRangesFromExClustResults(results.ExClust=ExClust_Results)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_excluster_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_excluster_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_excluster_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_EXCLUSTER:", paste0("    excluster: ", packageVersion("ExCluster"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_excluster_results.csv
    touch ${prefix}_excluster_output.rds
    echo "BIOC_EXCLUSTER:" > versions.yml
    echo "    excluster: 0.0.0" >> versions.yml
    """
}


workflow BIOC_EXCLUSTER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_EXCLUSTER(ch_input)

    emit:
    results  = BIOC_EXCLUSTER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_EXCLUSTER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_EXCLUSTER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_EXCLUSTER.out.versions  // channel: path(versions.yml)
}
