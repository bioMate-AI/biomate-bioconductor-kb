#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ppcseq — outlier_identification_and_visualization
// Identify and visualize outlier transcripts from RNA-seq differential expression analysis results.
// Input: counts.tsv
// Container: quay.io/biocontainers/bioconductor-ppcseq:1.18.0--r45ha27e39d_0
// R packages: dplyr, ggplot2, knitr, ppcseq, readr
// Bioconductor: 3.20 | R: 4.4
// Requires: dplyr, ggplot2, ppcseq, readr
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the tidy count and differential expression data
//  * 2. [Core Analysis] Identify outlier transcripts using identify_outliers with a specified GLM formula and significance threshold
//  * 3. [Visualization & Output] Generate credible interval plots for the identified outliers using plot_credible_intervals

nextflow.enable.dsl = 2

process BIOC_PPCSEQ_OUTLIER_IDENTIFICATION_AND_VISUALIZATION {
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
    .bm_deps <- c("dplyr", "ggplot2", "knitr", "ppcseq", "readr")
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
    library(dplyr)
    library(ppcseq)
    library(readr)
    library(ggplot2)
    
    # 1. Load the tidy count and differential expression data
    # The input file 'counts.tsv' must be present in the working directory.
    # It should contain columns: sample, symbol, value, PValue, FDR, and a covariate (e.g., Label, condition)
    if (!file.exists("counts.tsv")) {
      stop("Error: 'counts.tsv' not found in the working directory.")
    }
    
    counts <- readr::read_tsv("counts.tsv", col_types = readr::cols())
    
    # Dynamically determine the formula based on covariate columns present
    # Exclude numeric columns to prevent DE statistics (like logFC, test statistics) from being used as covariates
    covariate_cols <- setdiff(colnames(counts), c("sample", "symbol", "value", "PValue", "FDR"))
    if (length(covariate_cols) > 0) {
      covariate_cols <- covariate_cols[!sapply(counts[covariate_cols], is.numeric)]
    }
    
    if (length(covariate_cols) > 0) {
      design_formula <- as.formula(paste("~", paste(covariate_cols, collapse = " + ")))
    } else {
      design_formula <- ~ 1
    }
    
    # 2. Identify outlier transcripts using identify_outliers
    # We reproduce the documented code faithfully.
    counts.ppc = 
    	counts %>%
    	mutate(is_significant = FDR < 0.0001) %>%
    	identify_outliers(
    		formula = design_formula,
    		.sample = sample, 
    		.transcript = symbol,
    		.abundance = value,
    		.significance = PValue,
    		.do_check = is_significant,
    		percent_false_positive_genes = 5, 
    		approximate_posterior_inference = FALSE,
    		cores = 1
    	)
    
    # Save the raw outlier identification results as an RDS object
    saveRDS(counts.ppc, file = "outliers_identified.rds")
    
    # Also save a flattened summary table for easy inspection
    counts.ppc_summary <- counts.ppc %>% 
      dplyr::select(-dplyr::any_of("sample_wise_data"))
    write_csv(counts.ppc_summary, "outliers_summary.csv")
    
    # 3. Generate credible interval plots for the identified outliers
    counts.ppc_plots = 
    	counts.ppc %>% 
    	plot_credible_intervals() 
    
    # Save the plots object
    saveRDS(counts.ppc_plots, file = "credible_interval_plots.rds")
    
    # Export the generated plots to a PDF file
    if (nrow(counts.ppc_plots) > 0) {
      plots_list <- counts.ppc_plots %>% pull(plot)
      
      pdf("credible_intervals_plots.pdf", width = 8, height = 6)
      for (i in seq_along(plots_list)) {
        print(plots_list[[i]])
      }
      dev.off()
    } else {
      message("No outlier plots to save.")
    }

    writeLines(c(
        '"BIOC_PPCSEQ_OUTLIER_IDENTIFICATION_AND_VISUALIZATION":',
        paste0('    ppcseq: ', as.character(packageVersion('ppcseq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_outlier_identification_and_visualization.csv versions.yml
    """
}

workflow BIOC_PPCSEQ_OUTLIER_IDENTIFICATION_AND_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts.tsv ] ]

    main:
    BIOC_PPCSEQ_OUTLIER_IDENTIFICATION_AND_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_PPCSEQ_OUTLIER_IDENTIFICATION_AND_VISUALIZATION.out.tables
    plots    = BIOC_PPCSEQ_OUTLIER_IDENTIFICATION_AND_VISUALIZATION.out.plots
    objects  = BIOC_PPCSEQ_OUTLIER_IDENTIFICATION_AND_VISUALIZATION.out.objects
    versions = BIOC_PPCSEQ_OUTLIER_IDENTIFICATION_AND_VISUALIZATION.out.versions
}
