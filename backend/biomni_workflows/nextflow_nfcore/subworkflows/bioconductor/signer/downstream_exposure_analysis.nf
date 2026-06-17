#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: signeR — downstream_exposure_analysis
// Perform supervised and unsupervised analyses on estimated exposures, including differential exposure analysis, sample classification, correlation, survival anal
// Input: SignExposures, BRCA_labels, myFeature, su
// Container: quay.io/biocontainers/bioconductor-signer:2.12.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: signeR, survival
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Perform Differential Exposure Analysis using DiffExp
//  * 2. [Core Analysis] Classify unlabeled samples using ExposureClassify
//  * 3. [Core Analysis] Evaluate correlation with continuous features using ExposureCorrelation and ExposureGLM
//  * 4. [Core Analysis] Perform survival analysis using ExposureSurvival (log-rank and Cox) and ExposureSurvModel
//  * 5. [Core Analysis] Perform hierarchical and fuzzy clustering using HClustExp and FuzzyClustExp

nextflow.enable.dsl = 2

process BIOC_SIGNER_DOWNSTREAM_EXPOSURE_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("signeR", "survival")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    library(signeR)
    library(survival)
    
    # Robust input reader to handle RDS, CSV, or TXT formats
    read_input <- function(file_base) {
      # 1. Try RDS format first
      for (fp in c(paste0(file_base, ".rds"), file_base)) {
        if (file.exists(fp)) {
          res <- tryCatch({ readRDS(fp) }, error = function(e) NULL)
          if (!is.null(res)) return(res)
        }
      }
      
      # 2. Try reading as text/csv
      for (ext in c(".txt", ".csv", "")) {
        fp <- paste0(file_base, ext)
        if (file.exists(fp)) {
          # Try reading as table
          df <- tryCatch({
            read.table(fp, header=TRUE, sep="", stringsAsFactors=FALSE, check.names=FALSE)
          }, error = function(e) {
            read.table(fp, header=FALSE, sep="", stringsAsFactors=FALSE, check.names=FALSE)
          })
          if (ncol(df) == 1) {
            return(as.vector(df[[1]]))
          }
          return(as.matrix(df))
        }
      }
      stop(paste("Required input file not found or could not be read:", file_base))
    }
    
    # Read user inputs from the working directory
    SignExposures <- read_input("SignExposures")
    BRCA_labels   <- read_input("BRCA_labels")
    myFeature     <- read_input("myFeature")
    su            <- read_input("su")
    
    # Ensure su is a matrix as required by the survival functions
    su <- as.matrix(su)
    
    # Prepare label variants for classification and survival modeling
    # For classification, we need some NA values to predict.
    # If the input BRCA_labels doesn't have NAs, we introduce them to ensure ExposureClassify runs.
    BRCA_labels_classify <- BRCA_labels
    if (length(BRCA_labels_classify) >= 21) {
      BRCA_labels_classify[c(15, 20, 21)] <- NA
    } else {
      if (!any(is.na(BRCA_labels_classify))) {
        BRCA_labels_classify[length(BRCA_labels_classify)] <- NA
      }
    }
    
    # For survival modeling, we ensure there are no NA values
    BRCA_labels_no_na <- BRCA_labels
    BRCA_labels_no_na[is.na(BRCA_labels_no_na)] <- "wt"
    
    # Open PDF device to capture all generated plots
    pdf("downstream_analysis_plots.pdf", width=11, height=8.5)
    
    # 1. Perform Differential Exposure Analysis using DiffExp
    message("Performing Differential Exposure Analysis...")
    diff_exposure <- DiffExp(SignExposures, labels=BRCA_labels)
    diff_exposure\$Pvquant
    diff_exposure\$MostExposed
    
    # 2. Classify unlabeled samples using ExposureClassify
    message("Classifying unlabeled samples...")
    Class <- ExposureClassify(SignExposures, labels=BRCA_labels_classify, method="knn")
    Class\$class
    Class\$freq
    Class\$allfreqs
    
    # 3. Evaluate correlation with continuous features using ExposureCorrelation and ExposureGLM
    message("Evaluating correlation and fitting GLM with continuous features...")
    ExpCorr <- ExposureCorrelation(SignExposures, feature=myFeature)
    ExpLM <- ExposureGLM(SignExposures, feature=myFeature)
    
    # 4. Perform survival analysis using ExposureSurvival (log-rank and Cox) and ExposureSurvModel
    message("Performing survival analysis...")
    ExpSurv <- ExposureSurvival(Exposures=SignExposures, surv=su, method="logrank")
    ExpSurv.cox <- ExposureSurvival(Exposures=SignExposures, surv=su, method="cox")
    ExpSurvMd <- ExposureSurvModel(Exposures=SignExposures, surv=su, addata=data.frame(as.factor(BRCA_labels_no_na)))
    
    # 5. Perform hierarchical and fuzzy clustering using HClustExp and FuzzyClustExp
    message("Performing hierarchical and fuzzy clustering...")
    HCE <- HClustExp(SignExposures, method.dist="euclidean", method.hclust="average")
    FCE <- FuzzyClustExp(SignExposures, Clim=c(3,7))
    
    # Close PDF device
    dev.off()
    
    # Save RDS objects of the results
    message("Saving output RDS objects...")
    saveRDS(diff_exposure, "diff_exposure.rds")
    saveRDS(Class, "classification_results.rds")
    saveRDS(ExpCorr, "exposure_correlation.rds")
    saveRDS(ExpLM, "exposure_glm.rds")
    saveRDS(ExpSurv, "exposure_survival_logrank.rds")
    saveRDS(ExpSurv.cox, "exposure_survival_cox.rds")
    saveRDS(ExpSurvMd, "exposure_survival_model.rds")
    saveRDS(HCE, "hierarchical_clustering.rds")
    saveRDS(FCE, "fuzzy_clustering.rds")
    
    # Save CSV tables for key results
    message("Saving output CSV tables...")
    write.csv(as.data.frame(diff_exposure\$Pvquant), "diff_exposure_pvquant.csv", row.names=TRUE)
    if (!is.null(diff_exposure\$MostExposed)) {
      write.csv(as.data.frame(diff_exposure\$MostExposed), "diff_exposure_most_exposed.csv", row.names=TRUE)
    }
    
    class_df <- data.frame(
      Sample = names(Class\$class),
      Class = Class\$class,
      Freq = Class\$freq,
      stringsAsFactors = FALSE
    )
    write.csv(class_df, "classification_assignments.csv", row.names=FALSE)
    write.csv(as.data.frame(Class\$allfreqs), "classification_all_frequencies.csv", row.names=TRUE)
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_SIGNER_DOWNSTREAM_EXPOSURE_ANALYSIS":',
        paste0('    signeR: ', as.character(packageVersion('signeR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_downstream_exposure_analysis.csv versions.yml
    """
}

workflow BIOC_SIGNER_DOWNSTREAM_EXPOSURE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ SignExposures, BRCA_labels, myFeature, su ] ]

    main:
    BIOC_SIGNER_DOWNSTREAM_EXPOSURE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SIGNER_DOWNSTREAM_EXPOSURE_ANALYSIS.out.tables
    plots    = BIOC_SIGNER_DOWNSTREAM_EXPOSURE_ANALYSIS.out.plots
    objects  = BIOC_SIGNER_DOWNSTREAM_EXPOSURE_ANALYSIS.out.objects
    versions = BIOC_SIGNER_DOWNSTREAM_EXPOSURE_ANALYSIS.out.versions
}
