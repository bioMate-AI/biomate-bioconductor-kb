#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SeqGate
// Filtering of lowly expressed features (e.g. genes) is a common step before performing statistical an
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SeqGate/inst/doc/Seqgate-html-vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("SeqGate")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SEQGATE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-seqgate"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-seqgate:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-seqgate:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_seqgate_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_seqgate_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_seqgate_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DataFrame)
    library(SummarizedExperiment)
    library(jsonlite)

    # --- Create SummarizedExperiment [] ---
    # Key functions: DataFrame, SummarizedExperiment
    rowData <- DataFrame(row.names=rownames(data_MiTF_1000genes))
    colData <- DataFrame(Conditions=cond)
    # --- Assay data access [] ---
    # Key functions: applySeqGate, assay, metadata
    keptGenes <- assay(counts_strub[rowData(counts_strub)$onFilter == TRUE,])
    head(keptGenes)
    dim(keptGenes)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_seqgate_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_seqgate_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_seqgate_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SEQGATE:", paste0("    seqgate: ", packageVersion("SeqGate"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_seqgate_results.csv
    touch ${prefix}_seqgate_output.rds
    echo "BIOC_SEQGATE:" > versions.yml
    echo "    seqgate: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SEQGATE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SEQGATE(ch_input)

    emit:
    results  = BIOC_SEQGATE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SEQGATE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SEQGATE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SEQGATE.out.versions  // channel: path(versions.yml)
}
