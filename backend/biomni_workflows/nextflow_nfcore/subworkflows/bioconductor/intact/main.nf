#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: INTACT — intact_integration_and_fdr
// Integrate TWAS scan z-scores and colocalization probabilities to compute posterior probabilities of gene causality, followed by Bayesian FDR control.
// Input: GLCP_vec, z_vec
// Container: quay.io/biocontainers/bioconductor-intact:1.10.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: INTACT
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Integrate TWAS and colocalization results using
//  * 2. [Core Analysis] Integrate TWAS and colocalization results using
//  * 3. [Core Analysis] Perform Bayesian FDR control on the posterior

nextflow.enable.dsl = 2

process BIOC_INTACT_INTACT_INTEGRATION_AND_FDR {
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
    .bm_deps <- c("INTACT")
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
    library(INTACT)
    
    # Helper function to read input vectors robustly from the working directory
    read_input_vector <- function(file_base) {
      if (file.exists(paste0(file_base, ".rds"))) {
        return(readRDS(paste0(file_base, ".rds")))
      } else if (file.exists(file_base)) {
        val <- tryCatch({
          readRDS(file_base)
        }, error = function(e) {
          NULL
        })
        if (!is.null(val)) return(val)
        
        val <- tryCatch({
          scan(file_base, quiet = TRUE)
        }, error = function(e) {
          NULL
        })
        if (!is.null(val)) return(val)
        
        val <- tryCatch({
          read.csv(file_base, header = FALSE)[[1]]
        }, error = function(e) {
          NULL
        })
        if (!is.null(val)) return(val)
        
        stop(paste("Could not parse file:", file_base))
      } else if (file.exists(paste0(file_base, ".txt"))) {
        return(scan(paste0(file_base, ".txt"), quiet = TRUE))
      } else if (file.exists(paste0(file_base, ".csv"))) {
        return(read.csv(paste0(file_base, ".csv"), header = FALSE)[[1]])
      } else {
        stop(paste("Input file not found for:", file_base))
      }
    }
    
    # Read user inputs
    GLCP_vec <- read_input_vector("GLCP_vec")
    z_vec <- read_input_vector("z_vec")
    
    # Ensure inputs are numeric vectors
    GLCP_vec <- as.numeric(GLCP_vec)
    z_vec <- as.numeric(z_vec)
    
    # --- Integrate TWAS and colocalization results using ---
    rst <- INTACT::intact(GLCP_vec=GLCP_vec, z_vec=z_vec)
    
    # --- Integrate TWAS and colocalization results using ---
    rst1 <- INTACT::intact(GLCP_vec=GLCP_vec, prior_fun=INTACT::expit, z_vec = z_vec, t = 0.02, D = 0.09)
    
    # --- Perform Bayesian FDR control on the posterior ---
    fdr_example <- fdr_rst(rst1, alpha = 0.05)
    
    # Write outputs to the working directory
    write.csv(data.frame(GLCP = GLCP_vec, z = z_vec, Posterior_Default = rst, Posterior_Expit = rst1), 
              file = "intact_posterior_probabilities.csv", row.names = FALSE)
    
    write.csv(fdr_example, file = "fdr_results.csv", row.names = FALSE)
    
    saveRDS(rst, file = "rst_default.rds")
    saveRDS(rst1, file = "rst_expit.rds")
    saveRDS(fdr_example, file = "fdr_results.rds")
    
    # Generate diagnostic plot
    pdf("intact_results_plot.pdf", width = 10, height = 5)
    par(mfrow = c(1, 2))
    hist(rst, main = "Posterior Probabilities (Default)", xlab = "Posterior Probability", col = "lightblue", border = "white")
    hist(rst1, main = "Posterior Probabilities (Expit)", xlab = "Posterior Probability", col = "salmon", border = "white")
    dev.off()

    writeLines(c(
        '"BIOC_INTACT_INTACT_INTEGRATION_AND_FDR":',
        paste0('    INTACT: ', as.character(packageVersion('INTACT')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_intact_integration_and_fdr.csv versions.yml
    """
}

workflow BIOC_INTACT_INTACT_INTEGRATION_AND_FDR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ GLCP_vec, z_vec ] ]

    main:
    BIOC_INTACT_INTACT_INTEGRATION_AND_FDR(ch_input)

    emit:
    tables   = BIOC_INTACT_INTACT_INTEGRATION_AND_FDR.out.tables
    plots    = BIOC_INTACT_INTACT_INTEGRATION_AND_FDR.out.plots
    objects  = BIOC_INTACT_INTACT_INTEGRATION_AND_FDR.out.objects
    versions = BIOC_INTACT_INTACT_INTEGRATION_AND_FDR.out.versions
}
