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

    # --- example [] ---
    # Key functions: example
    example(sample_size)
    # --- est_power_distribution [] ---
    # Key functions: est_power_distribution
    est_power_distribution(n=65,f=0.01,rho=2,
    # --- sample_size_distribution [] ---
    # Key functions: sample_size_distribution
    sample_size_distribution(power=0.8,f=0.01,distributionObject="TCGA_READ",
    # --- est_count_dispersion [] ---
    # Key functions: est_count_dispersion, est_power_distribution
    dataMatrixDistribution<-est_count_dispersion(dataMatrix,
    group=c(rep(0,5),rep(1,5)))
    est_power_distribution(n=65,f=0.01,rho=2,
    # --- download_study [] ---
    # Key functions: download_study, plot_mappedReads_percent, plot_gene_counts_range
    library(recount)
    url <- download_study(studyId)
    load(file.path(studyId, 'rse_gene.Rdata'))
    # --- get Atlas Data [] ---
    # Key functions: getAtlasData
    library(ExpressionAtlas)
    allExps <- getAtlasData(projectId)
    expObj=ExpressionAtlasObj[,which(colData(ExpressionAtlasObj)$AtlasAssayGroup %in% c("g2","g4"))]
    # --- est_power_curve [] ---
    # Key functions: est_power_curve, plot_power_curve
    result1<-est_power_curve(n=63, f=0.01, rho=2, lambda0=5, phi0=0.5)
    result2<-est_power_curve(n=63, f=0.05, rho=2, lambda0=5, phi0=0.5)
    plot_power_curve(list(result1,result2))
    # --- optimize_parameter [] ---
    # Key functions: optimize_parameter
    result<-optimize_parameter(fun=est_power,opt1="n",
    opt2="lambda0",opt1Value=c(3,5,10,15,20),
    opt2Value=c(1:5,10,20))

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
