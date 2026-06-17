#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: tximport — gene_level_import_and_edger_limma
// Import transcript-level estimates, summarize them to the gene level, and prepare a DGEList object for downstream analysis with edgeR or limma-voom.
// Input: quant.sf.gz, tx2gene.gencode.v27.csv
// Container: quay.io/biocontainers/bioconductor-tximport:1.38.2--r45hdfd78af_0
// R packages: edgeR, readr, tximport
// Bioconductor: 3.20 | R: 4.4
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
    .bm_deps <- c("edgeR", "readr", "tximport")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
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
