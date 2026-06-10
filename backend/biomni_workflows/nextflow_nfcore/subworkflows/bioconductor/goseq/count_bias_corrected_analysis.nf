#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: goseq — count_bias_corrected_analysis
// Perform enrichment analysis correcting for read count bias instead of gene length bias.
// Input: genes, counts
// Container: quay.io/biocontainers/bioconductor-goseq:1.62.0--r45hdfd78af_0
// R packages: goseq
// Bioconductor: 3.20 | R: 4.4
// Requires: goseq
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Calculate read count bias per gene
//  * 2. [Core Analysis] Fit the PWF using nullp with custom bias.data
//  * 3. [Core Analysis] Run GO enrichment analysis using goseq

nextflow.enable.dsl = 2

process BIOC_GOSEQ_COUNT_BIAS_CORRECTED_ANALYSIS {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("goseq")
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
    
    # Parse command line arguments for genome and gene ID format
    args <- commandArgs(trailingOnly = TRUE)
    genome_build <- if (length(args) >= 1) args[1] else "hg19"
    gene_id <- if (length(args) >= 2) args[2] else "ensGene"
    
    # Load required libraries
    library(goseq)
    
    # -----------------------------------------------------------------------------
    # Stage 0: Read User Input Files
    # -----------------------------------------------------------------------------
    
    # 1. Load 'genes' (named binary vector of assayed genes and DE status)
    genes <- NULL
    if (file.exists("genes.rds")) {
      genes <- readRDS("genes.rds")
    } else if (file.exists("genes.csv")) {
      df_genes <- read.csv("genes.csv", header = TRUE, stringsAsFactors = FALSE)
      genes <- as.integer(df_genes[[2]])
      names(genes) <- df_genes[[1]]
    } else if (file.exists("genes.tsv")) {
      df_genes <- read.delim("genes.tsv", header = TRUE, stringsAsFactors = FALSE)
      genes <- as.integer(df_genes[[2]])
      names(genes) <- df_genes[[1]]
    } else {
      stop("Error: Required input file 'genes' (RDS, CSV, or TSV format) not found in the working directory.")
    }
    
    # Ensure genes is an integer vector while preserving names
    gene_names <- names(genes)
    genes <- as.integer(genes)
    names(genes) <- gene_names
    
    if (is.null(names(genes))) {
      stop("Error: The 'genes' vector must be named with gene identifiers.")
    }
    
    # 2. Load 'counts' (matrix of raw read counts per gene)
    counts <- NULL
    if (file.exists("counts.rds")) {
      counts <- readRDS("counts.rds")
    } else if (file.exists("counts.csv")) {
      counts <- as.matrix(read.csv("counts.csv", row.names = 1, header = TRUE, check.names = FALSE))
    } else if (file.exists("counts.tsv")) {
      counts <- as.matrix(read.delim("counts.tsv", row.names = 1, header = TRUE, check.names = FALSE))
    } else {
      stop("Error: Required input file 'counts' (RDS, CSV, or TSV format) not found in the working directory.")
    }
    
    # Ensure counts is a matrix
    if (!is.matrix(counts)) {
      counts <- as.matrix(counts)
    }
    
    # -----------------------------------------------------------------------------
    # Stage 1: Calculate read count bias per gene
    # -----------------------------------------------------------------------------
    countbias <- rowSums(counts)
    # Align countbias with the genes vector by name to ensure correct order and length
    countbias <- countbias[names(genes)]
    
    # -----------------------------------------------------------------------------
    # Stage 2: Fit the PWF using nullp with custom bias.data
    # -----------------------------------------------------------------------------
    # Capture the diagnostic plot generated by nullp into a PDF file
    pdf("pwf_plot.pdf", width = 7, height = 7)
    pwf.counts <- nullp(genes, bias.data = countbias)
    dev.off()
    
    # -----------------------------------------------------------------------------
    # Stage 3: Run GO enrichment analysis using goseq
    # -----------------------------------------------------------------------------
    GO.counts <- goseq(pwf.counts, genome_build, gene_id)
    
    # -----------------------------------------------------------------------------
    # Stage 4: Write Output Files
    # -----------------------------------------------------------------------------
    # Save the main enrichment results table
    write.csv(GO.counts, "GO_counts_results.csv", row.names = FALSE)
    
    # Save the fitted PWF object for downstream use or inspection
    saveRDS(pwf.counts, "pwf_counts.rds")
    
    cat("Analysis complete. Outputs written:\n")
    cat("- GO_counts_results.csv (Enrichment analysis results)\n")
    cat("- pwf_counts.rds (Fitted probability weighting function object)\n")
    cat("- pwf_plot.pdf (Diagnostic plot of the PWF fit)\n")

    writeLines(c(
        '"BIOC_GOSEQ_COUNT_BIAS_CORRECTED_ANALYSIS":',
        paste0('    goseq: ', as.character(packageVersion('goseq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_count_bias_corrected_analysis.csv versions.yml
    """
}

workflow BIOC_GOSEQ_COUNT_BIAS_CORRECTED_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genes, counts ] ]

    main:
    BIOC_GOSEQ_COUNT_BIAS_CORRECTED_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_GOSEQ_COUNT_BIAS_CORRECTED_ANALYSIS.out.tables
    plots    = BIOC_GOSEQ_COUNT_BIAS_CORRECTED_ANALYSIS.out.plots
    objects  = BIOC_GOSEQ_COUNT_BIAS_CORRECTED_ANALYSIS.out.objects
    versions = BIOC_GOSEQ_COUNT_BIAS_CORRECTED_ANALYSIS.out.versions
}
