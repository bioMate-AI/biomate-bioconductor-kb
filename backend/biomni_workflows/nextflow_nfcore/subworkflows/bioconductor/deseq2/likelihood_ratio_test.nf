#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DESeq2 — likelihood_ratio_test
// Perform a Likelihood Ratio Test (LRT) to identify genes with significant changes across multi-level factors or time-series.
// Input: dds
// Container: quay.io/biocontainers/bioconductor-deseq2:1.50.2--r45ha27e39d_0
// Requires: DESeq2
// Visualizations: MA plot
// QC: diagnostic MA/PCA QC
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run DESeq() with LRT test and specify a reduced design formula
//  * 2. [Core Analysis] Extract results

nextflow.enable.dsl = 2

process BIOC_DESEQ2_LIKELIHOOD_RATIO_TEST {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required libraries
    library(DESeq2)
    
    # Read user input
    if (file.exists("dds")) {
      dds <- readRDS("dds")
    } else if (file.exists("dds.rds")) {
      dds <- readRDS("dds.rds")
    } else {
      stop("Input file 'dds' or 'dds.rds' not found in the working directory.")
    }
    
    # Execute documented workflow
    dds <- DESeq(dds, test="LRT", reduced=~1)
    res <- results(dds)
    
    # Write outputs
    # 1. CSV table of results
    write.csv(as.data.frame(res), file = "lrt_results.csv", row.names = TRUE)
    
    # 2. RDS of the processed dds and results
    saveRDS(dds, file = "dds_lrt_processed.rds")
    saveRDS(res, file = "res_lrt_processed.rds")
    
    # 3. Diagnostic plots
    pdf("lrt_plots.pdf", width = 7, height = 7)
    plotMA(res, main = "Likelihood Ratio Test (LRT) - MA Plot")
    if (!is.null(res\$pvalue)) {
      hist(res\$pvalue, breaks = 50, col = "skyblue", border = "white",
           xlab = "p-value", main = "P-value Distribution")
    }
    dev.off()

    writeLines(c(
        '"BIOC_DESEQ2_LIKELIHOOD_RATIO_TEST":',
        paste0('    DESeq2: ', as.character(packageVersion('DESeq2')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_likelihood_ratio_test.csv versions.yml
    """
}

workflow BIOC_DESEQ2_LIKELIHOOD_RATIO_TEST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dds ] ]

    main:
    BIOC_DESEQ2_LIKELIHOOD_RATIO_TEST(ch_input)

    emit:
    tables   = BIOC_DESEQ2_LIKELIHOOD_RATIO_TEST.out.tables
    plots    = BIOC_DESEQ2_LIKELIHOOD_RATIO_TEST.out.plots
    objects  = BIOC_DESEQ2_LIKELIHOOD_RATIO_TEST.out.objects
    versions = BIOC_DESEQ2_LIKELIHOOD_RATIO_TEST.out.versions
}
