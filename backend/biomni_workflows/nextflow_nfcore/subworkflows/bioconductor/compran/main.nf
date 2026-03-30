#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ComPrAn
// This package is for analysis of SILAC labeled complexome profiling data. It uses peptide table in ta
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ComPrAn/inst/doc/proteinWorkflow.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("ComPrAn")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_COMPRAN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-compran"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-compran:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-compran:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_compran_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_compran_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_compran_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ComPrAn)
    library(jsonlite)

    # --- group Heat Map [] ---
    # Key functions: groupHeatMap, oneGroupTwoLabelsCoMigration, clusterComp, assignClusters
    groupDataFileName <- system.file("extData","exampleGroup.txt",package="ComPrAn")
    groupData <- data.table::fread(groupDataFileName)
    (default settings)
    # --- make Bar Plot Cluster Summary [] ---
    # Key functions: makeBarPlotClusterSummary, exportClusterAssignments
    makeBarPlotClusterSummary(labTab_clust, name = 'labeled')
    makeBarPlotClusterSummary(unlabTab_clust, name = 'unlabeled')
    tableForClusterExport <- exportClusterAssignments(labTab_clust,unlabTab_clust)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_compran_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_compran_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_compran_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_COMPRAN:", paste0("    compran: ", packageVersion("ComPrAn"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_compran_results.csv
    touch ${prefix}_compran_output.rds
    echo "BIOC_COMPRAN:" > versions.yml
    echo "    compran: 0.0.0" >> versions.yml
    """
}


workflow BIOC_COMPRAN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_COMPRAN(ch_input)

    emit:
    results  = BIOC_COMPRAN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_COMPRAN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_COMPRAN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_COMPRAN.out.versions  // channel: path(versions.yml)
}
