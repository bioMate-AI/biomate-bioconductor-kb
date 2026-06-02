#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: hdxmsqc
// The hdxmsqc package enables us to analyse and visualise the quality of HDX-MS experiments. Either as
//
// Source : https://bioconductor.org/packages/3.20/bioc/https://bioconductor.org/packages/3.20/bioc/vignettes/hdxmsqc/inst/doc/qc-streamlined.html
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("hdxmsqc")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HDXMSQC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-hdxmsqc"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-hdxmsqc:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-hdxmsqc:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_hdxmsqc_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_hdxmsqc_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_hdxmsqc_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(hdxmsqc)
    library(jsonlite)

    # --- Missing Value Filtering and Imputation [] ---
    # Key functions: isMissingAtRandom, impute
    BRD4df_filtered <- isMissingAtRandom(object = BRD4df)
    BRD4df_filtered_imputed <- impute(
        BRD4df_filtered,
        method = "zero",
        i = 1
    )


    # --- Mass Error and Intensity Outlier Analysis [] ---
    # Key functions: computeMassError, plotMassError, intensityOutliers, plotIntensityOutliers
    massError <- computeMassError(object = BRD4df_filtered_imputed)
    plotMassError(object = BRD4df_filtered_imputed)
    intensityOutlier <- intensityOutliers(object = BRD4df_filtered_imputed)
    plotIntensityOutliers(object = BRD4df_filtered_imputed)


    # --- Retention Time and Monotonicity Analysis [] ---
    # Key functions: rTimeOutliers, plotrTimeOutliers, computeMonotoneStats, plotMonotoneStat
    dfrt <- rTimeOutliers(object = BRD4df_filtered_imputed)
    plotrTimeOutliers(object = BRD4df_filtered_imputed)
    experiment <- c("wt", "iBET")
    timepoints <- rep(c(0, 15, 60, 600, 3600, 14000), each = 3)
    monoStat <- computeMonotoneStats(
        object = BRD4df_filtered_imputed,
        experiment = experiment,
        timepoints = timepoints
    )


    # --- Correlation and Replicate Analysis [] ---
    # Key functions: imTimeOutlier, chargeCorrelationHdx, replicateCorrelation, replicateOutlier
    imTimeOut <- imTimeOutlier(object = BRD4df_filtered_imputed)
    csCor <- chargeCorrelationHdx(
        object = BRD4df_filtered_imputed,
        experiment = experiment,
        timepoints = timepoints
    )
    replicateVar <- replicateCorrelation(
        object = BRD4df_filtered_imputed,
        experiment = experiment,
        timepoints = timepoints
    )
    replicateOut <- replicateOutlier(
        object = BRD4df_filtered_imputed,
        experiment = experiment,
        timepoints = timepoints
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_hdxmsqc_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_hdxmsqc_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_hdxmsqc_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HDXMSQC:", paste0("    hdxmsqc: ", packageVersion("hdxmsqc"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hdxmsqc_results.csv
    touch ${prefix}_hdxmsqc_output.rds
    echo "BIOC_HDXMSQC:" > versions.yml
    echo "    hdxmsqc: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HDXMSQC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HDXMSQC(ch_input)

    emit:
    results  = BIOC_HDXMSQC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HDXMSQC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HDXMSQC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HDXMSQC.out.versions  // channel: path(versions.yml)
}
