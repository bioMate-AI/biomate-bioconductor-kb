#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: sigFeature
// This package provides a novel feature selection algorithm for binary classification using support ve
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/sigFeature/inst/doc/vignettes.R
// Upstream  : SummarizedExperiment, e1071, pheatmap, RColorBrewer
// Downstream: none
//
// Install: BiocManager::install("sigFeature")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SIGFEATURE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sigfeature"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-sigfeature:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-sigfeature:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_sigfeature_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sigfeature_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sigfeature_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(sigFeature)
    library(jsonlite)


    # --- Cars [] ---
    # Key functions: assays, colData, sigFeaturePvalue, unlist, sigFeature, skyblue
    library(sigFeature)
    library(SummarizedExperiment)
    data(ExampleRawData, package="sigFeature")
    ExampleRawData   

    ## -----------------------------------------------------------------------------
    x  <- t(assays(ExampleRawData)$counts)
    y  <- colData(ExampleRawData)$sampleLabels

    ## -----------------------------------------------------------------------------
    pvals <- sigFeaturePvalue(x,y)
    hist(unlist(pvals),breaks=seq(0,0.08,0.0015),col="skyblue",
        xlab="p value",ylab="Frequency",main="")

    ## -----------------------------------------------------------------------------

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_sigfeature_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_sigfeature_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_sigfeature_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SIGFEATURE:", paste0("    sigfeature: ", packageVersion("sigFeature"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sigfeature_results.csv
    touch ${prefix}_sigfeature_output.rds
    echo "BIOC_SIGFEATURE:" > versions.yml
    echo "    sigfeature: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SIGFEATURE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SIGFEATURE(ch_input)

    emit:
    results  = BIOC_SIGFEATURE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SIGFEATURE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SIGFEATURE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SIGFEATURE.out.versions  // channel: path(versions.yml)
}
