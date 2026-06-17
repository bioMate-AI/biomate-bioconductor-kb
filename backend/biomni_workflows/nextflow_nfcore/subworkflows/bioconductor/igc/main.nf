#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: iGC — cna_driven_gene_analysis
// Identify differentially expressed genes driven by copy number alterations from paired gene expression and CNA data.
// Input: sample_desc.csv, CNA files, GE files
// Container: quay.io/biocontainers/bioconductor-igc:1.40.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: data.table, iGC
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create sample description table using create_sample_desc
//  * 2. [Input & Preparation] Read and join gene expression data across samples using create_gene_exp
//  * 3. [Input & Preparation] Read, map, and categorize CNA data into gain/loss/neutral states using create_gene_cna
//  * 4. [Core Analysis] Identify CNA-driven differentially expressed genes using find_cna_driven_gene

nextflow.enable.dsl = 2

process BIOC_IGC_CNA_DRIVEN_GENE_ANALYSIS {
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
    .bm_deps <- c("iGC", "data.table")
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
    library(iGC)
    library(data.table)
    
    # 1. Create sample description table using create_sample_desc
    # The user must provide 'sample_desc.csv' in the working directory.
    # This file maps sample names to CNA and gene expression file paths.
    sample_desc_pth <- "sample_desc.csv"
    sample_desc <- create_sample_desc(sample_desc_pth)
    
    # 2. Read and join gene expression data across samples using create_gene_exp
    gene_exp <- create_gene_exp(sample_desc, progress = FALSE)
    
    # 3. Read, map, and categorize CNA data into gain/loss/neutral states using create_gene_cna
    my_cna_reader <- function(cna_filepath) {
      cna <- data.table::fread(cna_filepath, sep = '\t', header = TRUE)
      cna[, .(Chromosome, Start, End, Segment_Mean)]
    }
    
    gain_loss = log2(c(2.4, 1.6)) - 1
    
    gene_cna <- create_gene_cna(
      sample_desc,
      gain_threshold = gain_loss[1], loss_threshold = gain_loss[2],
      read_fun = my_cna_reader,
      progress = FALSE
    )
    
    # 4. Identify CNA-driven differentially expressed genes using find_cna_driven_gene
    cna_driven_genes <- find_cna_driven_gene(
      gene_cna, gene_exp,
      gain_prop = 0.15, loss_prop = 0.15,
      progress = FALSE, parallel = FALSE
    )
    
    # Write outputs to the working directory
    # Save the complete results object
    saveRDS(cna_driven_genes, file = "cna_driven_genes.rds")
    
    # Save individual tables as CSV files
    if (!is.null(cna_driven_genes\$gain_driven)) {
      data.table::fwrite(cna_driven_genes\$gain_driven, file = "gain_driven_genes.csv")
    }
    
    if (!is.null(cna_driven_genes\$loss_driven)) {
      data.table::fwrite(cna_driven_genes\$loss_driven, file = "loss_driven_genes.csv")
    }
    
    if (!is.null(cna_driven_genes\$both)) {
      data.table::fwrite(cna_driven_genes\$both, file = "both_driven_genes.csv")
    }

    writeLines(c(
        '"BIOC_IGC_CNA_DRIVEN_GENE_ANALYSIS":',
        paste0('    iGC: ', as.character(packageVersion('iGC')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cna_driven_gene_analysis.csv versions.yml
    """
}

workflow BIOC_IGC_CNA_DRIVEN_GENE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sample_desc.csv, CNA files, GE files ] ]

    main:
    BIOC_IGC_CNA_DRIVEN_GENE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_IGC_CNA_DRIVEN_GENE_ANALYSIS.out.tables
    plots    = BIOC_IGC_CNA_DRIVEN_GENE_ANALYSIS.out.plots
    objects  = BIOC_IGC_CNA_DRIVEN_GENE_ANALYSIS.out.objects
    versions = BIOC_IGC_CNA_DRIVEN_GENE_ANALYSIS.out.versions
}
