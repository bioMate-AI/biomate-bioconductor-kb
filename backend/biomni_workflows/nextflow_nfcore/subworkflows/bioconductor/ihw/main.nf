#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: IHW — standard_ihw_analysis
// Perform independent hypothesis weighting for FDR or FWER control using a complete list of p-values and a continuous covariate.
// Input: deRes.csv
// Container: quay.io/biocontainers/bioconductor-ihw:1.38.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: IHW, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run the IHW procedure using the formula interface
//  * 2. [Core Analysis] Retrieve the total number of rejections
//  * 3. [Core Analysis] Extract adjusted p-values and weights
//  * 4. [Visualization & Output] Generate diagnostic plots of weights and decision boundaries
//  * 5. [Core Analysis] Convert the results to a data frame for downstream analysis
//  * 6. [Core Analysis] Optionally perform FWER control using the Bonferroni adjustment type

nextflow.enable.dsl = 2

process BIOC_IHW_STANDARD_IHW_ANALYSIS {
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
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(IHW)
    library(ggplot2)
    
    # 1. Read the user input file
    # The file 'deRes.csv' must contain at least 'pvalue' and 'baseMean' columns.
    if (!file.exists("deRes.csv")) {
      stop("Error: 'deRes.csv' not found in the working directory.")
    }
    
    deRes <- read.csv("deRes.csv", stringsAsFactors = FALSE)
    
    # 2. Run the IHW procedure using the formula interface
    ihwRes <- ihw(pvalue ~ baseMean, data = deRes, alpha = 0.1)
    
    # 3. Retrieve the total number of rejections
    num_rejections <- rejections(ihwRes)
    cat("Number of rejections: ", num_rejections, "\n")
    
    # 4. Extract adjusted p-values and weights
    adj_p <- adj_pvalues(ihwRes)
    cat("First few adjusted p-values:\n")
    print(head(adj_p))
    
    # Verify consistency of rejections
    consistency_check <- sum(adj_pvalues(ihwRes) <= 0.1, na.rm = TRUE) == rejections(ihwRes)
    cat("Consistency check (sum of adj_p <= 0.1 equals rejections): ", consistency_check, "\n")
    
    # Extract weights
    w <- weights(ihwRes)
    cat("First few weights:\n")
    print(head(w))
    
    # Extract bins and folds
    bins_folds <- c(nbins(ihwRes), nfolds(ihwRes))
    cat("Number of bins and folds: ", paste(bins_folds, collapse = ", "), "\n")
    
    # Extract weights levels only
    w_levels <- weights(ihwRes, levels_only = TRUE)
    cat("Weights levels matrix:\n")
    print(w_levels)
    
    # 5. Generate diagnostic plots of weights and decision boundaries
    pdf("ihw_diagnostic_plots.pdf", width = 7, height = 5)
    
    # Plot 1: Estimated weights
    p1 <- plot(ihwRes)
    print(p1)
    
    # Plot 2: Decision boundary
    p2 <- plot(ihwRes, what = "decisionboundary")
    print(p2)
    
    dev.off()
    cat("Diagnostic plots saved to 'ihw_diagnostic_plots.pdf'\n")
    
    # 6. Convert the results to a data frame for downstream analysis
    ihwResDf <- as.data.frame(ihwRes)
    write.csv(ihwResDf, "ihw_results.csv", row.names = FALSE)
    cat("IHW results data frame saved to 'ihw_results.csv'\n")
    
    # 7. Optionally perform FWER control using the Bonferroni adjustment type
    ihwBonferroni <- ihw(pvalue ~ baseMean, data = deRes, alpha = 0.1, adjustment_type = "bonferroni")
    
    # Save RDS objects for downstream R analysis
    saveRDS(ihwRes, "ihwRes.rds")
    saveRDS(ihwBonferroni, "ihwBonferroni.rds")
    cat("IHW result objects saved to 'ihwRes.rds' and 'ihwBonferroni.rds'\n")

    writeLines(c(
        '"BIOC_IHW_STANDARD_IHW_ANALYSIS":',
        paste0('    IHW: ', as.character(packageVersion('IHW')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_ihw_analysis.csv versions.yml
    """
}

workflow BIOC_IHW_STANDARD_IHW_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ deRes.csv ] ]

    main:
    BIOC_IHW_STANDARD_IHW_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_IHW_STANDARD_IHW_ANALYSIS.out.tables
    plots    = BIOC_IHW_STANDARD_IHW_ANALYSIS.out.plots
    objects  = BIOC_IHW_STANDARD_IHW_ANALYSIS.out.objects
    versions = BIOC_IHW_STANDARD_IHW_ANALYSIS.out.versions
}
