#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: geneplotter — single_chromosome_expression_plotting
// Plot expression levels or cumulative expression along a single chromosome to detect regional genomic features
// Input: sample.ExpressionSet, chrObj
// Container: quay.io/biocontainers/bioconductor-geneplotter:1.88.0--r45hdfd78af_0
// R packages: Biobase, annotate, geneplotter
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, annotate, geneplotter
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define colors for sample covariates
//  * 2. [Visualization & Output] Plot expression along a specific chromosome using alongChrom

nextflow.enable.dsl = 2

process BIOC_GENEPLOTTER_SINGLE_CHROMOSOME_EXPRESSION_PLOTTING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("Biobase", "annotate", "geneplotter")
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
    library(Biobase)
    library(geneplotter)
    library(annotate)
    
    # Read the exact user input files from the working directory
    eset <- readRDS("sample.ExpressionSet")
    chrObj <- readRDS("chrObj")
    
    # Define output PDF file for the plot
    output_pdf <- "alongChrom_plot.pdf"
    pdf(output_pdf, width = 10, height = 8)
    
    # Stage 1: Define colors for sample covariates
    par(mfrow=c(1,1)) 
    mycols <- c("red", "darkgreen", "blue")[eset\$cov3]
    
    # Stage 2: Plot expression along a specific chromosome using alongChrom
    alongChrom(eset, "1", chrObj, plotFormat="cumulative", 
           col=mycols)
    
    # Close the plotting device
    dev.off()
    
    # Log completion
    cat(paste("Pipeline completed successfully. Plot saved to:", output_pdf, "\n"))

    writeLines(c(
        '"BIOC_GENEPLOTTER_SINGLE_CHROMOSOME_EXPRESSION_PLOTTING":',
        paste0('    geneplotter: ', as.character(packageVersion('geneplotter')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_chromosome_expression_plotting.csv versions.yml
    """
}

workflow BIOC_GENEPLOTTER_SINGLE_CHROMOSOME_EXPRESSION_PLOTTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sample.ExpressionSet, chrObj ] ]

    main:
    BIOC_GENEPLOTTER_SINGLE_CHROMOSOME_EXPRESSION_PLOTTING(ch_input)

    emit:
    tables   = BIOC_GENEPLOTTER_SINGLE_CHROMOSOME_EXPRESSION_PLOTTING.out.tables
    plots    = BIOC_GENEPLOTTER_SINGLE_CHROMOSOME_EXPRESSION_PLOTTING.out.plots
    objects  = BIOC_GENEPLOTTER_SINGLE_CHROMOSOME_EXPRESSION_PLOTTING.out.objects
    versions = BIOC_GENEPLOTTER_SINGLE_CHROMOSOME_EXPRESSION_PLOTTING.out.versions
}
