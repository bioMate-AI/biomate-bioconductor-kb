#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ChIPexoQual
// Package with a quality control pipeline for ChIP-exo/nexus data.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ChIPexoQual/inst/doc/vignette.R
// Upstream  : BiocParallel, BiocStyle, ChIPexoQualExample, gridExtra, knitr
// Downstream: none
//
// Install: BiocManager::install("ChIPexoQual")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CHIPEXOQUAL {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-chipexoqual"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-chipexoqual:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-chipexoqual:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_chipexoqual_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_chipexoqual_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_chipexoqual_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ARCvURCplot)
    library(jsonlite)

    # --- A R Cv U R Cplot [] ---
    # Key functions: ARCvURCplot
    ARCvURCplot(exampleExoData,names.input = paste("Rep",1:3,sep = "-"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_chipexoqual_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_chipexoqual_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_chipexoqual_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CHIPEXOQUAL:", paste0("    chipexoqual: ", packageVersion("ChIPexoQual"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chipexoqual_results.csv
    touch ${prefix}_chipexoqual_output.rds
    echo "BIOC_CHIPEXOQUAL:" > versions.yml
    echo "    chipexoqual: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CHIPEXOQUAL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CHIPEXOQUAL(ch_input)

    emit:
    results  = BIOC_CHIPEXOQUAL.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CHIPEXOQUAL.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CHIPEXOQUAL.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CHIPEXOQUAL.out.versions  // channel: path(versions.yml)
}
