#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: iCARE — absolute_risk_estimation
// Estimate absolute risk of disease over a specified age interval using SNP profiles and/or classical risk factor profiles.
// Input: model.snp.info, model.disease.incidence.rates, model.competing.incidence.rates, apply.snp.profile, apply.cov.profile, model.ref.dataset
// Container: quay.io/biocontainers/bioconductor-icare:1.38.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: iCARE
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Compute absolute risk using computeAbsoluteRisk with SNP-only data (with or without individual profiles)
//  * 2. [Core Analysis] Compute absolute risk using computeAbsoluteRisk with combined SNP and classical risk factor data
//  * 3. [Visualization & Output] Summarize and plot risk distributions

nextflow.enable.dsl = 2

process BIOC_ICARE_ABSOLUTE_RISK_ESTIMATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("iCARE")
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
    library(iCARE)
    
    # Helper function to robustly read input files of various formats (RDS, CSV, TSV)
    read_input <- function(file_path) {
      if (!file.exists(file_path)) {
        stop(paste("Error: Required file", file_path, "does not exist in the working directory."))
      }
      
      # Try reading as RDS
      res <- tryCatch({
        readRDS(file_path)
      }, error = function(e) {
        NULL
      })
      if (!is.null(res)) return(res)
      
      # Try reading as CSV
      res <- tryCatch({
        read.csv(file_path, stringsAsFactors = FALSE)
      }, error = function(e) {
        NULL
      })
      if (!is.null(res)) return(res)
      
      # Try reading as table (TSV/space-separated)
      res <- tryCatch({
        read.table(file_path, header = TRUE, stringsAsFactors = FALSE)
      }, error = function(e) {
        NULL
      })
      if (!is.null(res)) return(res)
      
      stop(paste("Error: Failed to read file", file_path))
    }
    
    # ----------------------------------------------------------------------
    # 1. Load User Input Files
    # ----------------------------------------------------------------------
    
    bc_72_snps <- read_input("model.snp.info")
    bc_inc <- read_input("model.disease.incidence.rates")
    mort_inc <- read_input("model.competing.incidence.rates")
    new_snp_prof <- read_input("apply.snp.profile")
    new_cov_prof <- read_input("apply.cov.profile")
    ref_cov_dat_raw <- read_input("model.ref.dataset")
    
    # Ensure incidence rates are in matrix format as required by iCARE
    if (is.data.frame(bc_inc)) {
      bc_inc <- as.matrix(bc_inc)
    }
    if (is.data.frame(mort_inc)) {
      mort_inc <- as.matrix(mort_inc)
    }
    
    # Check for optional but necessary covariate model files if not bundled in model.ref.dataset
    bc_model_formula <- NULL
    if (file.exists("model.formula")) {
      bc_model_formula <- read_input("model.formula")
    }
    bc_model_cov_info <- NULL
    if (file.exists("model.cov.info")) {
      bc_model_cov_info <- read_input("model.cov.info")
    }
    bc_model_log_or <- NULL
    if (file.exists("model.log.RR")) {
      bc_model_log_or <- read_input("model.log.RR")
    }
    
    # If model.ref.dataset is a list containing the model structures, extract them
    if (is.list(ref_cov_dat_raw) && !is.data.frame(ref_cov_dat_raw)) {
      ref_cov_dat <- ref_cov_dat_raw\$ref_cov_dat
      if (is.null(bc_model_cov_info)) bc_model_cov_info <- ref_cov_dat_raw\$bc_model_cov_info
      if (is.null(bc_model_log_or)) bc_model_log_or <- ref_cov_dat_raw\$bc_model_log_or
      if (is.null(bc_model_formula)) bc_model_formula <- ref_cov_dat_raw\$bc_model_formula
    } else {
      ref_cov_dat <- ref_cov_dat_raw
    }
    
    # Ensure formula is of class 'formula'
    if (!is.null(bc_model_formula) && is.character(bc_model_formula)) {
      bc_model_formula <- as.formula(bc_model_formula)
    }
    
    # Set seed for reproducibility of SNP imputation
    set.seed(50)
    
    # ----------------------------------------------------------------------
    # 2. Compute Absolute Risk (SNP-only, without individual profiles)
    # ----------------------------------------------------------------------
    
    res_snps_miss = computeAbsoluteRisk(model.snp.info = bc_72_snps, 
                          model.disease.incidence.rates = bc_inc,
                          model.competing.incidence.rates = mort_inc, 
                          apply.age.start = 50, 
                          apply.age.interval.length = 30,
                          return.refs.risk=TRUE)
    
    # ----------------------------------------------------------------------
    # 3. Compute Absolute Risk (SNP-only, with individual profiles)
    # ----------------------------------------------------------------------
    
    res_snps_dat = computeAbsoluteRisk(model.snp.info = bc_72_snps, 
                                    model.disease.incidence.rates = bc_inc,
                                    model.competing.incidence.rates = mort_inc, 
                                    apply.age.start = 50, 
                                    apply.age.interval.length = 30, 
                                    apply.snp.profile = new_snp_prof, 
                                    return.refs.risk = TRUE)
    
    # ----------------------------------------------------------------------
    # 4. Compute Absolute Risk (Combined SNP and Classical Risk Factors)
    # ----------------------------------------------------------------------
    
    res_covs_snps = computeAbsoluteRisk(model.formula=bc_model_formula, 
                                             model.cov.info=bc_model_cov_info,
                                             model.snp.info=bc_72_snps,
                                             model.log.RR=bc_model_log_or,
                                             model.ref.dataset=ref_cov_dat,
                                             model.disease.incidence.rates=bc_inc,
                                             model.competing.incidence.rates=mort_inc, 
                                             model.bin.fh.name="famhist",
                                             apply.age.start=50, 
                                             apply.age.interval.length=30,
                                             apply.cov.profile=new_cov_prof,
                                             apply.snp.profile=new_snp_prof, 
                                             return.refs.risk=TRUE)
    
    # ----------------------------------------------------------------------
    # 5. Summarize and Plot Risk Distributions
    # ----------------------------------------------------------------------
    
    # Print summaries to standard output
    cat("=== Summary of SNP-only Risk (Missing Profiles) ===\n")
    print(summary(res_snps_miss\$risk))
    cat("\n=== Summary of SNP-only Referent Risk (Missing Profiles) ===\n")
    print(summary(res_snps_miss\$refs.risk))
    
    cat("\n=== Summary of SNP-only Referent Risk (With Profiles) ===\n")
    print(summary(res_snps_dat\$refs.risk))
    
    cat("\n=== Details of Combined Covariate and SNP Risk Model ===\n")
    print(res_covs_snps\$details)
    
    # Generate PDF plots
    pdf("absolute_risk_plots.pdf", width = 8, height = 6)
    
    # Plot 1: SNP-only Risk Stratification (Missing Profiles)
    plot(density(res_snps_miss\$risk), lwd=2, 
         main="SNP-only Risk Stratification: Ages 50-80", 
         xlab="Absolute Risk of Breast Cancer")
    
    # Plot 2: Referent SNP-only Risk Distribution (With Profiles)
    plot(density(res_snps_dat\$refs.risk), lwd=2, 
         main="Referent SNP-only Risk Distribution: Ages 50-80",
         xlab="Absolute Risk of Breast Cancer")
    abline(v=res_snps_dat\$risk, col="red")
    legend("topright", legend="New Profiles", col="red", lwd=1)
    
    # Plot 3: Referent SNP-only Risk Distribution (Alternative limits)
    plot(density(res_snps_dat\$refs.risk),
         xlim = c(0.04, 0.18), xlab = "Absolute Risk of Breast Cancer",
         main = "Referent SNP-only Risk Distribution: Ages 50-80 years")
    abline(v = res_snps_dat\$risk, col = "red")
    legend("topright", legend = "New profiles", col = "red", lwd = 1)
    
    dev.off()
    
    # ----------------------------------------------------------------------
    # 6. Save Outputs to Disk
    # ----------------------------------------------------------------------
    
    # Save RDS objects of the full results
    saveRDS(res_snps_miss, "res_snps_miss.rds")
    saveRDS(res_snps_dat, "res_snps_dat.rds")
    saveRDS(res_covs_snps, "res_covs_snps.rds")
    
    # Save CSV tables of the risk estimates and details
    write.csv(data.frame(Risk_Estimate = res_snps_miss\$risk), "risk_estimates_snps_miss.csv", row.names = FALSE)
    write.csv(data.frame(Referent_Risk = res_snps_miss\$refs.risk), "referent_risks_snps_miss.csv", row.names = FALSE)
    write.csv(data.frame(Risk_Estimate = res_snps_dat\$risk), "risk_estimates_snps_dat.csv", row.names = FALSE)
    write.csv(res_covs_snps\$details, "risk_details_covs_snps.csv", row.names = FALSE)
    
    cat("\nPipeline completed successfully. Outputs written to working directory.\n")

    writeLines(c(
        '"BIOC_ICARE_ABSOLUTE_RISK_ESTIMATION":',
        paste0('    iCARE: ', as.character(packageVersion('iCARE')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_absolute_risk_estimation.csv versions.yml
    """
}

workflow BIOC_ICARE_ABSOLUTE_RISK_ESTIMATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ model.snp.info, model.disease.incidence.rates, model.competing.incidence.rates, apply.snp.profile, apply.cov.profile, model.ref.dataset ] ]

    main:
    BIOC_ICARE_ABSOLUTE_RISK_ESTIMATION(ch_input)

    emit:
    tables   = BIOC_ICARE_ABSOLUTE_RISK_ESTIMATION.out.tables
    plots    = BIOC_ICARE_ABSOLUTE_RISK_ESTIMATION.out.plots
    objects  = BIOC_ICARE_ABSOLUTE_RISK_ESTIMATION.out.objects
    versions = BIOC_ICARE_ABSOLUTE_RISK_ESTIMATION.out.versions
}
