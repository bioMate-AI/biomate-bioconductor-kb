#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: moanin
// Simple and efficient workflow for time-course gene expression data, built on publictly available ope
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/moanin/inst/doc/documentation.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("moanin")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MOANIN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-moanin"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-moanin:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-moanin:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_moanin_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_moanin_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_moanin_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(moanin)
    library(jsonlite)

    # --- Contrast Construction [] ---
    # Key functions: create_timepoints_contrasts
    preContrasts <- create_timepoints_contrasts(
        moaninObject, "Preflowering", "Control"
    )
    postContrasts <- create_timepoints_contrasts(
        moaninObject, "Postflowering", "Control"
    )
    preGroupDiffContrasts <- create_timepoints_contrasts(
        moaninObject, "Preflowering", "Control",
        type = "group_and_timepoint_diff"
    )


    # --- Differential Expression Analysis [] ---
    # Key functions: DE_timepoints, DE_timecourse, estimate_log_fold_change
    weeklyPre <- DE_timepoints(
        moaninObject[1:500, ],
        contrasts = c(preContrasts, postContrasts),
        use_voom_weights = TRUE
    )
    timecourseContrasts <- c(
        "Preflowering-Control",
        "Postflowering-Control"
    )
    splinePre <- DE_timecourse(
        moaninObject[1:500, ],
        contrasts = timecourseContrasts,
        use_voom_weights = TRUE
    )
    log_fold_change_timepoints <- estimate_log_fold_change(
        moaninObject[1:500, ],
        contrasts = timecourseContrasts,
        method = "sum"
    )


    # --- Timecourse Clustering [] ---
    # Key functions: splines_kmeans, splines_kmeans_score_and_label
    kmeans_clusters <- splines_kmeans(
        moaninObject[1:500, ],
        n_clusters = 3,
        random_seed = 42,
        n_init = 20
    )
    scores_and_labels <- splines_kmeans_score_and_label(
        object = moaninObject,
        data = preData[1:500, ],
        kmeans_clusters = kmeans_clusters
    )


    # --- Visualization [] ---
    # Key functions: plot_splines_data
    whSig <- which(splinePre[, "Preflowering-Control_qval"] < 0.05)
    deGenes <- order(
        abs(log_fold_change_timepoints)[whSig, "Preflowering-Control"],
        decreasing = TRUE
    )[1:10]
    plot_splines_data(
        moaninObject[whSig, ][deGenes, ],
        smooth = TRUE
    )
    plot_splines_data(
        data = kmeans_clusters$centroids,
        moaninObject,
        smooth = TRUE
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_moanin_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_moanin_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_moanin_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MOANIN:", paste0("    moanin: ", packageVersion("moanin"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_moanin_results.csv
    touch ${prefix}_moanin_output.rds
    echo "BIOC_MOANIN:" > versions.yml
    echo "    moanin: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MOANIN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MOANIN(ch_input)

    emit:
    results  = BIOC_MOANIN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MOANIN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MOANIN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MOANIN.out.versions  // channel: path(versions.yml)
}
