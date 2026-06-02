#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: bayNorm
// bayNorm is used for normalizing single-cell RNA-seq data.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/bayNorm/inst/doc/bayNorm.R
// Upstream  : BiocManager, BiocStyle, MAST, SingleCellExperiment, SummarizedExperiment
// Downstream: none
//
// Install: BiocManager::install("bayNorm")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BAYNORM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-baynorm"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-baynorm:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-baynorm:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(singlecellexperiment)

    output:
    tuple val(meta), path("${meta.id}_baynorm_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_baynorm_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_baynorm_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(bayNorm)
    library(BetaFun)
    library(SCnorm_runMAST)
    library(SCnorm_runMAST3)
    library(SingleCellExperiment)
    library(SummarizedExperiment)
    library(jsonlite)

    # --- Bayesian Normalization (3D Array) [] ---
    # Key functions: bayNorm
    bayNorm_3D <- bayNorm(
        Data=rse,
        BETA_vec=beta_vector,
        mode_version=FALSE,
        mean_version=FALSE,
        S=20,
        verbose=FALSE,
        parallel=FALSE
    )


    # --- Bayesian Normalization (2D Matrix) [] ---
    # Key functions: bayNorm_sup
    bayNorm_2D_mean <- bayNorm_sup(
        Data=rse,
        PRIORS=bayNorm_3D$PRIORS,
        input_params=bayNorm_3D$input_params,
        mode_version=FALSE,
        mean_version=TRUE,
        verbose=FALSE
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_baynorm_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_baynorm_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_baynorm_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BAYNORM:", paste0("    baynorm: ", packageVersion("bayNorm"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_baynorm_results.csv
    touch ${prefix}_baynorm_output.rds
    echo "BIOC_BAYNORM:" > versions.yml
    echo "    baynorm: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BAYNORM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(singlecellexperiment) ]

    main:
    BIOC_BAYNORM(ch_input)

    emit:
    results  = BIOC_BAYNORM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BAYNORM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BAYNORM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BAYNORM.out.versions  // channel: path(versions.yml)
}
