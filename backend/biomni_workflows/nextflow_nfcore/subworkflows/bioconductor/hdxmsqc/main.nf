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

    # --- Code Block 1 [] ---
    # Key functions: frame, csv
    BRD4uncurated <- data.frame(read.csv(system.file("extdata", "ELN55049_AllResultsTables_Uncurated.csv", package = "hdxmsqc", mustWork = TRUE)))
    # --- Code Block 2 [] ---
    # Key functions: processHDE
    BRD4uncurated_wide <- processHDE(HDExaminerFile = BRD4uncurated,
                                     proteinStates = c("wt", "iBET"))
    # --- Code Block 4 [] ---
    # Key functions: readQFeatures
    BRD4df <- readQFeatures(assayData = BRD4uncurated_wide,
                            ecol = i,
                            names = "Deuteration",
                            fnames = "fnames")
    # --- Code Block 5 [] ---
    # Key functions: isMissingAtRandom
    BRD4df_filtered <- isMissingAtRandom(object = BRD4df)
    # --- Code Block 6 [] ---
    # Key functions: impute
    BRD4df_filtered_imputed <- impute(BRD4df_filtered, method = "zero", i = 1)
    # --- Code Block 7 [] ---
    # Key functions: computeMassError, plotMassError
    massError <- computeMassError(object = BRD4df_filtered_imputed)
    plotMassError(object = BRD4df_filtered_imputed)
    # --- Code Block 8 [] ---
    # Key functions: geom_point
    ## Warning: Removed 8 rows containing missing values or values outside the scale range
    ## (`geom_point()`).
    # --- Code Block 9 [] ---
    # Key functions: intensityOutliers, plotIntensityOutliers
    intensityOutlier <- intensityOutliers(object = BRD4df_filtered_imputed)
    plotIntensityOutliers(object = BRD4df_filtered_imputed)
    # --- Code Block 10 [] ---
    # Key functions: rTimeOutliers, plotrTimeOutliers
    dfrt <- rTimeOutliers(object = BRD4df_filtered_imputed)
    plotrTimeOutliers(object = BRD4df_filtered_imputed)
    # --- Code Block 11 [] ---
    # Key functions: rep
    experiment <- c("wt", "iBET")
    timepoints <- rep(c(0, 15, 60, 600, 3600, 14000), each = 3)
    # --- Code Block 12 [] ---
    # Key functions: computeMonotoneStats, plotMonotoneStat
    monoStat <- computeMonotoneStats(object = BRD4df_filtered_imputed,
                                     experiment = experiment,
                                     timepoints = timepoints)
    # --- Code Block 13 [] ---
    # Key functions: imTimeOutlier, plotImTimeOutlier
    imTimeOut <- imTimeOutlier(object = BRD4df_filtered_imputed)
    plotImTimeOutlier(object = BRD4df_filtered_imputed)
    # --- Code Block 14 [] ---
    # Key functions: chargeCorrelationHdx
    csCor <- chargeCorrelationHdx(object = BRD4df_filtered_imputed,
                                  experiment = experiment,
                                  timepoints = timepoints)
    csCor
    # --- Code Block 15 [] ---
    # Key functions: replicateCorrelation, replicateOutlier
    replicateVar <- replicateCorrelation(object = BRD4df_filtered_imputed,
                                         experiment = experiment,
                                         timepoints = timepoints)

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
