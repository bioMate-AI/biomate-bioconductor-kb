#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GeneMeta — manual_meta_analysis
// Perform step-by-step meta-analysis of two-sample microarray data to calculate effect sizes, evaluate heterogeneity, and fit fixed or random effects models.
// Input: Split1, Split2, Split1.ER, Split2.ER
// Container: quay.io/biocontainers/bioconductor-genemeta:1.82.0--r45hdfd78af_0
// R packages: Biobase, GeneMeta, RColorBrewer
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, GeneMeta
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Calculate effect size d for each study using getdF
//  * 2. [Core Analysis] Adjust d values using dstar
//  * 3. [Core Analysis] Calculate variance of adjusted d using sigmad
//  * 4. [Core Analysis] Compute Cochran's Q statistic using f.Q to test for
//  * 5. [Core Analysis] Fit Fixed Effects Model (FEM) using mu.tau2 and var.tau2
//  * 6. [Core Analysis] Estimate between-study variance tau^2 using tau2.DL and

nextflow.enable.dsl = 2

process BIOC_GENEMETA_MANUAL_META_ANALYSIS {
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
    .bm_deps <- c("Biobase", "GeneMeta", "RColorBrewer")
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
    library(GeneMeta)
    library(Biobase)
    
    # Read user input files from the working directory
    Split1 <- readRDS("Split1.rds")
    Split2 <- readRDS("Split2.rds")
    Split1.ER <- readRDS("Split1.ER.rds")
    Split2.ER <- readRDS("Split2.ER.rds")
    
    # Define number of studies
    num.studies <- 2
    
    # --- Calculate effect size d for each study using getdF ---
    d.Split1     <- getdF(Split1, Split1.ER)
    
    # --- Adjust d values using dstar ---
    d.adj.Split1    <- dstar(d.Split1, length(Split1.ER))
    
    # --- Calculate variance of adjusted d using sigmad ---
    var.d.adj.Spli1 <- sigmad(d.adj.Split1, sum(Split1.ER==0), sum(Split1.ER==1))
    
    # Repeat for Split2
    d.Split2 <- getdF(Split2, Split2.ER)
    d.adj.Split2     <- dstar(d.Split2, length(Split2.ER))
    var.d.adj.Split2 <- sigmad(d.adj.Split2, sum(Split2.ER==0), sum(Split2.ER==1))
    
    # Combine means and variances
    mymns  <- cbind(d.adj.Split1, d.adj.Split2)
    myvars <- cbind(var.d.adj.Spli1,var.d.adj.Split2)
    
    # --- Compute Cochran's Q statistic using f.Q to test for ---
    my.Q   <- f.Q(mymns, myvars)
    
    # --- Fit Fixed Effects Model (FEM) using mu.tau2 and var.tau2 ---
    muFEM = mu.tau2(mymns, myvars)
    sdFEM = var.tau2(myvars)
    ZFEM = muFEM/sqrt(sdFEM)
    
    # --- Estimate between-study variance tau^2 using tau2.DL and ---
    my.tau2.DL<-tau2.DL(my.Q, num.studies, my.weights=1/myvars)
    myvarsDL <- myvars + my.tau2.DL
    muREM <- mu.tau2(mymns, myvarsDL)
    varREM <- var.tau2(myvarsDL)
    ZREM <- muREM/sqrt(varREM)
    
    # Save results to a CSV table
    results_df <- data.frame(
      d_adj_Split1 = d.adj.Split1,
      var_d_adj_Split1 = var.d.adj.Spli1,
      d_adj_Split2 = d.adj.Split2,
      var_d_adj_Split2 = var.d.adj.Split2,
      Q_stat = my.Q,
      mu_FEM = muFEM,
      sd_FEM = sdFEM,
      Z_FEM = ZFEM,
      tau2_DL = my.tau2.DL,
      mu_REM = muREM,
      var_REM = varREM,
      Z_REM = ZREM,
      row.names = rownames(mymns)
    )
    write.csv(results_df, "manual_meta_analysis_results.csv", row.names = TRUE)
    
    # Save results as an RDS object
    saveRDS(results_df, "manual_meta_analysis_results.rds")
    
    # Generate diagnostic and results plots
    pdf("manual_meta_analysis_plots.pdf", width = 10, height = 8)
    
    # Plot 1: Histogram of Q
    hist(my.Q, breaks=50, col="red", main="Histogram of Q", xlab="Q statistic")
    
    # Plot 2: QQ Plot of Q against Chi-square distribution
    chisqq <- qchisq(seq(0, .9999, .001), df=num.studies-1)
    tmp <- quantile(my.Q, seq(0, .9999, .001))
    qqplot(chisqq, tmp, ylab="Quantiles of Sample", pch="*",
           xlab="Quantiles of Chi square", main="QQ Plot of Q")
    lines(chisqq, chisqq, lty="dotted", col="red")
    
    # Plot 3: Normal QQ Plot of ZFEM
    qqnorm(ZFEM, pch="*", main="Normal Q-Q Plot (ZFEM)")
    qqline(ZFEM, col="red")
    
    # Plot 4: Comparison of muFEM and muREM
    plot(muFEM, muREM, pch=".", main="Comparison of muFEM and muREM", xlab="muFEM", ylab="muREM")
    abline(0, 1, col="red")
    
    # Plot 5: Histogram of tau
    hist(my.tau2.DL, col="red", breaks=50, main="Histogram of tau", xlab="tau2.DL")
    
    dev.off()

    writeLines(c(
        '"BIOC_GENEMETA_MANUAL_META_ANALYSIS":',
        paste0('    GeneMeta: ', as.character(packageVersion('GeneMeta')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_manual_meta_analysis.csv versions.yml
    """
}

workflow BIOC_GENEMETA_MANUAL_META_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Split1, Split2, Split1.ER, Split2.ER ] ]

    main:
    BIOC_GENEMETA_MANUAL_META_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_GENEMETA_MANUAL_META_ANALYSIS.out.tables
    plots    = BIOC_GENEMETA_MANUAL_META_ANALYSIS.out.plots
    objects  = BIOC_GENEMETA_MANUAL_META_ANALYSIS.out.objects
    versions = BIOC_GENEMETA_MANUAL_META_ANALYSIS.out.versions
}
