#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GEWIST — snp_prioritization_known_effect
// Prioritize SNPs and perform interaction testing when the interaction effect size (theta_gc) is known or estimated.
// Input: GenoSet, Trait, COV, SNPset, theta_gc, theta_c
// Container: quay.io/biocontainers/bioconductor-gewist:1.54.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GEWIST, car
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Compute Levene's test p-values for all SNPs using car::leveneTest
//  * 2. [Core Analysis] Compute optimal variance prioritization p-value thresholds for each SNP using gewistLevene
//  * 3. [Core Analysis] Filter SNPs where Levene's p-value is less than the optimal threshold
//  * 4. [Core Analysis] Perform interaction testing on the prioritized SNPs using linear regression (lm)

nextflow.enable.dsl = 2

process BIOC_GEWIST_SNP_PRIORITIZATION_KNOWN_EFFECT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20-slim"

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
    .bm_deps <- c("GEWIST", "car")
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
    library(GEWIST)
    library(car)
    
    # ==========================================
    # 1. READ USER INPUT FILES
    # ==========================================
    
    # GenoSet: genotype matrix of m SNPs for n individuals (n rows, m columns)
    if (file.exists("GenoSet.csv")) {
      GenoSet <- as.matrix(read.csv("GenoSet.csv", row.names = 1, check.names = FALSE))
    } else if (file.exists("GenoSet.rds")) {
      GenoSet <- readRDS("GenoSet.rds")
    } else {
      stop("Error: GenoSet file (GenoSet.csv or GenoSet.rds) not found in the working directory.")
    }
    
    # Trait: quantitative phenotype vector of length n
    if (file.exists("Trait.csv")) {
      Trait <- read.csv("Trait.csv")[[1]]
    } else if (file.exists("Trait.rds")) {
      Trait <- readRDS("Trait.rds")
    } else {
      stop("Error: Trait file (Trait.csv or Trait.rds) not found in the working directory.")
    }
    
    # COV: covariate measurements vector of length n
    if (file.exists("COV.csv")) {
      COV <- read.csv("COV.csv")[[1]]
    } else if (file.exists("COV.rds")) {
      COV <- readRDS("COV.rds")
    } else {
      stop("Error: COV file (COV.csv or COV.rds) not found in the working directory.")
    }
    
    # SNPset: data frame containing SNP names and MAF values (m rows, 2 columns)
    if (file.exists("SNPset.csv")) {
      SNPset <- read.csv("SNPset.csv", header = TRUE)
    } else if (file.exists("SNPset.rds")) {
      SNPset <- readRDS("SNPset.rds")
    } else {
      stop("Error: SNPset file (SNPset.csv or SNPset.rds) not found in the working directory.")
    }
    
    # theta_gc: estimated variance explained by GxE interaction
    if (file.exists("theta_gc.txt")) {
      theta_gc <- as.numeric(readLines("theta_gc.txt", warn = FALSE)[1])
    } else if (file.exists("theta_gc.rds")) {
      theta_gc <- readRDS("theta_gc.rds")
    } else {
      stop("Error: theta_gc file (theta_gc.txt or theta_gc.rds) not found in the working directory.")
    }
    
    # theta_c: estimated variance explained by covariate
    if (file.exists("theta_c.txt")) {
      theta_c <- as.numeric(readLines("theta_c.txt", warn = FALSE)[1])
    } else if (file.exists("theta_c.rds")) {
      theta_c <- readRDS("theta_c.rds")
    } else {
      stop("Error: theta_c file (theta_c.txt or theta_c.rds) not found in the working directory.")
    }
    
    # ==========================================
    # Robustness Wrapper for gewistLevene
    # (Handles potential vignette typo where \$Optimal_pval is used instead of \$Optimal_pval_threshold)
    # ==========================================
    original_gewistLevene <- GEWIST::gewistLevene
    gewistLevene <- function(...) {
      res <- original_gewistLevene(...)
      if (!is.null(res) && is.null(res\$Optimal_pval) && !is.null(res\$Optimal_pval_threshold)) {
        res\$Optimal_pval <- res\$Optimal_pval_threshold
      }
      return(res)
    }
    
    # ==========================================
    # 2. EXECUTING DOCUMENTED WORKFLOW
    # ==========================================
    
    n  <- dim(GenoSet)[1]
    m <- dim(GenoSet)[2]
    
    library(car)
    
    levene_pval <- NA
    
    	for (i in 1: m) {
    		
    		levene_pval[i] <- leveneTest(Trait, as.factor(GenoSet[,i]),center = mean)[1,3]
    		
    			   }
    
    optimal_pval <- NA
    
    for ( i in 1: m){
    	
    optimal_pval[i] <- gewistLevene(p = SNPset[i,2], N = n, theta_gc = theta_gc, 
    theta_c = theta_c, M = m )\$Optimal_pval
    		
    			    }
    			    
    
    SNPind <- which(levene_pval < optimal_pval)
    
    # Use drop = FALSE to preserve matrix structure if only 1 SNP is prioritized
    Reduced <- GenoSet[,SNPind, drop = FALSE]
     
    intPval <- NA
     
    if (length(SNPind) > 0) {
     	for (j in 1: length(SNPind)) {
     
     		intPval[j] <- summary(lm(Trait~ Reduced[,j] * COV ))\$coef[4,4]
    		
     						}
    } else {
    	intPval <- numeric(0)
    	message("Warning: No SNPs were prioritized (Levene p-value < Optimal p-value threshold).")
    }
    
    # ==========================================
    # 3. WRITE OUTPUT FILES
    # ==========================================
    
    # Save comprehensive prioritization results
    prioritization_results <- data.frame(
      SNPname = SNPset[, 1],
      MAF = SNPset[, 2],
      Levene_Pval = levene_pval,
      Optimal_Threshold = optimal_pval,
      Prioritized = (levene_pval < optimal_pval)
    )
    write.csv(prioritization_results, "prioritization_results.csv", row.names = FALSE)
    
    # Save interaction testing results for prioritized SNPs
    if (length(SNPind) > 0) {
      interaction_results <- data.frame(
        SNPname = SNPset[SNPind, 1],
        MAF = SNPset[SNPind, 2],
        Levene_Pval = levene_pval[SNPind],
        Optimal_Threshold = optimal_pval[SNPind],
        Interaction_Pval = intPval
      )
    } else {
      interaction_results <- data.frame(
        SNPname = character(0),
        MAF = numeric(0),
        Levene_Pval = numeric(0),
        Optimal_Threshold = numeric(0),
        Interaction_Pval = numeric(0)
      )
    }
    write.csv(interaction_results, "interaction_results.csv", row.names = FALSE)
    
    # Save R objects for downstream analysis
    saveRDS(list(
      levene_pval = levene_pval,
      optimal_pval = optimal_pval,
      SNPind = SNPind,
      intPval = intPval,
      prioritization_results = prioritization_results,
      interaction_results = interaction_results
    ), "gewist_pipeline_outputs.rds")
    
    # Generate diagnostic plot
    pdf("gewist_prioritization_plot.pdf", width = 7, height = 6)
    plot(levene_pval, optimal_pval, 
         xlab = "Levene's Test P-value", 
         ylab = "Optimal VP P-value Threshold",
         main = "SNP Prioritization (GEWIST)",
         pch = 20, col = ifelse(levene_pval < optimal_pval, "red", "black"))
    abline(a = 0, b = 1, lty = 2, col = "blue")
    legend("topleft", legend = c("Prioritized SNPs", "Non-prioritized SNPs"), 
           col = c("red", "black"), pch = 20)
    dev.off()
    
    message("Pipeline completed successfully. Outputs written to 'prioritization_results.csv', 'interaction_results.csv', 'gewist_pipeline_outputs.rds', and 'gewist_prioritization_plot.pdf'.")

    writeLines(c(
        '"BIOC_GEWIST_SNP_PRIORITIZATION_KNOWN_EFFECT":',
        paste0('    GEWIST: ', as.character(packageVersion('GEWIST')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_snp_prioritization_known_effect.csv versions.yml
    """
}

workflow BIOC_GEWIST_SNP_PRIORITIZATION_KNOWN_EFFECT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ GenoSet, Trait, COV, SNPset, theta_gc, theta_c ] ]

    main:
    BIOC_GEWIST_SNP_PRIORITIZATION_KNOWN_EFFECT(ch_input)

    emit:
    tables   = BIOC_GEWIST_SNP_PRIORITIZATION_KNOWN_EFFECT.out.tables
    plots    = BIOC_GEWIST_SNP_PRIORITIZATION_KNOWN_EFFECT.out.plots
    objects  = BIOC_GEWIST_SNP_PRIORITIZATION_KNOWN_EFFECT.out.objects
    versions = BIOC_GEWIST_SNP_PRIORITIZATION_KNOWN_EFFECT.out.versions
}
