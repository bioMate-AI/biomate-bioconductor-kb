#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: LiquidAssociation
// The package contains functions for calculate direct and model-based estimators for liquid associatio
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/LiquidAssociation/inst/doc/LiquidAssociation.R
// Upstream  : yeastCC
// Downstream: fastLiquidAssociation
//
// Install: BiocManager::install("LiquidAssociation")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_LIQUIDASSOCIATION {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-liquidassociation"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-liquidassociation:1.60.0--r44_0' :
        'quay.io/biocontainers/bioconductor-liquidassociation:1.60.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_liquidassociation_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_liquidassociation_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_liquidassociation_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(LiquidAssociation)
    library(GLA)
    library(LA)
    library(jsonlite)

    # --- Data Preprocessing and Standardization [Preprocessing] ---
    # Key functions: qqnorm2, stand
    # Standardize and normalize the triplet expression data
    # Input 'data' is a matrix of gene expression triplets
    norm_data <- apply(data, 2, qqnorm2)
    std_data <- apply(norm_data, 2, stand)
    colnames(std_data) <- colnames(data)
    saveRDS(std_data, file = "standardized_data.rds")

    # --- Liquid Association Estimation [Estimation] ---
    # Key functions: GLA
    # Calculate Liquid Association (LA) score for ExpressionSet
    # 'eSetdata' is an ExpressionSet, 'geneMap' is a named vector mapping probes
    la_result <- GLA(eSetdata, cut = 4, dim = 3, geneMap = geneMap)
    saveRDS(la_result, file = "gla_expression_set_results.rds")

    # --- Conditional Normal Model Fitting [Model Fitting] ---
    # Key functions: CNM.full
    # Fit the Conditional Normal Model (CNM) to the standardized triplet data
    # This model tests the liquid association of the gene triplet
    cnm_fit <- CNM.full(std_data)
    saveRDS(cnm_fit, file = "cnm_model_fit.rds")

    # --- Significance Testing [Significance] ---
    # Key functions: getsGLA
    # Estimate the significance of the GLA score using bootstrap and permutation
    sgla_res <- getsGLA(std_data, boots = 20, perm = 50, cut = 4, dim = 3)
    saveRDS(sgla_res, file = "sgla_significance_testing.rds")

    # --- Visualization [Visualisation] ---
    # Key functions: plotGLA
    # Generate a 3D plot of the liquid association for the gene triplet
    # Saves the plot to a file named 'GLA_plot'
    plotGLA(std_data, cut = 3, dim = 3, pch = 16, filen = "GLA_plot", save = TRUE)


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_liquidassociation_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_liquidassociation_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_liquidassociation_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_LIQUIDASSOCIATION:", paste0("    liquidassociation: ", packageVersion("LiquidAssociation"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_liquidassociation_results.csv
    touch ${prefix}_liquidassociation_output.rds
    echo "BIOC_LIQUIDASSOCIATION:" > versions.yml
    echo "    liquidassociation: 0.0.0" >> versions.yml
    """
}


workflow BIOC_LIQUIDASSOCIATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_LIQUIDASSOCIATION(ch_input)

    emit:
    results  = BIOC_LIQUIDASSOCIATION.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_LIQUIDASSOCIATION.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_LIQUIDASSOCIATION.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_LIQUIDASSOCIATION.out.versions  // channel: path(versions.yml)
}
