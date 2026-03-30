#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DEFormats
// Convert between different data formats used by differential gene expression analysis tools.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DEFormats/inst/doc/DEFormats.R
// Upstream  : DESeq2, edgeR
// Downstream: none
//
// Install: BiocManager::install("DEFormats")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DEFORMATS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-deformats"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-deformats:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-deformats:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_deformats_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_deformats_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_deformats_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DESeqDataSet)
    library(DESeqDataSetFromMatrix)
    library(DGEList)
    library(jsonlite)

    # --- Counts [] ---
    # Key functions: simulateRnaSeqData
    ---------------------------------------------------------------
    counts = simulateRnaSeqData()
    # --- Dge [] ---
    # Key functions: DGEList
    ------------------------------------------------------------------
    group = rep(c("A", "B"), each = 3)
    dge = DGEList(counts, group = group)
    dge
    # --- Dds [] ---
    # Key functions: DESeqDataSet
    ------------------------------------------------------------------
    dds = as.DESeqDataSet(dge)
    dds
    # --- Dgedds [] ---
    # Key functions: DGEList
    ---------------------------------------------------------------
    identical(dge, as.DGEList(dds))
    # --- Identicaldds [] ---
    # Key functions: DESeqDataSetFromMatrix, frame
    ---------------------------------------------------------
    dds1 = DESeqDataSetFromMatrix(counts, data.frame(condition=group), ~ condition)
    dds2 = DESeqDataSetFromMatrix(counts, data.frame(condition=group), ~ condition)
    identical(dds1, dds2)
    # --- Se [] ---
    # Key functions: simulateRnaSeqData
    -------------------------------------------------------------------
    se = simulateRnaSeqData(output = "RangedSummarizedExperiment")
    se
    # --- Dds Se [] ---
    # Key functions: DESeqDataSet
    ---------------------------------------------------------------
    dds = DESeqDataSet(se, design = ~ condition)
    # --- Dgedds2 [] ---
    # Key functions: DGEList
    --------------------------------------------------------------
    dge = as.DGEList(dds)
    dge
    # --- Dgese [] ---
    # Key functions: colData, DGEList
    ----------------------------------------------------------------
    names(colData(se)) = "group"
    dge = DGEList(se)
    dge
    # --- Rse [] ---
    # Key functions: DESeqDataSet
    ------------------------------------------------------------------
    dds = as.DESeqDataSet(dge)
    rse = as(dds, "RangedSummarizedExperiment")
    rse

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_deformats_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_deformats_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_deformats_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DEFORMATS:", paste0("    deformats: ", packageVersion("DEFormats"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_deformats_results.csv
    touch ${prefix}_deformats_output.rds
    echo "BIOC_DEFORMATS:" > versions.yml
    echo "    deformats: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DEFORMATS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DEFORMATS(ch_input)

    emit:
    results  = BIOC_DEFORMATS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DEFORMATS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DEFORMATS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DEFORMATS.out.versions  // channel: path(versions.yml)
}
