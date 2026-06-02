#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: TrajectoryGeometry
// Given a time series or pseudo-times series of gene expression data, we might wish to know: Do the ch
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/TrajectoryGeometry/inst/doc/SingleCellTrajectoryAnalysis.R
// Upstream  : RColorBrewer, dplyr, ggplot2
// Downstream: none
//
// Install: BiocManager::install("TrajectoryGeometry")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TRAJECTORYGEOMETRY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-trajectorygeometry"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-trajectorygeometry:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-trajectorygeometry:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_trajectorygeometry_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_trajectorygeometry_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_trajectorygeometry_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(TrajectoryGeometry)
    library(jsonlite)

    # --- Path Sampling and Directionality Testing [] ---
    # Key functions: samplePath, testPathForDirectionality
    chol_path <- samplePath(chol_attr, chol_pt_norm)
    chol_perm <- testPathForDirectionality(
        chol_path[, 1:3],
        randomizationParams = c("byPermutation", "permuteWithinColumns"),
        statistic = "mean",
        N = 100
    )


    # --- Trajectory Analysis and Visualization [] ---
    # Key functions: analyseSingleCellTrajectory, visualiseTrajectoryStats
    chol_ans <- analyseSingleCellTrajectory(
        attributes = chol_attr[, 1:3],
        pseudotime = chol_pt_norm,
        randomizationParams = c("byPermutation", "permuteWithinColumns"),
        statistic = "mean",
        nSamples = 100,
        N = 1
    )
    chol_dist <- visualiseTrajectoryStats(chol_ans, "distance")
    plot_dist <- chol_dist$plot


    # --- Branch Point Analysis [] ---
    # Key functions: analyseBranchPoint, visualiseBranchPointStats
    chol_bp <- analyseBranchPoint(
        chol_attr[, 1:3],
        chol_pt,
        randomizationParams = c("byPermutation", "permuteWithinColumns"),
        statistic = "mean",
        start = 0,
        stop = 50,
        step = 5,
        nSamples = 100,
        N = 1
    )
    bp_stats <- visualiseBranchPointStats(chol_bp)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_trajectorygeometry_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_trajectorygeometry_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_trajectorygeometry_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TRAJECTORYGEOMETRY:", paste0("    trajectorygeometry: ", packageVersion("TrajectoryGeometry"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_trajectorygeometry_results.csv
    touch ${prefix}_trajectorygeometry_output.rds
    echo "BIOC_TRAJECTORYGEOMETRY:" > versions.yml
    echo "    trajectorygeometry: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TRAJECTORYGEOMETRY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TRAJECTORYGEOMETRY(ch_input)

    emit:
    results  = BIOC_TRAJECTORYGEOMETRY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TRAJECTORYGEOMETRY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TRAJECTORYGEOMETRY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TRAJECTORYGEOMETRY.out.versions  // channel: path(versions.yml)
}
