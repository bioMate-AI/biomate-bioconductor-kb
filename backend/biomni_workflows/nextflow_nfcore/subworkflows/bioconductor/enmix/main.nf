#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ENmix
// Tools for quanlity control, analysis and visulization of Illumina DNA methylation array data.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ENmix/inst/doc/ENmix.R
// Upstream  : geneplotter, minfiData, minfidata
// Downstream: none
//
// Install: BiocManager::install("ENmix")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ENMIX {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-enmix"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-enmix:1.42.2--r44_0' :
        'quay.io/biocontainers/bioconductor-enmix:1.42.2--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_enmix_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_enmix_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_enmix_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(AnnotatedDataFrame)
    library(MethylSet)
    library(QCinfo)
    library(jsonlite)

    # --- Sample metadata inspection [] ---
    # Key functions: readidat, QCinfo, preprocessENmix, rcp, qcfilter, colData, plotCtrl, AnnotatedDataFrame
    library(ENmix)
    rgSet <- readidat(path = "directory path for idat files",
    system("wget https://webdata.illumina.com/downloads/productfiles/humanmethylation450/humanmethylation450_15017482_v1-2.csv")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_enmix_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_enmix_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_enmix_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ENMIX:", paste0("    enmix: ", packageVersion("ENmix"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_enmix_results.csv
    touch ${prefix}_enmix_output.rds
    echo "BIOC_ENMIX:" > versions.yml
    echo "    enmix: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ENMIX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ENMIX(ch_input)

    emit:
    results  = BIOC_ENMIX.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ENMIX.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ENMIX.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ENMIX.out.versions  // channel: path(versions.yml)
}
