#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Linnorm — highly_variable_gene_analysis
// Identify highly variable genes/features from expression data.
// Input: Islam2011
// Container: quay.io/biocontainers/bioconductor-linnorm:2.34.0--r45ha27e39d_0
// R packages: Linnorm, ggplot2
// Bioconductor: 3.20 | R: 4.4
// Requires: Linnorm, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run Linnorm.HVar to detect highly variable genes
//  * 2. [Visualization & Output] Extract results and plot Mean vs SD highlighting significant genes

nextflow.enable.dsl = 2

process BIOC_LINNORM_HIGHLY_VARIABLE_GENE_ANALYSIS {
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
    .bm_deps <- c("Linnorm", "ggplot2")
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
    library(Linnorm)
    library(ggplot2)
    
    # Read user input file "Islam2011"
    # The pipeline reads the file from the working directory.
    if (file.exists("Islam2011.txt")) {
      Islam2011 <- as.matrix(read.table("Islam2011.txt", header=TRUE, sep="\t", row.names=1, check.names=FALSE))
    } else if (file.exists("Islam2011.csv")) {
      Islam2011 <- as.matrix(read.csv("Islam2011.csv", header=TRUE, row.names=1, check.names=FALSE))
    } else if (file.exists("Islam2011")) {
      Islam2011 <- as.matrix(read.table("Islam2011", header=TRUE, row.names=1, check.names=FALSE))
    } else {
      stop("Error: Input file 'Islam2011' (as .txt, .csv, or extensionless) not found in the working directory.")
    }
    
    # Ensure the matrix is numeric
    storage.mode(Islam2011) <- "numeric"
    
    # Run Linnorm.HVar to detect highly variable genes
    results <- Linnorm.HVar(Islam2011)
    
    # Extract results
    resultsdata <- results\$Results
    Genes10 <- resultsdata[order(resultsdata[,"q.value"]),][1:10,3:5]
    
    # Write meaningful results to output files
    write.csv(resultsdata, "highly_variable_genes_results.csv", row.names=TRUE)
    write.csv(Genes10, "top10_highly_variable_genes.csv", row.names=TRUE)
    saveRDS(results, "linnorm_hvar_results.rds")
    
    # Plot Mean vs SD highlighting significant genes
    pdf("highly_variable_genes_plot.pdf", width=6, height=6)
    print(results\$plot\$plot)
    dev.off()

    writeLines(c(
        '"BIOC_LINNORM_HIGHLY_VARIABLE_GENE_ANALYSIS":',
        paste0('    Linnorm: ', as.character(packageVersion('Linnorm')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_highly_variable_gene_analysis.csv versions.yml
    """
}

workflow BIOC_LINNORM_HIGHLY_VARIABLE_GENE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Islam2011 ] ]

    main:
    BIOC_LINNORM_HIGHLY_VARIABLE_GENE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_LINNORM_HIGHLY_VARIABLE_GENE_ANALYSIS.out.tables
    plots    = BIOC_LINNORM_HIGHLY_VARIABLE_GENE_ANALYSIS.out.plots
    objects  = BIOC_LINNORM_HIGHLY_VARIABLE_GENE_ANALYSIS.out.objects
    versions = BIOC_LINNORM_HIGHLY_VARIABLE_GENE_ANALYSIS.out.versions
}
