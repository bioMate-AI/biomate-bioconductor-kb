#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MsDataHub
// The MsDataHub package uses the ExperimentHub infrastructure to distribute raw mass spectrometry data
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MsDataHub/inst/doc/MsDataHub.R
// Upstream  : BiocManager, PSMatch, QFeatures, Spectra
// Downstream: none
//
// Install: BiocManager::install("MsDataHub")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MSDATAHUB {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-msdatahub"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-msdatahub:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-msdatahub:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_msdatahub_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_msdatahub_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_msdatahub_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MsDataHub)
    library(jsonlite)

    # --- datatable [] ---
    # Key functions: datatable
    library("MsDataHub")
    DT::datatable(MsDataHub())
    # --- read Q Features From D I A N N [] ---
    # Key functions: readQFeaturesFromDIANN
    library(QFeatures)
    lfdia <- read.delim(MsDataHub::benchmarkingDIA.tsv())
    readQFeaturesFromDIANN(lfdia)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_msdatahub_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_msdatahub_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_msdatahub_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MSDATAHUB:", paste0("    msdatahub: ", packageVersion("MsDataHub"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_msdatahub_results.csv
    touch ${prefix}_msdatahub_output.rds
    echo "BIOC_MSDATAHUB:" > versions.yml
    echo "    msdatahub: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MSDATAHUB_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MSDATAHUB(ch_input)

    emit:
    results  = BIOC_MSDATAHUB.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MSDATAHUB.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MSDATAHUB.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MSDATAHUB.out.versions  // channel: path(versions.yml)
}
