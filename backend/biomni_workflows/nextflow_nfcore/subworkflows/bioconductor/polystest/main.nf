#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: PolySTest
// The complexity of high-throughput quantitative omics experiments often leads to low replicates numbe
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/PolySTest/inst/doc/StatisticalTest.R
// Upstream  : SummarizedExperiment
// Downstream: none
//
// Install: BiocManager::install("PolySTest")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_POLYSTEST {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-polystest"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-polystest:1.0.2--r44_0' :
        'quay.io/biocontainers/bioconductor-polystest:1.0.2--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_polystest_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_polystest_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_polystest_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Normalization)
    library(PolySTest_unpaired)
    library(SummarizedExperiment)
    library(jsonlite)

    # --- Normalization [] ---
    # Key functions: Normalization, colMedians
    ---------------------------------------------------------------------
    # Normalization (example)
    dat <- t(t(dat) - colMedians(as.matrix(dat), na.rm = TRUE))
    # --- Frame [] ---
    # Key functions: frame, SummarizedExperiment, rowData, metadata
    ---------------------------------------------------------------------
    sampleMetadata <- data.frame(Condition = rep(paste("Condition", 1:4), each=3),
                                 Replicate = rep(1:3, each=4))
    fulldata <- SummarizedExperiment(assays = list(quant = dat),
                                     colData = sampleMetadata)
    # --- Unique [] ---
    # Key functions: colData, create_pairwise_comparisons
    ---------------------------------------------------------------------
    conditions <- unique(colData(fulldata)$Condition)
    allComps <- create_pairwise_comparisons(conditions, 1)
    # --- Polystest Unpaired [] ---
    # Key functions: PolySTest_unpaired
    ---------------------------------------------------------------------
    fulldata_unpaired <- PolySTest_unpaired(fulldata, allComps)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_polystest_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_polystest_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_polystest_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_POLYSTEST:", paste0("    polystest: ", packageVersion("PolySTest"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_polystest_results.csv
    touch ${prefix}_polystest_output.rds
    echo "BIOC_POLYSTEST:" > versions.yml
    echo "    polystest: 0.0.0" >> versions.yml
    """
}


workflow BIOC_POLYSTEST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_POLYSTEST(ch_input)

    emit:
    results  = BIOC_POLYSTEST.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_POLYSTEST.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_POLYSTEST.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_POLYSTEST.out.versions  // channel: path(versions.yml)
}
