#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cycle — periodic_expression_analysis
// Assess the statistical significance of periodic gene expression in time-series data using Fourier analysis and AR(1) or random permutation background models.
// Input: ExpressionSet
// Container: quay.io/biocontainers/bioconductor-cycle:1.64.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, cycle
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Filter out genes with excessive missing values
//  * 2. [Input & Preparation] Impute remaining missing values
//  * 3. [Input & Preparation] Standardize the expression values
//  * 4. [Input & Preparation] Extract measurement times and define the cycle period
//  * 5. [Input & Preparation] Calculate false discovery rates (FDR) using fdrfourier
//  * 6. [Input & Preparation] Identify significantly periodic genes by filtering on the

nextflow.enable.dsl = 2

process BIOC_CYCLE_PERIODIC_EXPRESSION_ANALYSIS {
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
    .bm_deps <- c("cycle", "Biobase")
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
    library(cycle)
    library(Biobase)
    
    # Set seed for reproducibility
    set.seed(1)
    
    # Read the user-provided ExpressionSet from the working directory
    input_file <- "expression_set.rds"
    if (!file.exists(input_file)) {
      stop(paste("Error: Input file", input_file, "not found in the working directory."))
    }
    
    yeast <- readRDS(input_file)
    
    # --- Filter out genes with excessive missing values ---
    yeast <- filter.NA(yeast, thres=0.25)
    
    # --- Impute remaining missing values ---
    yeast <- fill.NA(yeast, mode="mean")
    
    # --- Standardize the expression values ---
    yeast <- standardise(yeast)
    
    # Calculate autocorrelation
    auto.corr <- 0
    for (i in 2:dim(exprs(yeast))[[2]]){
      auto.corr[i] <- cor(exprs(yeast)[,i-1], exprs(yeast)[,i])
    }
    
    # Save autocorrelation to a CSV
    auto_corr_df <- data.frame(
      Timepoint_Index = 1:length(auto.corr),
      Autocorrelation = auto.corr
    )
    write.csv(auto_corr_df, "autocorrelation_results.csv", row.names = FALSE)
    
    # --- Extract measurement times and define the cycle period ---
    if ("period" %in% colnames(pData(yeast))) {
      T.yeast <- as.numeric(pData(yeast)\$period[1])
    } else if ("cycle_period" %in% colnames(pData(yeast))) {
      T.yeast <- as.numeric(pData(yeast)\$cycle_period[1])
    } else if ("T" %in% colnames(pData(yeast))) {
      T.yeast <- as.numeric(pData(yeast)\$T[1])
    } else {
      stop("Error: Cycle period not found. Please include 'period', 'cycle_period', or 'T' in the ExpressionSet pData.")
    }
    times.yeast <- pData(yeast)\$time 
    
    # --- Calculate false discovery rates (FDR) using fdrfourier ---
    NN <- 100 
    fdr.rr <- fdrfourier(eset=yeast, T=T.yeast, times=times.yeast, background.model="rr", N=NN, progress=FALSE)
    fdr.ar1 <- fdrfourier(eset=yeast, T=T.yeast, times=times.yeast, background.model="ar1", N=NN, progress=FALSE)
    
    # --- Identify significantly periodic genes by filtering on the ---
    # Create a summary data frame of the results
    results_df <- data.frame(
      Gene = rownames(exprs(yeast)),
      FDR_RandomPermutation = fdr.rr\$fdr,
      FDR_AR1 = fdr.ar1\$fdr
    )
    
    # Write the main outputs
    write.csv(results_df, "fdr_analysis_results.csv", row.names = FALSE)
    
    # Save RDS of the full FDR objects
    saveRDS(list(fdr_rr = fdr.rr, fdr_ar1 = fdr.ar1), "fdr_objects.rds")
    
    # Generate a PDF plot comparing the FDR distributions
    pdf("fdr_comparison_plot.pdf", width = 7, height = 6)
    plot(fdr.rr\$fdr, fdr.ar1\$fdr, 
         xlab = "FDR (Random Permutation Model)", 
         ylab = "FDR (AR(1) Model)",
         main = "Comparison of FDRs between Background Models",
         pch = 19, col = "blue")
    abline(a = 0, b = 1, col = "red", lty = 2)
    dev.off()

    writeLines(c(
        '"BIOC_CYCLE_PERIODIC_EXPRESSION_ANALYSIS":',
        paste0('    cycle: ', as.character(packageVersion('cycle')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_periodic_expression_analysis.csv versions.yml
    """
}

workflow BIOC_CYCLE_PERIODIC_EXPRESSION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ExpressionSet ] ]

    main:
    BIOC_CYCLE_PERIODIC_EXPRESSION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_CYCLE_PERIODIC_EXPRESSION_ANALYSIS.out.tables
    plots    = BIOC_CYCLE_PERIODIC_EXPRESSION_ANALYSIS.out.plots
    objects  = BIOC_CYCLE_PERIODIC_EXPRESSION_ANALYSIS.out.objects
    versions = BIOC_CYCLE_PERIODIC_EXPRESSION_ANALYSIS.out.versions
}
