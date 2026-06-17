#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: oncomix — oncomix_analysis
// Identify and visualize oncogene candidates from paired tumor-normal mRNA expression data using 2-component Gaussian mixture models.
// Input: exprNmlIsof.csv, exprTumIsof.csv
// Container: quay.io/biocontainers/bioconductor-oncomix:1.32.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ggplot2, oncomix
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Fit the mixture models to normal and tumor expression data using mixModelParams
//  * 2. [Core Analysis] Filter for top candidate genes using topGeneQuants
//  * 3. [Core Analysis] Select top N genes by sorting the mixture model parameters by score
//  * 4. [Visualization & Output] Plot a histogram of expression values for a specific gene using plotGeneHist
//  * 5. [Visualization & Output] Generate scatter plots of the differences between component means using scatterMixPlot

nextflow.enable.dsl = 2

process BIOC_ONCOMIX_ONCOMIX_ANALYSIS {
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
    .bm_deps <- c("oncomix", "ggplot2")
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
        library(oncomix)
        library(ggplot2)
        
        # Read user input files from the working directory
        # The input files are expected to have genes/isoforms as rows and patients as columns
        exprNmlIsof <- as.matrix(read.csv("exprNmlIsof.csv", row.names = 1, check.names = FALSE))
        exprTumIsof <- as.matrix(read.csv("exprTumIsof.csv", row.names = 1, check.names = FALSE))
        
        # 1. Fit the mixture models to normal and tumor expression data
        mmParams <- mixModelParams(exprNmlIsof, exprTumIsof)
        
        # 2. Filter for top candidate genes using topGeneQuants
        topGeneQuant <- topGeneQuants(mmParams, deltMu2Thr=99, 
            deltMu1Thr=10, siThr=.99)
        
        # 3. Select top N genes (top 10) by sorting the mixture model parameters by score
        mmParamsTop10 <- mmParams[1:10,]
        
        # Define the isoform to plot. 
        # For robustness, if the default "uc002jxc.2" is not present in the user's dataset,
        # we dynamically fall back to the top scoring gene in the dataset.
        isof = "uc002jxc.2"
        if (!(isof %in% rownames(mmParams)) && nrow(mmParams) > 0) {
            isof = rownames(mmParams)[1]
        }
        
        # Open PDF device to save the visualizations
        pdf("oncomix_visualization_plots.pdf", width = 8, height = 7)
        
        # 4. Plot a histogram of expression values for a specific gene
        print(plotGeneHist(mmParams, exprNmlIsof, exprTumIsof, isof))
        
        # 5. Generate scatter plots of the differences between component means
        print(scatterMixPlot(mmParams))
        print(scatterMixPlot(mmParams, selIndThresh=.99))
        print(scatterMixPlot(mmParams=mmParams, geneLabels=rownames(mmParamsTop10)))
        
        # Close the PDF device
        dev.off()
        
        # Save meaningful tabular results and RDS objects
        write.csv(mmParams, "oncomix_all_mixture_model_parameters.csv", row.names = TRUE)
        write.csv(topGeneQuant, "oncomix_top_candidate_genes.csv", row.names = TRUE)
        write.csv(mmParamsTop10, "oncomix_top10_genes.csv", row.names = TRUE)
        saveRDS(mmParams, "oncomix_mmParams.rds")

    writeLines(c(
        '"BIOC_ONCOMIX_ONCOMIX_ANALYSIS":',
        paste0('    oncomix: ', as.character(packageVersion('oncomix')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_oncomix_analysis.csv versions.yml
    """
}

workflow BIOC_ONCOMIX_ONCOMIX_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ exprNmlIsof.csv, exprTumIsof.csv ] ]

    main:
    BIOC_ONCOMIX_ONCOMIX_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_ONCOMIX_ONCOMIX_ANALYSIS.out.tables
    plots    = BIOC_ONCOMIX_ONCOMIX_ANALYSIS.out.plots
    objects  = BIOC_ONCOMIX_ONCOMIX_ANALYSIS.out.objects
    versions = BIOC_ONCOMIX_ONCOMIX_ANALYSIS.out.versions
}
