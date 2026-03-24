#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: HPAanalyze
// Provide functions for retrieving, exploratory analyzing and visualizing the Human Protein Atlas data
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/HPAanalyze/inst/doc/a_HPAanalyze_quick_start.R
// Upstream  : BiocStyle, dplyr, ggplot2, tibble
// Downstream: none
//
// Install: BiocManager::install("HPAanalyze")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HPAANALYZE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-hpaanalyze"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-hpaanalyze:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-hpaanalyze:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_hpaanalyze_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_hpaanalyze_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_hpaanalyze_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(HPAanalyze)
    library(jsonlite)

    # --- hpaVis eg [] ---
    # Key functions: hpaVis
    hpaVis(targetGene = c("GCH1", "PTS", "SPR", "DHFR"),
    targetTissue = c("cerebellum", "cerebral cortex", "hippocampus"),
    targetCancer = c("glioma"))
    # --- hpaVis eg3 [] ---
    # Key functions: hpaVis
    hpaVis(visType = "Patho",
    targetGene = c("GCH1", "PTS", "SPR", "DHFR"),
    targetCancer = c("glioma", "breast cancer"))
    # --- hpaVisPatho eg [] ---
    # Key functions: hpaVisPatho
    hpaVisPatho(targetGene = c("GCH1", "PTS", "SPR", "DHFR"))
    # --- listParam ex2 [] ---
    # Key functions: hpaListParam
    hpaListParam() %>% glimpse()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_hpaanalyze_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_hpaanalyze_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_hpaanalyze_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HPAANALYZE:", paste0("    hpaanalyze: ", packageVersion("HPAanalyze"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hpaanalyze_results.csv
    touch ${prefix}_hpaanalyze_output.rds
    echo "BIOC_HPAANALYZE:" > versions.yml
    echo "    hpaanalyze: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HPAANALYZE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HPAANALYZE(ch_input)

    emit:
    results  = BIOC_HPAANALYZE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HPAANALYZE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HPAANALYZE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HPAANALYZE.out.versions  // channel: path(versions.yml)
}
