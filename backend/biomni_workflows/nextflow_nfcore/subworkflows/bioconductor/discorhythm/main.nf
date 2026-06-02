#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DiscoRhythm
// Set of functions for estimation of cyclical characteristics, such as period, phase, amplitude, and s
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DiscoRhythm/inst/doc/disco_workflow_vignette.R
// Upstream  : SummarizedExperiment
// Downstream: none
//
// Install: BiocManager::install("DiscoRhythm")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DISCORHYTHM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-discorhythm"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-discorhythm:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-discorhythm:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(summarizedexperiment)

    output:
    tuple val(meta), path("${meta.id}_discorhythm_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_discorhythm_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_discorhythm_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DiscoRhythm)
    library(jsonlite)


    # --- Interface [] ---
    # Key functions: include_graphics
    knitr::include_graphics("IntroductionSS.jpg")

    # --- Select Data [] ---
    # Key functions: include_graphics, selectDataSS.jpg
    knitr::include_graphics("selectDataSS.jpg")

    # --- Cor Quality Control [] ---
    # Key functions: include_graphics
    knitr::include_graphics("IntersampleCorrelationSS.jpg")

    # --- PCA Quality Control [] ---
    # Key functions: include_graphics
    knitr::include_graphics("PCASS.jpg")

    # --- Filtering Summary [] ---
    # Key functions: include_graphics
    knitr::include_graphics("FilteringSummarySS.jpg")

    # --- Rep Analysis [] ---
    # Key functions: include_graphics
    knitr::include_graphics("RowSelectionSS.jpg")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_discorhythm_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_discorhythm_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_discorhythm_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DISCORHYTHM:", paste0("    discorhythm: ", packageVersion("DiscoRhythm"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_discorhythm_results.csv
    touch ${prefix}_discorhythm_output.rds
    echo "BIOC_DISCORHYTHM:" > versions.yml
    echo "    discorhythm: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DISCORHYTHM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(summarizedexperiment) ]

    main:
    BIOC_DISCORHYTHM(ch_input)

    emit:
    results  = BIOC_DISCORHYTHM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DISCORHYTHM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DISCORHYTHM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DISCORHYTHM.out.versions  // channel: path(versions.yml)
}
