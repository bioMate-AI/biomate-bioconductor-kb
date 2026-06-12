#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: NPARC — nparc_tpp_analysis
// Perform non-parametric analysis of response curves on TPP data to identify significantly shifted proteins.
// Input: stauro_TPP_data_tidy
// Container: quay.io/biocontainers/bioconductor-nparc:1.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, NPARC, dplyr, ggplot2, magrittr
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter data for complete curves (all temperatures present in all replicates/groups)
//  * 2. [Core Analysis] Fit null and alternative sigmoid models using NPARCfit
//  * 3. [Core Analysis] Compute F-statistics and p-values using NPARCtest with empirical degrees of freedom
//  * 4. [Core Analysis] Filter for significantly shifted proteins based on adjusted p-values

nextflow.enable.dsl = 2

process BIOC_NPARC_NPARC_TPP_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20"

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
    .bm_deps <- c("dplyr", "magrittr", "ggplot2", "BiocParallel", "NPARC")
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
    library(magrittr)
    library(ggplot2)
    library(BiocParallel)
    library(NPARC)
    
    # 1. Read User Input
    # The pipeline reads the tidy data frame from the working directory.
    # It supports both CSV and RDS formats.
    input_file <- NULL
    if (file.exists("stauro_TPP_data_tidy.csv")) {
      input_file <- "stauro_TPP_data_tidy.csv"
      df <- read.csv(input_file, stringsAsFactors = FALSE)
    } else if (file.exists("stauro_TPP_data_tidy.rds")) {
      input_file <- "stauro_TPP_data_tidy.rds"
      df <- readRDS(input_file)
    } else if (file.exists("stauro_TPP_data_tidy")) {
      input_file <- "stauro_TPP_data_tidy"
      df <- tryCatch(
        readRDS(input_file),
        error = function(e) read.csv(input_file, stringsAsFactors = FALSE)
      )
    } else {
      stop("Required input file 'stauro_TPP_data_tidy' (CSV or RDS) not found in the working directory.")
    }
    
    # Standardize column names to match NPARC expectations
    col_mapping <- list(
      uniqueID = c("uniqueID", "unique_id", "proteinID", "protein_id", "protein ID", "id"),
      temperature = c("temperature", "temp", "Temperature"),
      relAbundance = c("relAbundance", "rel_abundance", "relativeAbundance", "relative_abundance", "relative abundance"),
      compoundConcentration = c("compoundConcentration", "compound_concentration", "concentration", "compound"),
      replicate = c("replicate", "rep", "Replicate")
    )
    
    for (target in names(col_mapping)) {
      if (!target %in% colnames(df)) {
        matched <- intersect(col_mapping[[target]], colnames(df))
        if (length(matched) > 0) {
          colnames(df)[colnames(df) == matched[1]] <- target
        }
      }
    }
    
    # Validate required columns
    required_cols <- c("uniqueID", "temperature", "relAbundance", "compoundConcentration", "replicate")
    missing_cols <- setdiff(required_cols, colnames(df))
    if (length(missing_cols) > 0) {
      stop(paste("Missing required columns in input data:", paste(missing_cols, collapse = ", ")))
    }
    
    # 2. Filter data for complete curves
    # Remove missing relative abundances
    df <- df %>% filter(!is.na(relAbundance))
    
    # Filter for complete curves (proteins with measurements at all temperatures across replicates and treatment groups)
    df <- df %>%
      group_by(uniqueID) %>%
      mutate(n_obs = n()) %>%
      ungroup()
    
    max_obs <- max(df\$n_obs, na.rm = TRUE)
    
    df <- df %>%
      filter(n_obs == max_obs) %>%
      dplyr::select(-n_obs)
    
    message(paste("Filtered dataset contains", length(unique(df\$uniqueID)), "proteins with complete curves."))
    
    # 3. Fit null and alternative sigmoid models using NPARCfit
    BPPARAM <- BiocParallel::SerialParam(progressbar = FALSE)
    
    fits <- NPARCfit(x = df\$temperature, 
                     y = df\$relAbundance, 
                     id = df\$uniqueID, 
                     groupsNull = NULL, 
                     groupsAlt = df\$compoundConcentration, 
                     BPPARAM = BPPARAM,
                     returnModels = FALSE)
    
    # Save fits object as RDS
    saveRDS(fits, "nparc_fits.rds")
    
    # 4. Compute F-statistics and p-values using NPARCtest with empirical degrees of freedom
    modelMetrics <- fits\$metrics 
    fStats <- NPARCtest(modelMetrics, dfType = "empirical")
    
    # Save metrics and f-statistics
    write.csv(modelMetrics, "nparc_model_metrics.csv", row.names = FALSE)
    write.csv(fStats, "nparc_fstats_results.csv", row.names = FALSE)
    
    # 5. Filter for significantly shifted proteins based on adjusted p-values
    topHits <- fStats %>% 
      filter(pAdj <= 0.01) %>%
      dplyr::select(id, fStat, pVal, pAdj) %>%
      arrange(-fStat)
    
    write.csv(topHits, "nparc_top_hits.csv", row.names = FALSE)
    message(paste("Found", nrow(topHits), "significantly shifted proteins at pAdj <= 0.01."))
    
    # 6. Generate diagnostic plots
    pdf("nparc_diagnostics.pdf", width = 8, height = 6)
    
    # P-value distribution plot
    p_val_plot <- ggplot(filter(fStats, !is.na(pAdj))) +
      geom_histogram(aes(x = pVal, y = after_stat(density)), fill = "steelblue", alpha = 0.5, boundary = 0, bins = 30) +
      geom_line(aes(x = pVal, y = dunif(pVal)), color = "darkred", linewidth = 1.5) +
      theme_bw() +
      labs(title = "p-Value Distribution (Empirical Null)", x = "p-Value", y = "Density")
    print(p_val_plot)
    
    # F-statistic distribution plot
    f_stat_plot <- ggplot(filter(fStats, !is.na(pAdj))) +
      geom_density(aes(x = fStat), fill = "steelblue", alpha = 0.5) +
      geom_line(aes(x = fStat, y = df(fStat, df1 = df1, df2 = df2)), color = "darkred", linewidth = 1.5) +
      theme_bw() +
      xlim(c(0, 10)) +
      labs(title = "F-Statistic Distribution vs Theoretical F-Distribution", x = "F-Statistic", y = "Density")
    print(f_stat_plot)
    
    dev.off()
    
    message("Pipeline completed successfully. Outputs written to working directory.")

    writeLines(c(
        '"BIOC_NPARC_NPARC_TPP_ANALYSIS":',
        paste0('    NPARC: ', as.character(packageVersion('NPARC')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_nparc_tpp_analysis.csv versions.yml
    """
}

workflow BIOC_NPARC_NPARC_TPP_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ stauro_TPP_data_tidy ] ]

    main:
    BIOC_NPARC_NPARC_TPP_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_NPARC_NPARC_TPP_ANALYSIS.out.tables
    plots    = BIOC_NPARC_NPARC_TPP_ANALYSIS.out.plots
    objects  = BIOC_NPARC_NPARC_TPP_ANALYSIS.out.objects
    versions = BIOC_NPARC_NPARC_TPP_ANALYSIS.out.versions
}
