#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: preciseTAD
// preciseTAD provides functions to predict the location of boundaries of topologically associated doma
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/preciseTAD/inst/doc/preciseTAD.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("preciseTAD")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PRECISETAD {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-precisetad"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-precisetad:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-precisetad:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_precisetad_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_precisetad_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_precisetad_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(preciseTAD)
    library(jsonlite)

    # --- Set Options [] ---
    # Key functions: set
    -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
    options(width = 400)
    knitr::opts_chunk$set(warnings = FALSE, message = FALSE)
    # --- Data [] ---
    # Key functions: data
    -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
    data("arrowhead_gm12878_5kb")
    head(arrowhead_gm12878_5kb)
    # --- Extractboundaries [] ---
    # Key functions: extractBoundaries
    -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
    bounds <- extractBoundaries(domains.mat = arrowhead_gm12878_5kb, filter = FALSE, CHR = c("CHR1", "CHR22"), resolution = 5000)
    # View unique boundaries
    bounds
    # --- Bedtograngeslist [] ---
    # Key functions: bedToGRangesList
    -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
    # path <- "./path/to/BEDfiles"
    # tfbsList <- bedToGRangesList(filepath=path, bedList=NULL, bedNames=NULL, pattern = "*.bed", signal=4)
    data("tfbsList")
    names(tfbsList)
    # --- Svm [] ---
    # Key functions: svm, predict
    -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
    svmModel <- svm(y ~ ., data = tadData[[1]], kernel = "radial", cost = 1, gamma = 0.5)
    svmPreds <- predict(svmModel, tadData[[2]][, -1], positive = "Yes")
    # View confusion matrix
    table(svmPreds, tadData[[2]][, 1])

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_precisetad_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_precisetad_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_precisetad_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PRECISETAD:", paste0("    precisetad: ", packageVersion("preciseTAD"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_precisetad_results.csv
    touch ${prefix}_precisetad_output.rds
    echo "BIOC_PRECISETAD:" > versions.yml
    echo "    precisetad: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PRECISETAD_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PRECISETAD(ch_input)

    emit:
    results  = BIOC_PRECISETAD.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PRECISETAD.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PRECISETAD.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PRECISETAD.out.versions  // channel: path(versions.yml)
}
