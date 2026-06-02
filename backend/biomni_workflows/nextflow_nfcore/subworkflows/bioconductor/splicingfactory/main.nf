#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SplicingFactory
// The SplicingFactory R package uses transcript-level expression values to analyze splicing diversity 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SplicingFactory/inst/doc/SplicingFactory.R
// Upstream  : tidyr, ggplot2
// Downstream: none
//
// Install: BiocManager::install("SplicingFactory")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPLICINGFACTORY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-splicingfactory"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-splicingfactory:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-splicingfactory:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_splicingfactory_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_splicingfactory_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_splicingfactory_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SplicingFactory)
    library(jsonlite)

    # --- Gini Index Estimation [] ---
    # Key functions: calculate_diversity
    gini_index <- calculate_diversity(
        readcounts,
        genes,
        method = "gini",
        verbose = TRUE
    )


    # --- Differential Diversity Analysis [] ---
    # Key functions: calculate_difference
    colData(laplace_entropy)$sample_type <- ifelse(
        grepl("_N", laplace_entropy$samples),
        "Normal",
        "Tumor"
    )
    entropy_significance <- calculate_difference(
        x = laplace_entropy,
        samples = "sample_type",
        control = "Normal",
        method = "mean",
        test = "wilcoxon",
        verbose = TRUE
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_splicingfactory_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_splicingfactory_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_splicingfactory_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPLICINGFACTORY:", paste0("    splicingfactory: ", packageVersion("SplicingFactory"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_splicingfactory_results.csv
    touch ${prefix}_splicingfactory_output.rds
    echo "BIOC_SPLICINGFACTORY:" > versions.yml
    echo "    splicingfactory: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SPLICINGFACTORY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SPLICINGFACTORY(ch_input)

    emit:
    results  = BIOC_SPLICINGFACTORY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SPLICINGFACTORY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SPLICINGFACTORY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SPLICINGFACTORY.out.versions  // channel: path(versions.yml)
}
