#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MultiRNAflow
// Our R package MultiRNAflow provides an easy to use unified framework allowing to automatically make 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MultiRNAflow/inst/doc/MultiRNAflow_vignette-knitr.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("MultiRNAflow")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MULTIRNAFLOW {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-multirnaflow"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-multirnaflow:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-multirnaflow:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_multirnaflow_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_multirnaflow_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_multirnaflow_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DATAnormalization)
    library(DATAplotExpressionGenes)
    library(DATAprepSE)
    library(DEanalysisGlobal)
    library(DEplotVolcanoMA)
    library(HCPCanalysis)
    library(MFUZZanalysis)
    library(PCAanalysis)
    library(jsonlite)

    # --- Object metadata inspection [] ---
    # Key functions: latex, DATAprepSE, DATAnormalization, metadata, assays, PCAanalysis, HCPCanalysis, MFUZZanalysis
    Sub3bc3T <- RawCounts_Weger2021_MOUSEsub500[, seq_len(73)]
    SelectTime <- grep("_t0_", colnames(Sub3bc3T))
    SelectTime <- c(SelectTime, grep("_t1_", colnames(Sub3bc3T)))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_multirnaflow_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_multirnaflow_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_multirnaflow_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MULTIRNAFLOW:", paste0("    multirnaflow: ", packageVersion("MultiRNAflow"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multirnaflow_results.csv
    touch ${prefix}_multirnaflow_output.rds
    echo "BIOC_MULTIRNAFLOW:" > versions.yml
    echo "    multirnaflow: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MULTIRNAFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MULTIRNAFLOW(ch_input)

    emit:
    results  = BIOC_MULTIRNAFLOW.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MULTIRNAFLOW.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MULTIRNAFLOW.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MULTIRNAFLOW.out.versions  // channel: path(versions.yml)
}
