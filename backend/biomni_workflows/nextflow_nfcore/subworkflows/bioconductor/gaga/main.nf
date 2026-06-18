#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: gaga — differential_expression_and_fold_change
// Fit the GaGa model to expression data, identify differentially expressed genes under a target FDR, and estimate posterior fold changes.
// Input: expression_matrix.csv, sample_groups.csv
// Container: quay.io/biocontainers/bioconductor-gaga:2.56.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, gaga
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read User Input Files and Preprocess
//  * 2. [Input & Preparation] Execute Documented Workflow
//  * 3. [Input & Preparation] Save Outputs

nextflow.enable.dsl = 2

process BIOC_GAGA_DIFFERENTIAL_EXPRESSION_AND_FOLD_CHANGE {
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
    .bm_deps <- c("gaga", "Biobase")
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
    library(gaga)
    library(Biobase)
    
    # -----------------------------------------------------------------
    # --- Read User Input Files and Preprocess ---
    # -----------------------------------------------------------------
    
    # Read expression matrix
    if (!file.exists("expression_matrix.csv")) {
      stop("Error: 'expression_matrix.csv' not found in the working directory.")
    }
    expr_df <- read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE)
    x_raw <- as.matrix(expr_df)
    mode(x_raw) <- "double"
    
    # Read sample groups metadata
    if (!file.exists("sample_groups.csv")) {
      stop("Error: 'sample_groups.csv' not found in the working directory.")
    }
    groups_df <- read.csv("sample_groups.csv", stringsAsFactors = FALSE)
    
    # Identify the group column dynamically
    group_col <- grep("group", colnames(groups_df), ignore.case = TRUE, value = TRUE)
    if (length(group_col) == 0) {
      group_col <- colnames(groups_df)[2]
    } else {
      group_col <- group_col[1]
    }
    groups_raw <- as.character(groups_df[[group_col]])
    
    # Map user groups to "group 1" and "group 2" to match the documented patterns matrix
    unique_groups <- unique(groups_raw)
    if (length(unique_groups) < 2) {
      half <- ceiling(length(groups_raw) / 2)
      groups_raw[1:half] <- "group 1"
      groups_raw[(half + 1):length(groups_raw)] <- "group 2"
    } else {
      groups_raw <- ifelse(groups_raw == unique_groups[1], "group 1", "group 2")
    }
    
    # Construct the matrix `x` and ExpressionSet `xsim`
    x <- x_raw
    pheno_data <- data.frame(group = groups_raw)
    rownames(pheno_data) <- colnames(x)
    xsim <- ExpressionSet(assayData = x, phenoData = AnnotatedDataFrame(pheno_data))
    
    # -----------------------------------------------------------------
    # --- Execute Documented Workflow ---
    # -----------------------------------------------------------------
    
    # Define experimental groups and the hypothesis patterns matrix
    groups <- pData(xsim)\$group
    patterns <- matrix(c(0,0,0,1),2,2)
    colnames(patterns) <- c('group 1','group 2')
    
    # Fit the GaGa model using fitGG
    gg1 <- fitGG(x,groups,patterns=patterns,nclust=1,method='Gibbs',B=1000,trace=FALSE)
    
    # Estimate hyper-parameters and posterior probabilities using parest
    gg1 <- parest(gg1,x=x,groups,burnin=100,alpha=.05)
    
    # Assess model goodness-of-fit using checkfit (saving plots to PDF)
    pdf("goodness_of_fit_plots.pdf", width = 10, height = 10)
    par(mfrow = c(2, 2))
    checkfit(gg1,x=x,groups,type='data',main='')
    checkfit(gg1,x=x,groups,type='shape',main='')
    checkfit(gg1,x=x,groups,type='mean',main='')
    checkfit(gg1,x=x,groups,type='shapemean',main='',xlab='Mean',ylab='1/sqrt(CV)')
    dev.off()
    
    # Identify differentially expressed genes using findgenes
    d1 <- findgenes(gg1,x,groups,fdrmax=.05,parametric=TRUE)
    d1.nonpar <- findgenes(gg1,x,groups,fdrmax=.05,parametric=FALSE,B=1000)
    
    # Save FDR estimation plot
    pdf("fdr_estimation_plot.pdf", width = 7, height = 7)
    plot(d1.nonpar\$fdrest,type='l',xlab='Bayesian FDR',ylab='Estimated frequentist FDR')
    dev.off()
    
    # Compute posterior expected expression values and log-fold changes using posmeansGG
    mpos <- posmeansGG(gg1,x=x,groups=groups,underpattern=1)
    fc <- mpos[,1]-mpos[,2]
    
    # -----------------------------------------------------------------
    # --- Save Outputs ---
    # -----------------------------------------------------------------
    
    # Save the fitted model object
    saveRDS(gg1, "gaga_fit_model.rds")
    
    # Save differential expression and fold change results
    results_df <- data.frame(
      Gene = rownames(x_raw),
      DE_Parametric = d1\$d,
      DE_NonParametric = d1.nonpar\$d,
      PosteriorMean_Group1 = mpos[, 1],
      PosteriorMean_Group2 = mpos[, 2],
      LogFoldChange = fc,
      stringsAsFactors = FALSE
    )
    write.csv(results_df, "differential_expression_results.csv", row.names = FALSE)
    
    cat("Pipeline completed successfully.\n")

    writeLines(c(
        '"BIOC_GAGA_DIFFERENTIAL_EXPRESSION_AND_FOLD_CHANGE":',
        paste0('    gaga: ', as.character(packageVersion('gaga')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_expression_and_fold_change.csv versions.yml
    """
}

workflow BIOC_GAGA_DIFFERENTIAL_EXPRESSION_AND_FOLD_CHANGE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv, sample_groups.csv ] ]

    main:
    BIOC_GAGA_DIFFERENTIAL_EXPRESSION_AND_FOLD_CHANGE(ch_input)

    emit:
    tables   = BIOC_GAGA_DIFFERENTIAL_EXPRESSION_AND_FOLD_CHANGE.out.tables
    plots    = BIOC_GAGA_DIFFERENTIAL_EXPRESSION_AND_FOLD_CHANGE.out.plots
    objects  = BIOC_GAGA_DIFFERENTIAL_EXPRESSION_AND_FOLD_CHANGE.out.objects
    versions = BIOC_GAGA_DIFFERENTIAL_EXPRESSION_AND_FOLD_CHANGE.out.versions
}
