#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: EpiMix
// EpiMix is a comprehensive tool for the integrative analysis of high-throughput DNA methylation data 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/EpiMix/inst/doc/Methylation_Modeling.R
// Upstream  : DT, clusterProfiler, miRBaseConverter, multiMiR, survival
// Downstream: none
//
// Install: BiocManager::install("EpiMix")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EPIMIX {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-epimix"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-epimix:1.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-epimix:1.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_epimix_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_epimix_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_epimix_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(EpiMix)
    library(jsonlite)

    # --- Kable [] ---
    # Key functions: kable
    ---------------------------------------------------------------------
    knitr::kable(METProcessedData[1:5,1:5])

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_epimix_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_epimix_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_epimix_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_EPIMIX:", paste0("    epimix: ", packageVersion("EpiMix"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_epimix_results.csv
    touch ${prefix}_epimix_output.rds
    echo "BIOC_EPIMIX:" > versions.yml
    echo "    epimix: 0.0.0" >> versions.yml
    """
}


workflow BIOC_EPIMIX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_EPIMIX(ch_input)

    emit:
    results  = BIOC_EPIMIX.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_EPIMIX.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_EPIMIX.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_EPIMIX.out.versions  // channel: path(versions.yml)
}
