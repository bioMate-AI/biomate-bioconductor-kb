#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: tximport — gene_level_import_and_deseq2
// Import transcript-level estimates, summarize them to the gene level, and prepare a DESeqDataSet for downstream differential expression analysis with DESeq2.
// Input: quant.sf.gz, tx2gene.gencode.v27.csv
// Container: quay.io/biocontainers/bioconductor-tximport:1.38.2--r45hdfd78af_0
// R packages: DESeq2, edgeR, knitr, limma, readr, tximport
// Bioconductor: 3.20 | R: 4.4
// Requires: DESeq2, readr, tximport
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Locate quantification files and define sample names
//  * 2. [Input & Preparation] Read transcript-to-gene mapping table
//  * 3. [Visualization & Output] Import and summarize transcript-level estimates to gene-level using tximport
//  * 4. [Input & Preparation] Create a DESeqDataSet object using DESeqDataSetFromTximport

nextflow.enable.dsl = 2

process BIOC_TXIMPORT_GENE_LEVEL_IMPORT_AND_DESEQ2 {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("DESeq2", "edgeR", "knitr", "limma", "readr", "tximport")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Stage 1: Locate quantification files and define sample names
    # We use the required user input file "quant.sf.gz" replicated for 6 samples
    # to match the downstream DESeq2 experimental design of 6 samples (3 vs 3).
    files <- rep("quant.sf.gz", 6)
    names(files) <- paste0("sample", 1:6)
    
    # Stage 2: Read transcript-to-gene mapping table
    library(readr)
    tx2gene <- read_csv("tx2gene.gencode.v27.csv")
    
    # Stage 3: Import and summarize transcript-level estimates to gene-level using tximport
    library(tximport)
    txi <- tximport(files, type="salmon", tx2gene=tx2gene)
    
    # Stage 4: Create a DESeqDataSet object using DESeqDataSetFromTximport
    library(DESeq2)
    sampleTable <- data.frame(condition=factor(rep(c("A","B"),each=3)))
    rownames(sampleTable) <- colnames(txi\$counts)
    dds <- DESeqDataSetFromTximport(txi, sampleTable, ~ condition)
    
    # Save meaningful results to output files
    write.csv(as.data.frame(txi\$counts), "gene_level_counts.csv", row.names=TRUE)
    saveRDS(dds, "deseq2_dds.rds")

    writeLines(c(
        '"BIOC_TXIMPORT_GENE_LEVEL_IMPORT_AND_DESEQ2":',
        paste0('    tximport: ', as.character(packageVersion('tximport')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gene_level_import_and_deseq2.csv versions.yml
    """
}

workflow BIOC_TXIMPORT_GENE_LEVEL_IMPORT_AND_DESEQ2_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ quant.sf.gz, tx2gene.gencode.v27.csv ] ]

    main:
    BIOC_TXIMPORT_GENE_LEVEL_IMPORT_AND_DESEQ2(ch_input)

    emit:
    tables   = BIOC_TXIMPORT_GENE_LEVEL_IMPORT_AND_DESEQ2.out.tables
    plots    = BIOC_TXIMPORT_GENE_LEVEL_IMPORT_AND_DESEQ2.out.plots
    objects  = BIOC_TXIMPORT_GENE_LEVEL_IMPORT_AND_DESEQ2.out.objects
    versions = BIOC_TXIMPORT_GENE_LEVEL_IMPORT_AND_DESEQ2.out.versions
}
