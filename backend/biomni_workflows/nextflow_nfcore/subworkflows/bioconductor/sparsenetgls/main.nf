#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: sparsenetgls — multivariate_gls_regression
// Perform multivariate GLS regression using GGM-based covariance estimation, convert coefficients to original scale, and select optimal parameters based on minima
// Input: databand_Y, databand_X
// Container: quay.io/biocontainers/bioconductor-sparsenetgls:1.28.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Matrix, sparsenetgls
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Estimate precision and covariance matrices and fit GLS regression using sparsenetgls()
//  * 2. [Core Analysis] Convert regression coefficients to original scale using convertbeta()
//  * 3. [Core Analysis] Select optimal lambda and distance parameters using minimal variance of beta, AIC, or BIC
//  * 4. [Visualization & Output] Visualize the results using plotsngls()

nextflow.enable.dsl = 2

process BIOC_SPARSENETGLS_MULTIVARIATE_GLS_REGRESSION {
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
    .bm_deps <- c("sparsenetgls", "Matrix", "MASS")
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
    library(sparsenetgls)
    library(Matrix)
    library(MASS)
    
    # Helper function to load user input files robustly
    load_input_matrix <- function(base_name) {
      rds_path <- paste0(base_name, ".rds")
      csv_path <- paste0(base_name, ".csv")
      txt_path <- paste0(base_name, ".txt")
      
      if (file.exists(rds_path)) {
        message("Loading ", rds_path)
        return(as.matrix(readRDS(rds_path)))
      } else if (file.exists(csv_path)) {
        message("Loading ", csv_path)
        df <- read.csv(csv_path, header = TRUE, row.names = 1, check.names = FALSE)
        return(as.matrix(df))
      } else if (file.exists(txt_path)) {
        message("Loading ", txt_path)
        df <- read.table(txt_path, header = TRUE, row.names = 1, check.names = FALSE)
        return(as.matrix(df))
      } else if (file.exists(base_name)) {
        message("Loading ", base_name)
        if (grepl("\\\\.rds\$", base_name, ignore.case = TRUE)) {
          return(as.matrix(readRDS(base_name)))
        } else {
          return(as.matrix(read.csv(base_name, header = TRUE, row.names = 1, check.names = FALSE)))
        }
      } else {
        stop(paste("Error: Required input file not found for:", base_name))
      }
    }
    
    # 1. Read user input files
    databand_Y <- load_input_matrix("databand_Y")
    databand_X <- load_input_matrix("databand_X")
    
    # 2. Estimate precision and covariance matrices and fit GLS regression
    fitgls <- sparsenetgls(databand_Y, databand_X, nlambda=10, 
    ndist=5, method="glasso")
    
    # 3. Convert the regression coefficients to its original scale
    q <- dim(databand_X)[2]
    nlambda=10
    
    betagls <- matrix(nrow=nlambda, ncol=q+1)
    for (i in seq_len(nlambda))   
    betagls[i,] <- convertbeta(Y=databand_Y, X=databand_X, q=q+1,
    beta0=fitgls\$beta[,i])\$betaconv
    
    # 4. Beta selection 
    
    # select lambda and dist value based on the minimal variance of beta
    ndist <- max(fitgls\$power)-1
    tr_gamma <- matrix(nrow=10, ncol=ndist-1)
    
    for (j in seq_len(ndist-1))
        for (i in seq_len(nlambda)) 
            tr_gamma[i,j] <- (sum(diag(fitgls\$covBeta[,,j,i]))) 
    
    select.lambda.dist <- which(tr_gamma==min(tr_gamma), arr.ind=TRUE)
    select.lambda.dist
    betagls_select <- betagls[select.lambda.dist[1],]
    
    # row is lambda and column is dist
    varbeta <- diag(fitgls\$covBeta[,,ndist,select.lambda.dist[1]])
    
    # select lambda and dist value based on the AIC and BIC
    select.lambda.dist2 <- which(fitgls\$bic==min(fitgls\$bic,na.rm=TRUE),
    arr.ind=TRUE)
    select.lambda.dist3 <- which(fitgls\$aic==min(fitgls\$aic,na.rm=TRUE),
    arr.ind=TRUE)
    varbeta_bic <- diag(fitgls\$covBeta[,,ndist,select.lambda.dist2[1]])
    varbeta_aic <- diag(fitgls\$covBeta[,,ndist,select.lambda.dist3[1]])
    
    # 5. Visualize the results
    pdf("plotsngls_output.pdf", width = 10, height = 8)
    plotsngls(fitgls,ith_lambda=5)
    dev.off()
    
    # 6. Save outputs to files
    # Save selected beta coefficients
    write.csv(data.frame(Beta = betagls_select), "selected_beta_min_var.csv", row.names = FALSE)
    
    # Save variances of beta coefficients
    var_df <- data.frame(
      Variable = seq_along(varbeta),
      Var_MinVar = varbeta,
      Var_BIC = varbeta_bic,
      Var_AIC = varbeta_aic
    )
    write.csv(var_df, "beta_variances.csv", row.names = FALSE)
    
    # Save parameter selection summary
    selection_summary <- data.frame(
      Criterion = c("Minimal_Variance", "BIC", "AIC"),
      Selected_Lambda_Index = c(select.lambda.dist[1], select.lambda.dist2[1], select.lambda.dist3[1]),
      Selected_Dist_Index = c(select.lambda.dist[2], select.lambda.dist2[2], select.lambda.dist3[2])
    )
    write.csv(selection_summary, "parameter_selection_summary.csv", row.names = FALSE)
    
    # Save full fitgls object
    saveRDS(fitgls, "fitgls_result.rds")
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_SPARSENETGLS_MULTIVARIATE_GLS_REGRESSION":',
        paste0('    sparsenetgls: ', as.character(packageVersion('sparsenetgls')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multivariate_gls_regression.csv versions.yml
    """
}

workflow BIOC_SPARSENETGLS_MULTIVARIATE_GLS_REGRESSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ databand_Y, databand_X ] ]

    main:
    BIOC_SPARSENETGLS_MULTIVARIATE_GLS_REGRESSION(ch_input)

    emit:
    tables   = BIOC_SPARSENETGLS_MULTIVARIATE_GLS_REGRESSION.out.tables
    plots    = BIOC_SPARSENETGLS_MULTIVARIATE_GLS_REGRESSION.out.plots
    objects  = BIOC_SPARSENETGLS_MULTIVARIATE_GLS_REGRESSION.out.objects
    versions = BIOC_SPARSENETGLS_MULTIVARIATE_GLS_REGRESSION.out.versions
}
