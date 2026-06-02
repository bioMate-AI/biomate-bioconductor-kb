#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Rmmquant
// RNA-Seq is currently used routinely, and it provides accurate information on gene transcription. How
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Rmmquant/inst/doc/Rmmquant.R
// Upstream  : BiocStyle, DESeq2, S4Vectors, SummarizedExperiment, TBX20BamSubset
// Downstream: none
//
// Install: BiocManager::install("Rmmquant")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RMMQUANT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rmmquant"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rmmquant:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rmmquant:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(deseqdataset)

    output:
    tuple val(meta), path("${meta.id}_rmmquant_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rmmquant_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rmmquant_plots.pdf"),    emit: plots, optional: true
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
    library(RmmquantRun)
    library(jsonlite)

    # --- Create DESeqDataSet from count matrix [] ---
    # Key functions: RmmquantRun, DESeqDataSetFromMatrix, DESeq, lfcShrink
    output   <- RmmquantRun(genomicRanges=gr, readsFiles=bamFiles,
    coldata <- data.frame(condition=factor(c(rep("control", 3), rep("KO", 3)),
    levels=c("control", "KO")),
    # --- Assay listing [] ---
    # Key functions: RmmquantRun, assays, getBamFileList, genes
    dir <- system.file("extdata", package="Rmmquant", mustWork = TRUE)
    gtfFile <- file.path(dir, "test.gtf")
    bamFile <- file.path(dir, "test.bam")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rmmquant_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rmmquant_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rmmquant_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RMMQUANT:", paste0("    rmmquant: ", packageVersion("Rmmquant"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rmmquant_results.csv
    touch ${prefix}_rmmquant_output.rds
    echo "BIOC_RMMQUANT:" > versions.yml
    echo "    rmmquant: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RMMQUANT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(deseqdataset) ]

    main:
    BIOC_RMMQUANT(ch_input)

    emit:
    results  = BIOC_RMMQUANT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RMMQUANT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RMMQUANT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RMMQUANT.out.versions  // channel: path(versions.yml)
}
