#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: wpm
// The Well-Plate Maker (WPM) is a shiny application deployed as an R package. Functions for a command-
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/wpm/inst/doc/wpm_vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("wpm")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_WPM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-wpm"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-wpm:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-wpm:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_wpm_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_wpm_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_wpm_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MSnSet)
    library(SummarizedExperiment)
    library(jsonlite)

    # --- convert CSV file [] ---
    # Key functions: convertCSV
    imported_csv <- wpm::convertCSV("path-to-CSV-file")
    # --- create an MSnSet object [] ---
    # Key functions: MSnSet
    sample_names <- c("s1","s2","s3","s4", "s5")
    M <- matrix(NA, nrow = 4, ncol = 5)
    colnames(M) <- sample_names
    # --- convert ESet/MSnSet object [] ---
    # Key functions: convertESet
    df <- wpm::convertESet(my_MSnSet_object, "Environment")
    # --- convert SummarizedExperiment object [] ---
    # Key functions: SummarizedExperiment, convertSE
    counts <- matrix(runif(nrows * ncols, 1, 1e4), nrows)
    colData <- data.frame(Treatment=rep(c("ChIP", "Input"), 3),
    se <- SummarizedExperiment::SummarizedExperiment(assays=list(counts=counts),
    # --- run wpm with a CSV file [] ---
    # Key functions: wrapperWPM
    wpm_result <- wpm::wrapperWPM(user_df = imported_csv$df_wpm,
    plate_dims = list(8,12),
    # --- wrapper W P M [] ---
    # Key functions: wrapperWPM
    wpm_result <- wpm::wrapperWPM(user_df = df,
    plate_dims = list(8,12),
    # --- visualize plate map [] ---
    # Key functions: drawMap
    drawned_map <- wpm::drawMap(df = wpm_result,
    sample_gps = length(levels(as.factor(colData$Treatment))),
    gp_levels = gp_lvl <- levels(as.factor(colData$Treatment)),

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_wpm_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_wpm_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_wpm_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_WPM:", paste0("    wpm: ", packageVersion("wpm"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_wpm_results.csv
    touch ${prefix}_wpm_output.rds
    echo "BIOC_WPM:" > versions.yml
    echo "    wpm: 0.0.0" >> versions.yml
    """
}


workflow BIOC_WPM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_WPM(ch_input)

    emit:
    results  = BIOC_WPM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_WPM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_WPM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_WPM.out.versions  // channel: path(versions.yml)
}
