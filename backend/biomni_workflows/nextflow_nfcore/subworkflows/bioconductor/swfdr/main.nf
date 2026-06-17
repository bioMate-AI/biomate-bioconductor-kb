#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: swfdr — covariate_conditioned_fdr
// Estimate the proportion of true null hypotheses and compute adjusted q-values while conditioning on one or more numeric covariates.
// Input: BMI_GIANT_GWAS_sample
// Container: quay.io/biocontainers/bioconductor-swfdr:1.36.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ggplot2, reshape2, swfdr
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Construct a numeric design matrix from covariates using model.matrix
//  * 2. [Core Analysis] Estimate the conditional proportion of nulls (pi0) using lm_pi0
//  * 3. [Core Analysis] Compute conditional q-values using lm_qvalue

nextflow.enable.dsl = 2

process BIOC_SWFDR_COVARIATE_CONDITIONED_FDR {
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
    .bm_deps <- c("swfdr", "reshape2", "ggplot2")
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
    library(swfdr)
    library(splines)
    
    # ----------------------------------------------------------------
    # 1. Read User Input
    # ----------------------------------------------------------------
    # The pipeline reads the file 'BMI_GIANT_GWAS_sample' from the working directory.
    # We check for common extensions (.csv, .rds) or the exact filename.
    input_file <- "BMI_GIANT_GWAS_sample"
    if (file.exists(paste0(input_file, ".csv"))) {
      BMI_GIANT_GWAS_sample <- read.csv(paste0(input_file, ".csv"), stringsAsFactors = TRUE)
    } else if (file.exists(paste0(input_file, ".rds"))) {
      BMI_GIANT_GWAS_sample <- readRDS(paste0(input_file, ".rds"))
    } else if (file.exists(input_file)) {
      BMI_GIANT_GWAS_sample <- tryCatch({
        readRDS(input_file)
      }, error = function(e) {
        read.table(input_file, header = TRUE, sep = "\t", stringsAsFactors = TRUE)
      })
    } else {
      stop("Required input file 'BMI_GIANT_GWAS_sample' (CSV or RDS) not found in the working directory.")
    }
    
    # Ensure Freq_MAF_Int_Hapmap is treated as a factor for model.matrix
    if (!is.factor(BMI_GIANT_GWAS_sample\$Freq_MAF_Int_Hapmap)) {
      BMI_GIANT_GWAS_sample\$Freq_MAF_Int_Hapmap <- as.factor(BMI_GIANT_GWAS_sample\$Freq_MAF_Int_Hapmap)
    }
    
    # ----------------------------------------------------------------
    # 2. Execute Documented Workflow
    # ----------------------------------------------------------------
    
    # Stage 1: Construct a numeric design matrix from covariates using model.matrix
    X <- model.matrix(~ splines::ns(N,5) + Freq_MAF_Int_Hapmap, data = BMI_GIANT_GWAS_sample)[,-1]
    
    # Stage 2: Estimate the conditional proportion of nulls (pi0) using lm_pi0
    pi0x <- lm_pi0(BMI_GIANT_GWAS_sample\$p, X=X)
    
    # Stage 3: Compute conditional q-values using lm_qvalue
    GWAS <- BMI_GIANT_GWAS_sample
    GWAS_lm_qvalue <- lm_qvalue(GWAS\$p, X=X)
    
    # ----------------------------------------------------------------
    # 3. Save Outputs
    # ----------------------------------------------------------------
    
    # Create a combined results data frame
    results_df <- GWAS
    results_df\$pi0_conditioned <- pi0x\$pi0
    results_df\$qvalue_conditioned <- GWAS_lm_qvalue\$qvalues
    
    # Write CSV table
    write.csv(results_df, "conditioned_fdr_results.csv", row.names = FALSE)
    
    # Save RDS objects
    saveRDS(list(pi0_model = pi0x, qvalue_model = GWAS_lm_qvalue, results = results_df), "conditioned_fdr_results.rds")
    
    # Optional Plotting Sub-step (wrapped in tryCatch for robustness)
    tryCatch({
      library(reshape2)
      library(ggplot2)
    
      # Prepare data for plotting as in the vignette
      plot_data <- BMI_GIANT_GWAS_sample
      plot_data\$fitted0.8 <- pi0x\$pi0.lambda[, round(pi0x\$lambda, 2) == 0.8]
      plot_data\$fitted0.9 <- pi0x\$pi0.lambda[, round(pi0x\$lambda, 2) == 0.9]
      plot_data\$fitted.final.smooth <- pi0x\$pi0
    
      ldf <- reshape2::melt(plot_data,
                            id.vars = colnames(plot_data)[-grep("fitted", colnames(plot_data))],
                            value.name = "pi0", variable.name = "lambda")
      ldf\$lambda <- as.character(ldf\$lambda)
      ldf\$lambda[ldf\$lambda == "fitted0.8"] <- "lambda=0.8"
      ldf\$lambda[ldf\$lambda == "fitted0.9"] <- "lambda=0.9"
      ldf\$lambda[ldf\$lambda == "fitted.final.smooth"] <- "final smoothed pi0(x)"
    
      p <- ggplot(ldf, aes(x = N, y = pi0)) +
        geom_line(aes(col = Freq_MAF_Int_Hapmap, linetype = lambda)) +
        ylab("Estimated proportion of nulls") +
        guides(color = guide_legend(title = "MAF in HapMap CEU population"),
               linetype = guide_legend(title = "Estimate")) +
        theme_minimal()
    
      ggsave("pi0_vs_covariates.pdf", plot = p, width = 8, height = 6)
    }, error = function(e) {
      warning("Plotting failed or required packages (ggplot2/reshape2) were not available: ", e\$message)
    })
    
    cat("Pipeline completed successfully. Outputs written to 'conditioned_fdr_results.csv', 'conditioned_fdr_results.rds', and 'pi0_vs_covariates.pdf'.\n")

    writeLines(c(
        '"BIOC_SWFDR_COVARIATE_CONDITIONED_FDR":',
        paste0('    swfdr: ', as.character(packageVersion('swfdr')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_covariate_conditioned_fdr.csv versions.yml
    """
}

workflow BIOC_SWFDR_COVARIATE_CONDITIONED_FDR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ BMI_GIANT_GWAS_sample ] ]

    main:
    BIOC_SWFDR_COVARIATE_CONDITIONED_FDR(ch_input)

    emit:
    tables   = BIOC_SWFDR_COVARIATE_CONDITIONED_FDR.out.tables
    plots    = BIOC_SWFDR_COVARIATE_CONDITIONED_FDR.out.plots
    objects  = BIOC_SWFDR_COVARIATE_CONDITIONED_FDR.out.objects
    versions = BIOC_SWFDR_COVARIATE_CONDITIONED_FDR.out.versions
}
