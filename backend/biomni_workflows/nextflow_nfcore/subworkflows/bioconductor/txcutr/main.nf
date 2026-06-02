#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: txcutr
// Various mRNA sequencing library preparation methods generate sequencing reads specifically from the 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/txcutr/inst/doc/intro.R
// Upstream  : GenomicFeatures, RefManageR, knitr, rmarkdown, sessioninfo
// Downstream: none
//
// Install: BiocManager::install("txcutr")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TXCUTR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-txcutr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-txcutr:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-txcutr:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_txcutr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_txcutr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_txcutr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(txcutr)
    library(PrintBibliography)
    library(jsonlite)

    # --- Merge Table Generation [] ---
    # Key functions: generateMergeTable
    df_merge <- generateMergeTable(txdb_w500, minDistance=500)
    head(df_merge, 10)


    # --- Transcript Annotation and Filtering [] ---
    # Key functions: transcripts
    tx_filtered <- transcripts(txdb_w500,
                               columns=c("tx_name", "gene_id"),
                               filter=list(gene_id=c("YAL026C")))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_txcutr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_txcutr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_txcutr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TXCUTR:", paste0("    txcutr: ", packageVersion("txcutr"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_txcutr_results.csv
    touch ${prefix}_txcutr_output.rds
    echo "BIOC_TXCUTR:" > versions.yml
    echo "    txcutr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TXCUTR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TXCUTR(ch_input)

    emit:
    results  = BIOC_TXCUTR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TXCUTR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TXCUTR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TXCUTR.out.versions  // channel: path(versions.yml)
}
