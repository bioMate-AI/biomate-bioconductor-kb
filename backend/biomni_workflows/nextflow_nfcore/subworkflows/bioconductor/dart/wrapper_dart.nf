#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DART — wrapper_dart
// Run the complete DART or clique-based DART pipeline using wrapper functions for rapid activity score estimation.
// Input: vdx.data, modelSig, mainz.data
// Container: quay.io/biocontainers/bioconductor-dart:1.58.0--r45hdfd78af_0
// R packages: DART
// Bioconductor: 3.20 | R: 4.4
// Requires: DART
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run standard DART wrapper using DoDART
//  * 2. [Core Analysis] Run enhanced clique-based DART wrapper using DoDARTCLQ
//  * 3. [Core Analysis] Predict activity in an independent dataset using PredActScore with the clique network

nextflow.enable.dsl = 2

process BIOC_DART_WRAPPER_DART {
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
    .bm_deps <- c("DART")
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
    library(DART)
    
    # Helper function to robustly read the user input files
    read_input <- function(filename) {
      # Check if RDS version exists
      if (file.exists(paste0(filename, ".rds"))) {
        return(readRDS(paste0(filename, ".rds")))
      } else if (file.exists(filename)) {
        # Try reading as RDS first
        obj <- tryCatch(readRDS(filename), error = function(e) NULL)
        if (!is.null(obj)) return(obj)
        
        # Try reading as a table (CSV/TSV)
        df <- tryCatch({
          read.table(filename, header = TRUE, row.names = 1, sep = "", check.names = FALSE)
        }, error = function(e) {
          read.csv(filename, header = TRUE, row.names = 1, check.names = FALSE)
        })
        
        # If it's a single column, it might be a named vector (like modelSig)
        if (ncol(df) == 1) {
          vec <- df[[1]]
          names(vec) <- rownames(df)
          return(vec)
        } else if (ncol(df) == 0) {
          # Maybe it's a vector stored as a single column without header
          vec <- readLines(filename)
          # Try to parse as named vector if it has names
          # Otherwise return as is
          return(vec)
        }
        return(as.matrix(df))
      } else {
        stop(paste("Required input file missing:", filename))
      }
    }
    
    # 1. Read User Inputs
    vdx.data <- read_input("vdx.data")
    modelSig <- read_input("modelSig")
    mainz.data <- read_input("mainz.data")
    
    # Ensure correct data types
    if (!is.matrix(vdx.data)) vdx.data <- as.matrix(vdx.data)
    if (!is.matrix(mainz.data)) mainz.data <- as.matrix(mainz.data)
    if (!is.numeric(modelSig)) modelSig <- as.numeric(modelSig)
    
    # 2. Run standard DART wrapper using DoDART
    res.vdx <- DoDART(vdx.data, modelSig, fdr=0.000001)
    
    # 3. Run enhanced clique-based DART wrapper using DoDARTCLQ
    res2.vdx <- DoDARTCLQ(vdx.data, modelSig, fdr=0.000001)
    
    # 4. Predict activity in an independent dataset using PredActScore with the clique network
    pred.mainz2.o <- PredActScore(res2.vdx\$clq, mainz.data)
    
    # 5. Save meaningful results to output files
    # Save RDS objects for downstream R analysis
    saveRDS(res.vdx, "res_vdx.rds")
    saveRDS(res2.vdx, "res2_vdx.rds")
    saveRDS(pred.mainz2.o, "pred_mainz2_o.rds")
    
    # Save CSV tables of the activity scores
    write.csv(data.frame(SampleID = names(res.vdx\$score), Standard_DART_Score = res.vdx\$score), 
              "standard_dart_scores.csv", row.names = FALSE)
    
    write.csv(data.frame(SampleID = names(res2.vdx\$pred), Clique_DART_Score = res2.vdx\$pred), 
              "clique_dart_scores.csv", row.names = FALSE)
    
    write.csv(data.frame(SampleID = names(pred.mainz2.o\$score), Predicted_Mainz_Score = pred.mainz2.o\$score), 
              "predicted_mainz_clique_scores.csv", row.names = FALSE)
    
    # Generate diagnostic plots of the activity scores
    pdf("dart_activity_scores_distribution.pdf", width = 10, height = 5)
    par(mfrow = c(1, 3))
    
    # Plot 1: Standard DART Scores
    hist(res.vdx\$score, main = "Standard DART Scores (VDX)", 
         xlab = "Activity Score", col = "skyblue", border = "white")
    
    # Plot 2: Clique-based DART Scores
    hist(res2.vdx\$pred, main = "Clique DART Scores (VDX)", 
         xlab = "Activity Score", col = "lightgreen", border = "white")
    
    # Plot 3: Predicted Mainz Scores
    hist(pred.mainz2.o\$score, main = "Predicted Scores (Mainz)", 
         xlab = "Activity Score", col = "salmon", border = "white")
    
    dev.off()
    
    cat("DART pipeline completed successfully. Outputs saved to working directory.\n")

    writeLines(c(
        '"BIOC_DART_WRAPPER_DART":',
        paste0('    DART: ', as.character(packageVersion('DART')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_wrapper_dart.csv versions.yml
    """
}

workflow BIOC_DART_WRAPPER_DART_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ vdx.data, modelSig, mainz.data ] ]

    main:
    BIOC_DART_WRAPPER_DART(ch_input)

    emit:
    tables   = BIOC_DART_WRAPPER_DART.out.tables
    plots    = BIOC_DART_WRAPPER_DART.out.plots
    objects  = BIOC_DART_WRAPPER_DART.out.objects
    versions = BIOC_DART_WRAPPER_DART.out.versions
}
