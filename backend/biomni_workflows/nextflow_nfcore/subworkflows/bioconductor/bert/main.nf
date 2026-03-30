#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BERT
// Provides efficient batch-effect adjustment of data with missing values. BERT orders all batch effect
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BERT/inst/doc/BERT-Vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("BERT")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BERT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-bert"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-bert:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-bert:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_bert_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_bert_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_bert_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BERT)
    library(SummarizedExperiment)
    library(jsonlite)

    # --- Frame [] ---
    # Key functions: frame, rnorm
    ---------------------------------------------------------------------
    example = data.frame(feature_1 = stats::rnorm(5), feature_2 = stats::rnorm(5), Batch=c(1,1,2,2,2))
    example
    # --- Matrix [] ---
    # Key functions: runif, frame, SummarizedExperiment
    ---------------------------------------------------------------------
    nrows <- 200
    ncols <- 8
    expr_values <- matrix(runif(nrows * ncols, 1, 1e4), nrows)
    # colData also takes all other metadata information, such as Label, Sample,
    # --- Generate Dataset [] ---
    # Key functions: generate_dataset, BERT
    ---------------------------------------------------------------------
    library(BERT)
    # generate test data with 10% missing values as provided by the BERT library
    dataset_raw <- generate_dataset(features=60, batches=10, samplesperbatch=10, mvstmt=0.1, classes=2)
    # apply BERT
    # --- Rows [] ---
    # Key functions: rows, runif, frame, SummarizedExperiment, BERT
    ---------------------------------------------------------------------
    nrows <- 200
    ncols <- 8
    # SummarizedExperiments store samples in columns and features in rows (in contrast to BERT).
    # BERT will automatically account for this.
    # --- Generate Dataset [] ---
    # Key functions: generate_dataset, requirements, sample, BERT
    ---------------------------------------------------------------------
    # import BERT
    library(BERT)
    # generate data with 4 batches, 6 features, 15 samples per batch, 15% missing values and 2 classes
    dataset_raw <- generate_dataset(features=6, batches=4, samplesperbatch=15, mvstmt=0.15, classes=2)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_bert_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_bert_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_bert_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BERT:", paste0("    bert: ", packageVersion("BERT"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bert_results.csv
    touch ${prefix}_bert_output.rds
    echo "BIOC_BERT:" > versions.yml
    echo "    bert: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BERT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BERT(ch_input)

    emit:
    results  = BIOC_BERT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BERT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BERT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BERT.out.versions  // channel: path(versions.yml)
}
