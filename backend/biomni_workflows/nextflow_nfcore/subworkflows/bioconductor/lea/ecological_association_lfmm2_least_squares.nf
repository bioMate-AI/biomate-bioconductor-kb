#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: LEA — ecological_association_lfmm2_least_squares
// Perform fast, exact genotype-environment association (GEA) tests using the frequentist least-squares LFMM2 algorithm.
// Input: Y, X
// Container: quay.io/biocontainers/bioconductor-lea:3.22.0--r45h01b2380_0
// R packages: LEA
// Bioconductor: 3.20 | R: 4.4
// Requires: LEA
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Fit the LFMM2 model (lfmm2) to estimate latent factors and loadings
//  * 2. [Core Analysis] Perform significance tests (lfmm2.test) using either linear models or joint Fisher's tests
//  * 3. [Visualization & Output] Plot p-values to identify candidate loci

nextflow.enable.dsl = 2

process BIOC_LEA_ECOLOGICAL_ASSOCIATION_LFMM2_LEAST_SQUARES {
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
    .bm_deps <- c("LEA")
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
            
    # Load required library
    library(LEA)
    
    # Helper function to robustly read input files (Y and X) from the working directory
    read_input <- function(name) {
      # Check for RDS format
      if (file.exists(paste0(name, ".rds"))) {
        return(readRDS(paste0(name, ".rds")))
      } else if (file.exists(name)) {
        # Try reading as RDS first, then fallback to table/csv
        val <- tryCatch({
          readRDS(name)
        }, error = function(e) {
          tryCatch({
            as.matrix(read.table(name, header = FALSE))
          }, error = function(e2) {
            as.matrix(read.csv(name, header = FALSE))
          })
        })
        return(val)
      } else if (file.exists(paste0(name, ".csv"))) {
        return(as.matrix(read.csv(paste0(name, ".csv"), header = FALSE)))
      } else if (file.exists(paste0(name, ".lfmm"))) {
        return(LEA::read.lfmm(paste0(name, ".lfmm")))
      } else if (file.exists(paste0(name, ".env"))) {
        return(LEA::read.env(paste0(name, ".env")))
      } else {
        stop(paste("Required input file for", name, "not found in the working directory."))
      }
    }
    
    # Read user inputs
    Y <- read_input("Y")
    X <- read_input("X")
    
    # Ensure inputs are matrices as required by lfmm2
    Y <- as.matrix(Y)
    X <- as.matrix(X)
    
    # Open PDF device to save plots
    pdf("lfmm2_analysis_plots.pdf", width = 8, height = 6)
    
    # ==========================================
    # DOCUMENTED CODE START
    # ==========================================
    
    # Estimate the number of latent factors (K) using PCA and Tracy-Widom test
    write.lfmm(Y, "temp_Y.lfmm")
    pc <- pca("temp_Y.lfmm", scale = TRUE)
    tw <- tracy.widom(pc)
    
    # Determine K as the number of significant principal components (p < 0.05)
    K <- sum(tw\$pvalues < 0.05, na.rm = TRUE)
    if (K < 1) {
      K <- 1
    }
    
    # Clean up PCA temporary files
    unlink(c("temp_Y.lfmm", "temp_Y.eigenvalues", "temp_Y.eigenvectors", "temp_Y.sdev", "temp_Y.projections"))
    
    # Fit LFMM2 with the estimated K
    mod.lfmm2 <- lfmm2(input = Y, env = X, K = K)
    
    # Plot the latent factors safely based on the value of K
    if (K >= 2) {
      plot(mod.lfmm2@U[, 1:2], col = "grey", pch = 19, 
           xlab = "Factor 1", 
           ylab = "Factor 2",
           main = paste("LFMM2 Latent Factors (K =", K, ")"))
    } else {
      plot(mod.lfmm2@U[, 1], col = "grey", pch = 19, 
           xlab = "Individual", 
           ylab = "Factor 1",
           main = paste("LFMM2 Latent Factors (K =", K, ")"))
    }
    
    # Perform the GEA significance test using the full model
    # full = TRUE returns a single p-value per locus even if X has >1 columns
    pv <- lfmm2.test(object = mod.lfmm2, 
                     input = Y, 
                     env = X, 
                     full = TRUE)
    
    plot(-log10(pv\$pvalues), col = "grey", cex = .5, pch = 19,
         main = "GEA Significance Test")
    abline(h = -log10(0.1/ncol(Y)), lty = 2, col = "orange")
    
    # ==========================================
    # DOCUMENTED CODE END
    # ==========================================
    
    # Close PDF device
    dev.off()
    
    # Save meaningful outputs to files dynamically named by K
    saveRDS(mod.lfmm2, paste0("mod_lfmm2_K", K, ".rds"))
    
    # Save the test p-values
    write.csv(data.frame(pvalue = pv\$pvalues), paste0("pvalues_K", K, "_full.csv"), row.names = FALSE)
    saveRDS(pv, paste0("pvalues_K", K, "_full.rds"))
    
    cat("Pipeline completed successfully. Outputs saved to working directory.\n")

    writeLines(c(
        '"BIOC_LEA_ECOLOGICAL_ASSOCIATION_LFMM2_LEAST_SQUARES":',
        paste0('    LEA: ', as.character(packageVersion('LEA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ecological_association_lfmm2_least_squares.csv versions.yml
    """
}

workflow BIOC_LEA_ECOLOGICAL_ASSOCIATION_LFMM2_LEAST_SQUARES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Y, X ] ]

    main:
    BIOC_LEA_ECOLOGICAL_ASSOCIATION_LFMM2_LEAST_SQUARES(ch_input)

    emit:
    tables   = BIOC_LEA_ECOLOGICAL_ASSOCIATION_LFMM2_LEAST_SQUARES.out.tables
    plots    = BIOC_LEA_ECOLOGICAL_ASSOCIATION_LFMM2_LEAST_SQUARES.out.plots
    objects  = BIOC_LEA_ECOLOGICAL_ASSOCIATION_LFMM2_LEAST_SQUARES.out.objects
    versions = BIOC_LEA_ECOLOGICAL_ASSOCIATION_LFMM2_LEAST_SQUARES.out.versions
}
