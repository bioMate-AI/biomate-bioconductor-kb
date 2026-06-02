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
    library(PrintBibliography)
    library(TreeSummarizedExperiment)
    library(jsonlite)

    # --- "install" [] ---
    # Key functions: valid

    # --- "pairedTimes" [] ---
    # Key functions: pairedTimes
    times <- pairedTimes(data = clr, sequential = TRUE, common = "_0_")
    # --- "makeObject" [] ---
    # Key functions: TreeSummarizedExperiment, altExp, assayNames
    ID_common_time <- rownames(clr)
    samples <- 1:dim(clr)[1]
    # --- "pairedTimesTSE" [] ---
    # Key functions: pairedTimes

    # --- "iterativeClustering" [] ---
    # Key functions: iterativeClustering
    mS <- iterativeClustering(pairedTimes = times, common = "_")
    # --- "iterativeClusteringTSE" [] ---
    # Key functions: iterativeClustering
    mS_TSE <- iterativeClustering(pairedTimes = TSE_times, common = "_")
    # --- "visualization" [] ---
    # Key functions: mSpreviz, plotmSscatter, plotmSheatmap
    results <- mSpreviz(results = mS, times = times)
    # --- "CV" [] ---
    # Key functions: bpmapply

    # --- "error" [] ---
    # Key functions: mSerrorCV

    # --- "error viz" [] ---
    # Key functions: mSpreviz, plotmSheatmap
    MAE <- mSpreviz(results = list(MAE_t1_t25), times = list(t1_t25 = times$t1_t25))
    # --- "lines" [] ---
    # Key functions: plotmSlinesCV
    plotmSlinesCV(pairedTime = times$t1_t25, CVklist = cv_klist_k2[[1]], k = 2L)
    # --- "metadata" [] ---
    # Key functions: mSmetadataGroups, plotmSdynamics
    metadata <- data.frame(Sample = rownames(clr), age = c(rep("youth", 65),
    rep("old", 131-65)))
    # --- knit [] ---
    # Key functions: knit
    library("rmarkdown")
    system.time(render("microSTASIS.Rmd", "BiocStyle::html_document"))
    library("knitr")
    # --- diff [] ---
    # Key functions: diff
    totalTime <- diff(c(startTime, Sys.time()))
    round(totalTime, digits = 3)
    # --- session_info [] ---
    # Key functions: session_info
    library("sessioninfo")
    options(width = 120)
    session_info()

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
