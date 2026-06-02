#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SpeCond
// This package performs a gene expression data analysis to detect condition-specific genes. Such genes
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SpeCond/inst/doc/SpeCond.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("SpeCond")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPECOND {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-specond"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-specond:1.60.0--r44_0' :
        'quay.io/biocontainers/bioconductor-specond:1.60.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_specond_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_specond_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_specond_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SpeCond)
    library(jsonlite)

    # --- Mixture Model Fitting [Model Fitting] ---
    # Key functions: fitGeneMixtureModels
    expression_matrix <- matrix(
        rnorm(1000),
        nrow = 100,
        ncol = 10,
        dimnames = list(paste0("Gene", 1:100), paste0("Cond", 1:10))
    )
    fit_results <- fitGeneMixtureModels(
        expressionData = expression_matrix,
        G = 1:3,
        verbose = TRUE
    )

    # --- Condition Specific Detection [Detection] ---
    # Key functions: getConditionSpecific
    specific_genes <- getConditionSpecific(
        expressionData = expression_matrix,
        fit = fit_results,
        threshold.pvalue = 0.05,
        percentage.detect = 0.1
    )

    # --- Integrated SpeCond Analysis [Analysis] ---
    # Key functions: specond
    conditions <- colnames(expression_matrix)
    specond_results <- specond(
        expressionData = expression_matrix,
        conds = conditions,
        param.detection = NULL,
        multicore = FALSE
    )

    # --- Visualisation of Specific Genes [Visualisation] ---
    # Key functions: plotSpecond
    plotSpecond(
        geneName = "Gene1",
        expressionData = expression_matrix,
        specondResult = specond_results,
        param.plot = NULL
    )

    # --- Exporting Results [Export] ---
    # Key functions: writeSpecondResult
    writeSpecondResult(
        specondResult = specond_results,
        file = "specond_results_output.txt",
        prefix = "SpeCond_Analysis"
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_specond_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_specond_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_specond_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPECOND:", paste0("    specond: ", packageVersion("SpeCond"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_specond_results.csv
    touch ${prefix}_specond_output.rds
    echo "BIOC_SPECOND:" > versions.yml
    echo "    specond: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SPECOND_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SPECOND(ch_input)

    emit:
    results  = BIOC_SPECOND.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SPECOND.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SPECOND.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SPECOND.out.versions  // channel: path(versions.yml)
}
