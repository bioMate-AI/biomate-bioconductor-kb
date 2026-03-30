#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: HarmonizR
// An implementation, which takes input data and makes it available for proper batch effect removal by 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/HarmonizR/inst/doc/HarmonizR_Vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("HarmonizR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HARMONIZR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-harmonizr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-harmonizr:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-harmonizr:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_harmonizr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_harmonizr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_harmonizr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SummarizedExperiment)
    library(jsonlite)

    # --- Frame [] ---
    # Key functions: frame, rnorm
    ---------------------------------------------------------------------
    # create a dataframe with 3 rows and 6 columns filled with random numbers
    df <- data.frame(matrix(rnorm(n = 3*6), ncol = 6))
    # set the column names
    colnames(df) <- c("A", "B", "C", "D", "E", "F")
    # --- Rep [] ---
    # Key functions: frame
    ---------------------------------------------------------------------
    # create a vector of batch numbers
    batch <- rep(1:3, each = 2)
    # create a dataframe with 6 rows and 3 columns
    des <- data.frame(ID = colnames(df), sample = 1:6, batch = batch)
    # --- Harmonizr [] ---
    # Key functions: harmonizR
    ---------------------------------------------------------------------
    # use the harmonizR() function; turning off creation of an output .tsv file
    result <- harmonizR(df, des, output_file = FALSE, cores = 1)
    # --- Matrix [] ---
    # Key functions: runif, frame, SummarizedExperiment
    ---------------------------------------------------------------------
    nrows <- 20
    ncols <- 8
    counts <- matrix(runif(nrows * ncols, 1, 1e4), nrows)
    colData <- data.frame(Batch=c(1,1,1,1,2,2,2,2))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_harmonizr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_harmonizr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_harmonizr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HARMONIZR:", paste0("    harmonizr: ", packageVersion("HarmonizR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_harmonizr_results.csv
    touch ${prefix}_harmonizr_output.rds
    echo "BIOC_HARMONIZR:" > versions.yml
    echo "    harmonizr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HARMONIZR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HARMONIZR(ch_input)

    emit:
    results  = BIOC_HARMONIZR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HARMONIZR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HARMONIZR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HARMONIZR.out.versions  // channel: path(versions.yml)
}
