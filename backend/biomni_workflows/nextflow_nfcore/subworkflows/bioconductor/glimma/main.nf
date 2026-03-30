#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Glimma
// This package produces interactive visualizations for RNA-seq data analysis, utilizing output from li
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Glimma/inst/doc/DESeq2.R
// Upstream  : AnnotationHub, DESeq2, edgeR, limma, scRNAseq
// Downstream: RNAseq123
//
// Install: BiocManager::install("Glimma")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GLIMMA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-glimma"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-glimma:2.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-glimma:2.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_glimma_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_glimma_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_glimma_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DESeq)
    library(DESeqDataSetFromMatrix)
    library(jsonlite)

    # --- Readrds [] ---
    # Key functions: DESeqDataSetFromMatrix
    ---------------------------------------------------------------------
    library(Glimma)
    library(edgeR)
    library(DESeq2)
    dge <- readRDS(system.file("RNAseq123/dge.rds", package = "Glimma"))
    # --- Glimmamds [] ---
    # Key functions: glimmaMDS
    ---------------------------------------------------------------------
    glimmaMDS(dds)
    # --- Deseq [] ---
    # Key functions: DESeq
    ---------------------------------------------------------------------
    dds <- DESeq(dds, quiet=TRUE)
    # --- Glimmama [] ---
    # Key functions: glimmaMA
    ---------------------------------------------------------------------
    glimmaMA(dds)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_glimma_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_glimma_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_glimma_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GLIMMA:", paste0("    glimma: ", packageVersion("Glimma"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_glimma_results.csv
    touch ${prefix}_glimma_output.rds
    echo "BIOC_GLIMMA:" > versions.yml
    echo "    glimma: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GLIMMA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GLIMMA(ch_input)

    emit:
    results  = BIOC_GLIMMA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GLIMMA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GLIMMA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GLIMMA.out.versions  // channel: path(versions.yml)
}
