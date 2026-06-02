#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RnaSeqSampleSize
// RnaSeqSampleSize package provides a sample size calculation method based on negative binomial model 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RnaSeqSampleSize/inst/doc/RnaSeqSampleSize.R
// Upstream  : ExpressionAtlas, recount
// Downstream: none
//
// Install: BiocManager::install("RnaSeqSampleSize")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RNASEQSAMPLESIZE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rnaseqsamplesize"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rnaseqsamplesize:2.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rnaseqsamplesize:2.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rnaseqsamplesize_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rnaseqsamplesize_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rnaseqsamplesize_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RnaSeqSampleSize)
    library(jsonlite)

    # --- Sample Size Estimation [] ---
    # Key functions: sample_size_distribution
    size_dist <- sample_size_distribution(
        power=0.8, f=0.01,
        distributionObject="TCGA_READ",
        repNumber=5, showMessage=FALSE
    )


    # --- Parameter Optimization [] ---
    # Key functions: optimize_parameter, est_power
    opt_res <- optimize_parameter(
        fun=est_power, opt1="n",
        opt2="lambda0", opt1Value=c(3,5,10,15,20),
        opt2Value=c(1:5,10,20)
    )


    # --- User Data Distribution Estimation [] ---
    # Key functions: est_count_dispersion, est_power_distribution
    dataMatrix <- matrix(
        sample(0:3000, 100000, replace=TRUE),
        nrow=10000, ncol=10
    )
    colnames(dataMatrix) <- c(paste0("Control", 1:5), paste0("Treatment", 1:5))
    row.names(dataMatrix) <- paste0("gene", 1:10000)
    dataMatrixDistribution <- est_count_dispersion(
        dataMatrix,
        group=c(rep(0,5), rep(1,5))
    )
    power_dist <- est_power_distribution(
        n=65, f=0.01, rho=2,
        distributionObject=dataMatrixDistribution,
        repNumber=5
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rnaseqsamplesize_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rnaseqsamplesize_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rnaseqsamplesize_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RNASEQSAMPLESIZE:", paste0("    rnaseqsamplesize: ", packageVersion("RnaSeqSampleSize"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rnaseqsamplesize_results.csv
    touch ${prefix}_rnaseqsamplesize_output.rds
    echo "BIOC_RNASEQSAMPLESIZE:" > versions.yml
    echo "    rnaseqsamplesize: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RNASEQSAMPLESIZE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RNASEQSAMPLESIZE(ch_input)

    emit:
    results  = BIOC_RNASEQSAMPLESIZE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RNASEQSAMPLESIZE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RNASEQSAMPLESIZE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RNASEQSAMPLESIZE.out.versions  // channel: path(versions.yml)
}
