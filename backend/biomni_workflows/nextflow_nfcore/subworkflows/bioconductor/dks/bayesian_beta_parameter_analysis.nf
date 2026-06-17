#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: dks — bayesian_beta_parameter_analysis
// Calculate and plot the posterior distribution and credible set of the Beta hyperparameters for a set of null p-values from a single study.
// Input: P[,1]
// Container: quay.io/biocontainers/bioconductor-dks:1.56.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: cubature, dks
// Visualizations: image plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Calculate the posterior distribution of the Beta
//  * 2. [Visualization & Output] Plot the posterior distribution
//  * 3. [Visualization & Output] Calculate the credible set of the hyperparameters
//  * 4. [Visualization & Output] Plot the credible set

nextflow.enable.dsl = 2

process BIOC_DKS_BAYESIAN_BETA_PARAMETER_ANALYSIS {
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
    .bm_deps <- c("dks", "cubature")
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
    library(dks)
    library(cubature)
    
    # Read the input file from the working directory
    # We expect a file named "P.csv" or "P_col1.csv" containing the p-values.
    # We will format it as a matrix P so that P[,1] is accessible.
    if (file.exists("P.csv")) {
      P_raw <- read.csv("P.csv", header = FALSE)
      P <- as.matrix(P_raw)
    } else if (file.exists("P_col1.csv")) {
      P_raw <- read.csv("P_col1.csv", header = FALSE)
      P <- as.matrix(P_raw)
    } else {
      stop("Error: Input file 'P.csv' or 'P_col1.csv' not found in the working directory.")
    }
    
    # Ensure P is a matrix and has at least one column
    P <- as.matrix(P)
    if (ncol(P) < 1) {
      stop("Error: Input matrix P must have at least one column.")
    }
    
    # --- Calculate the posterior distribution of the Beta ---
    delta <- 0.1
    dist1 <- pprob.dist(P[,1])
    
    # --- Plot the posterior distribution ---
    alpha <- seq(0.1,10,by=delta)
    beta <- seq(0.1,10,by=delta)
    
    pdf("posterior_distribution.pdf", width = 7, height = 7)
    pprobImage = image(log10(alpha),log10(beta),dist1,xaxt="n",yaxt="n",xlab="Alpha",ylab="Beta")
    axis(1,at=c(-2,-1,0,1,2),labels=c("10^-2","10^-1","10^0","10^1","10^2"))
    axis(2,at=c(-2,-1,0,1,2),labels=c("10^-2","10^-1","10^0","10^1","10^2"))
    points(0,0,col="blue",cex=1,pch=19)	
    dev.off()
    
    # --- Calculate the credible set of the hyperparameters ---
    cred1 <- cred.set(dist1,delta=0.1, level=0.80)
    
    # --- Plot the credible set ---
    alpha <- seq(0.1,10,by=delta)
    beta <- seq(0.1,10,by=delta)
    
    pdf("credible_set.pdf", width = 7, height = 7)
    credImage=image(log10(alpha),log10(beta),cred1\$cred,xaxt="n",yaxt="n",xlab="Alpha",ylab="Beta")
    axis(1,at=c(-2,-1,0,1,2),labels=c("10^-2","10^-1","10^0","10^1","10^2"))
    axis(2,at=c(-2,-1,0,1,2),labels=c("10^-2","10^-1","10^0","10^1","10^2"))
    points(0,0,col="blue",cex=1,pch=19)
    dev.off()
    
    # Save meaningful results to files
    write.csv(dist1, file = "posterior_distribution.csv", row.names = FALSE)
    write.csv(cred1\$cred, file = "credible_set.csv", row.names = FALSE)
    saveRDS(dist1, file = "posterior_distribution.rds")
    saveRDS(cred1, file = "credible_set.rds")

    writeLines(c(
        '"BIOC_DKS_BAYESIAN_BETA_PARAMETER_ANALYSIS":',
        paste0('    dks: ', as.character(packageVersion('dks')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bayesian_beta_parameter_analysis.csv versions.yml
    """
}

workflow BIOC_DKS_BAYESIAN_BETA_PARAMETER_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ P[,1] ] ]

    main:
    BIOC_DKS_BAYESIAN_BETA_PARAMETER_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_DKS_BAYESIAN_BETA_PARAMETER_ANALYSIS.out.tables
    plots    = BIOC_DKS_BAYESIAN_BETA_PARAMETER_ANALYSIS.out.plots
    objects  = BIOC_DKS_BAYESIAN_BETA_PARAMETER_ANALYSIS.out.objects
    versions = BIOC_DKS_BAYESIAN_BETA_PARAMETER_ANALYSIS.out.versions
}
