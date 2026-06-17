#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scShapes — differential_distribution_analysis
// Identify the best-fit distribution for genes in scRNA-seq data and detect genes changing distribution shapes between treatment conditions.
// Input: counts, covariates, lib_size, ifnb.distr
// Container: quay.io/biocontainers/bioconductor-scshapes:1.16.0--r45hdfd78af_0
// R packages: BiocParallel, scShapes
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, scShapes
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter genes based on zero expression percentage using filter_counts
//  * 2. [Core Analysis] Perform Kolmogorov-Smirnov test using ks_test to select genes belonging to the ZINB family
//  * 3. [Core Analysis] Select significant genes using ks_sig and subset the count matrix
//  * 4. [Core Analysis] Fit Poisson, NB, ZIP, and ZINB models using fit_models
//  * 5. [Core Analysis] Calculate BIC values using model_bic and select the model with the least BIC using lbic_model
//  * 6. [Core Analysis] Perform goodness-of-fit testing using gof_model
//  * 7. [Core Analysis] Select the final best-fit model using select_model
//  * 8. [Core Analysis] Extract model parameters using model_param
//  * 9. [Core Analysis] Identify genes changing distribution shape between conditions using change_shape

nextflow.enable.dsl = 2

process BIOC_SCSHAPES_DIFFERENTIAL_DISTRIBUTION_ANALYSIS {
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
    .bm_deps <- c("BiocParallel", "scShapes")
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
        library(scShapes)
        library(BiocParallel)
        
        # Set seed for reproducibility
        set.seed(0xBEEF)
        
        # Helper function to read input files robustly
        read_input <- function(base_name) {
          rds_path <- paste0(base_name, ".rds")
          csv_path <- paste0(base_name, ".csv")
          
          if (file.exists(rds_path)) {
            return(readRDS(rds_path))
          } else if (file.exists(csv_path)) {
            df <- read.csv(csv_path, row.names = 1, check.names = FALSE)
            if (base_name == "counts") {
              return(as.matrix(df))
            } else if (base_name == "covariates" || base_name == "lib_size") {
              if (ncol(df) == 1) {
                return(df[[1]])
              } else {
                return(as.matrix(df))
              }
            }
            return(df)
          } else if (file.exists(base_name)) {
            return(readRDS(base_name))
          } else {
            stop(paste("Required input file not found:", base_name))
          }
        }
        
        # Load user inputs
        scData <- list()
        scData\$counts <- read_input("counts")
        scData\$covariates <- read_input("covariates")
        scData\$lib_size <- read_input("lib_size")
        ifnb.distr <- read_input("ifnb.distr")
        
        # 1. Filter genes based on zero expression percentage
        scData_filt <- filter_counts(scData\$counts, perc.zero = 0.1)
        
        # 2. Perform Kolmogorov-Smirnov test to select genes belonging to the ZINB family
        scData_KS <- ks_test(counts=scData_filt, cexpr=scData\$covariates, lib.size=scData\$lib_size, BPPARAM=SnowParam(workers=8,type="SOCK"))
        
        # 3. Select significant genes and subset the count matrix
        scData_KS_sig <- ks_sig(scData_KS)
        scData.sig.genes <- scData_filt[rownames(scData_filt) %in% names(scData_KS_sig\$genes),]
        
        # 4. Fit Poisson, NB, ZIP, and ZINB models
        scData_models <- fit_models(counts=scData.sig.genes, cexpr=scData\$covariates, lib.size=scData\$lib_size, BPPARAM=SnowParam(workers=8,type="SOCK"))
        
        # 5. Calculate BIC values and select the model with the least BIC
        scData_bicvals <- model_bic(scData_models)
        scData_least.bic <- lbic_model(scData_bicvals, scData.sig.genes)
        
        # 6. Perform goodness-of-fit testing
        scData_gof <- gof_model(scData_least.bic, cexpr=scData\$covariates, lib.size=scData\$lib_size, BPPARAM=SnowParam(workers=8,type="SOCK"))
        
        # 7. Select the final best-fit model
        scData_fit <- select_model(scData_gof)
        
        # 8. Extract model parameters
        scData_params <- model_param(scData_models, scData_fit, model=NULL)
        
        # 9. Identify genes changing distribution shape between conditions
        ifnb.DD.genes <- change_shape(ifnb.distr)
        
        # Save outputs to the working directory
        saveRDS(scData_filt, "scData_filt.rds")
        saveRDS(scData_KS, "scData_KS.rds")
        saveRDS(scData_KS_sig, "scData_KS_sig.rds")
        saveRDS(scData_models, "scData_models.rds")
        saveRDS(scData_bicvals, "scData_bicvals.rds")
        saveRDS(scData_least.bic, "scData_least.bic.rds")
        saveRDS(scData_gof, "scData_gof.rds")
        saveRDS(scData_fit, "scData_fit.rds")
        write.csv(scData_fit, "scData_fit.csv", row.names = TRUE)
        saveRDS(scData_params, "scData_params.rds")
        saveRDS(ifnb.DD.genes, "ifnb.DD.genes.rds")
        
        # Write out text summaries of the results
        sink("summary_report.txt")
        cat("=== scShapes Analysis Summary ===\n\n")
        cat("Number of filtered genes:", nrow(scData_filt), "\n")
        cat("Number of significant KS genes:", length(scData_KS_sig\$genes), "\n")
        cat("Distribution of best-fit models:\n")
        print(table(scData_fit))
        cat("\nNumber of shape-changing genes identified:", length(unlist(ifnb.DD.genes)), "\n")
        sink()

    writeLines(c(
        '"BIOC_SCSHAPES_DIFFERENTIAL_DISTRIBUTION_ANALYSIS":',
        paste0('    scShapes: ', as.character(packageVersion('scShapes')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_distribution_analysis.csv versions.yml
    """
}

workflow BIOC_SCSHAPES_DIFFERENTIAL_DISTRIBUTION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts, covariates, lib_size, ifnb.distr ] ]

    main:
    BIOC_SCSHAPES_DIFFERENTIAL_DISTRIBUTION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SCSHAPES_DIFFERENTIAL_DISTRIBUTION_ANALYSIS.out.tables
    plots    = BIOC_SCSHAPES_DIFFERENTIAL_DISTRIBUTION_ANALYSIS.out.plots
    objects  = BIOC_SCSHAPES_DIFFERENTIAL_DISTRIBUTION_ANALYSIS.out.objects
    versions = BIOC_SCSHAPES_DIFFERENTIAL_DISTRIBUTION_ANALYSIS.out.versions
}
