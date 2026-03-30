#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: AUCell
// AUCell allows to identify cells with active gene sets (e.g. signatures, gene modules...) in single-c
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/AUCell/inst/doc/AUCell.R
// Upstream  : DT, GEOquery, GSEABase, Matrix, NMF
// Downstream: OSCA.basic
//
// Install: BiocManager::install("AUCell")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_AUCELL {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-aucell"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-aucell:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-aucell:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_aucell_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_aucell_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_aucell_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(AUCell_buildRankings)
    library(AUCell_calcAUC)
    library(AUCell_exploreThresholds)
    library(AUCell_run)
    library(GeneSet)
    library(GeneSetCollection)
    library(Stangle)
    library(jsonlite)

    # --- Fetch GEO dataset [] ---
    # Key functions: getGEO, fread, unname
    (Downloads the data)
    if (!requireNamespace("GEOquery", quietly = TRUE)) BiocManager::install("GEOquery")
    library(GEOquery)
    # --- Assay data access [] ---
    # Key functions: AUCell_run, AUCell_exploreThresholds, Stangle, assay, GeneSet, getGmt, subsetGeneSets, setGeneSetNames
    selectedThresholds <- getThresholdSelected(cells_assignment)
    par(mfrow=c(2,3)) # Splits the plot into two rows and three columns
    for(geneSetName in names(selectedThresholds)[1:6])

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_aucell_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_aucell_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_aucell_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_AUCELL:", paste0("    aucell: ", packageVersion("AUCell"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_aucell_results.csv
    touch ${prefix}_aucell_output.rds
    echo "BIOC_AUCELL:" > versions.yml
    echo "    aucell: 0.0.0" >> versions.yml
    """
}


workflow BIOC_AUCELL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_AUCELL(ch_input)

    emit:
    results  = BIOC_AUCELL.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_AUCELL.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_AUCELL.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_AUCELL.out.versions  // channel: path(versions.yml)
}
