#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: tximport — gene_level_import_and_edger_limma
// Import transcript-level estimates, summarize them to the gene level, and prepare a DGEList object for downstream analysis with edgeR or limma-voom.
// Input: quant.sf.gz, tx2gene.gencode.v27.csv
// Container: quay.io/biocontainers/bioconductor-tximport:1.38.2--r45hdfd78af_0
// Requires: edgeR, readr, tximport
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Locate quantification files and define sample names
//  * 2. [Input & Preparation] Read transcript-to-gene mapping table
//  * 3. [Visualization & Output] Import and summarize transcript-level estimates to gene-level using tximport
//  * 4. [Input & Preparation] Create a DGEList object using DGEListFromTximport

nextflow.enable.dsl = 2

process BIOC_TXIMPORT_GENE_LEVEL_IMPORT_AND_EDGER_LIMMA {
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
    library(readr)
    library(tximport)
    library(edgeR)
    
    # 1. Locate quantification files and define sample names
    # Reading the exact user input file "quant.sf.gz" from the working directory
    files <- "quant.sf.gz"
    names(files) <- "sample1"
    
    # 2. Read transcript-to-gene mapping table
    # Reading the exact user input file "tx2gene.gencode.v27.csv" from the working directory
    tx2gene <- read_csv("tx2gene.gencode.v27.csv")
    
    # 3. Import and summarize transcript-level estimates to gene-level using tximport
    txi <- tximport(files, type="salmon", tx2gene=tx2gene)
    
    # 4. Create a DGEList object using DGEListFromTximport
    dge <- DGEListFromTximport(txi)
    
    # Save meaningful results to output files
    saveRDS(dge, "dge_object.rds")
    write.csv(dge\$counts, "gene_level_counts.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_TXIMPORT_GENE_LEVEL_IMPORT_AND_EDGER_LIMMA":',
        paste0('    tximport: ', as.character(packageVersion('tximport')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gene_level_import_and_edger_limma.csv versions.yml
    """
}

workflow BIOC_TXIMPORT_GENE_LEVEL_IMPORT_AND_EDGER_LIMMA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ quant.sf.gz, tx2gene.gencode.v27.csv ] ]

    main:
    BIOC_TXIMPORT_GENE_LEVEL_IMPORT_AND_EDGER_LIMMA(ch_input)

    emit:
    tables   = BIOC_TXIMPORT_GENE_LEVEL_IMPORT_AND_EDGER_LIMMA.out.tables
    plots    = BIOC_TXIMPORT_GENE_LEVEL_IMPORT_AND_EDGER_LIMMA.out.plots
    objects  = BIOC_TXIMPORT_GENE_LEVEL_IMPORT_AND_EDGER_LIMMA.out.objects
    versions = BIOC_TXIMPORT_GENE_LEVEL_IMPORT_AND_EDGER_LIMMA.out.versions
}
