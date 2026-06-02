#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: microSTASIS
// The toolkit 'µSTASIS', or microSTASIS, has been developed for the stability analysis of microbiota i
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/microSTASIS/inst/doc/microSTASIS.R
// Upstream  : RefManageR, TreeSummarizedExperiment, rmarkdown, knitr, sessioninfo
// Downstream: none
//
// Install: BiocManager::install("microSTASIS")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MICROSTASIS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-microstasis"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-microstasis:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-microstasis:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_microstasis_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_microstasis_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_microstasis_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(microSTASIS)
    library(PrintBibliography)
    library(TreeSummarizedExperiment)
    library(jsonlite)

    # --- Iterative Clustering [] ---
    # Key functions: iterativeClustering, mSpreviz
    mS <- iterativeClustering(
        pairedTimes = times,
        common = "_"
    )
    results <- mSpreviz(
        results = mS,
        times = times
    )


    # --- Stability Visualization [] ---
    # Key functions: plotmSscatter, plotmSheatmap
    plotmSscatter(
        results = results,
        order = "median",
        times = c("t1_t25", "t25_t26"),
        gridLines = TRUE,
        sideScale = 0.2
    )
    plotmSheatmap(
        results = results,
        order = "mean",
        times = c("t1_t25", "t25_t26"),
        label = TRUE
    )


    # --- Cross Validation [] ---
    # Key functions: iterativeClusteringCV, mSerrorCV, plotmSlinesCV
    cv_klist_k2 <- BiocParallel::bpmapply(
        iterativeClusteringCV,
        name = names(times),
        k = rep(2L, 3),
        MoreArgs = list(
            pairedTimes = times,
            results = mS,
            common = "_0_"
        )
    )
    MAE_t1_t25 <- mSerrorCV(
        pairedTime = times$t1_t25,
        CVklist = cv_klist_k2[[1]],
        k = 2L
    )
    plotmSlinesCV(
        pairedTime = times$t1_t25,
        CVklist = cv_klist_k2[[1]],
        k = 2L
    )


    # --- Metadata Group Dynamics [] ---
    # Key functions: mSmetadataGroups, plotmSdynamics
    metadata <- data.frame(
        Sample = rownames(clr),
        age = c(rep("youth", 65), rep("old", 131 - 65))
    )
    group <- mSmetadataGroups(
        metadata = metadata,
        samples = metadata$Sample,
        common = "_0_",
        individuals = results$individual,
        variable = "age"
    )
    plotmSdynamics(
        results,
        groups = group,
        points = TRUE,
        linetype = 0
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_microstasis_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_microstasis_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_microstasis_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MICROSTASIS:", paste0("    microstasis: ", packageVersion("microSTASIS"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_microstasis_results.csv
    touch ${prefix}_microstasis_output.rds
    echo "BIOC_MICROSTASIS:" > versions.yml
    echo "    microstasis: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MICROSTASIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MICROSTASIS(ch_input)

    emit:
    results  = BIOC_MICROSTASIS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MICROSTASIS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MICROSTASIS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MICROSTASIS.out.versions  // channel: path(versions.yml)
}
