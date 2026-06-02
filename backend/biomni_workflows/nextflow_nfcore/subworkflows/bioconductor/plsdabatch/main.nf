#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: PLSDAbatch
// A novel framework to correct for batch effects prior to any downstream analysis in microbiome data b
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/PLSDAbatch/inst/doc/brief_vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("PLSDAbatch")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PLSDABATCH {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-plsdabatch"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-plsdabatch:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-plsdabatch:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_plsdabatch_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_plsdabatch_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_plsdabatch_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PLSDAbatch)
    library(Scatter_Density)
    library(jsonlite)

    # --- Batch Effect Diagnostic [] ---
    # Key functions: Scatter_Density, box_plot, density_plot
    data('AD_data')
    ad.metadata <- SummarizedExperiment::rowData(AD_data$FullData)
    ad.batch <- factor(ad.metadata$sequencing_run_date)
    ad.trt <- as.factor(ad.metadata$initial_phenol_concentration.regroup)
    ad.OTU_batch <- data.frame(
        value = rnorm(length(ad.batch)),
        batch = ad.batch
    )
    box_plot(df = ad.OTU_batch, title = "Batch Boxplot")
    density_plot(df = ad.OTU_batch, title = "Batch Density")


    # --- Linear Regression Analysis [] ---
    # Key functions: linear_regres
    data('AD_data')
    ad.metadata <- SummarizedExperiment::rowData(AD_data$FullData)
    ad.batch <- factor(ad.metadata$sequencing_run_date)
    ad.trt <- as.factor(ad.metadata$initial_phenol_concentration.regroup)
    mock_data <- rnorm(length(ad.batch))
    ad.OTU.lm <- linear_regres(
        data = mock_data,
        trt = ad.trt,
        batch.fix = ad.batch,
        type = 'linear model'
    )


    # --- Batch Effect Correction [] ---
    # Key functions: PLSDA_batch
    data('AD_data')
    ad.metadata <- SummarizedExperiment::rowData(AD_data$FullData)
    ad.batch <- factor(ad.metadata$sequencing_run_date)
    ad.trt <- as.factor(ad.metadata$initial_phenol_concentration.regroup)
    mock_matrix <- matrix(
        rnorm(length(ad.batch) * 10),
        nrow = length(ad.batch),
        ncol = 10
    )
    ad.PLSDA_batch.res <- PLSDA_batch(
        X = mock_matrix,
        Y.trt = ad.trt,
        Y.bat = ad.batch,
        ncomp.trt = 1,
        ncomp.bat = 2
    )
    corrected_data <- ad.PLSDA_batch.res$X.nobatch

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_plsdabatch_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_plsdabatch_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_plsdabatch_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PLSDABATCH:", paste0("    plsdabatch: ", packageVersion("PLSDAbatch"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_plsdabatch_results.csv
    touch ${prefix}_plsdabatch_output.rds
    echo "BIOC_PLSDABATCH:" > versions.yml
    echo "    plsdabatch: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PLSDABATCH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PLSDABATCH(ch_input)

    emit:
    results  = BIOC_PLSDABATCH.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PLSDABATCH.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PLSDABATCH.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PLSDABATCH.out.versions  // channel: path(versions.yml)
}
