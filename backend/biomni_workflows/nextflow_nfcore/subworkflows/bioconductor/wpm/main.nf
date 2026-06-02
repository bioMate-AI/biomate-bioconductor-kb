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
    library(wpm)
    library(MSnSet)
    library(SummarizedExperiment)
    library(jsonlite)

    # --- Plate Layout Generation [] ---
    # Key functions: wrapperWPM
    wpm_result <- wrapperWPM(
        user_df = df,
        plate_dims = list(8, 12),
        nb_plates = 1,
        forbidden_wells = "A1,A2",
        fixed_wells = "B1",
        spatial_constraint = "NS"
    )


    # --- Plate Map Visualization [] ---
    # Key functions: drawMap
    drawn_map <- drawMap(
        df = wpm_result,
        sample_gps = 2,
        gp_levels = c("ChIP", "Input"),
        plate_lines = 8,
        plate_cols = 12,
        project_title = "ChIP-Seq Plate Layout"
    )

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
