#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: TOAST — reference_free_deconvolution
// Estimate cell type proportions from bulk high-throughput data without a reference panel, optionally improving marker selection via cross-cell type differential 
// Input: Y_raw, K
// Container: quay.io/biocontainers/bioconductor-toast:1.24.0--r45hdfd78af_0
// R packages: TOAST
// Bioconductor: 3.20 | R: 4.4
// Requires: EpiDISH, TOAST, gplots
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Select the most variable features using findRefinx()
//  * 2. [Core Analysis] Subset the bulk data to the selected features
//  * 3. [Core Analysis] Perform reference-free deconvolution
//  * 4. [Core Analysis] Align estimated cell types to a reference (if available)

nextflow.enable.dsl = 2

process BIOC_TOAST_REFERENCE_FREE_DECONVOLUTION {
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
    .bm_deps <- c("TOAST")
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
    library(TOAST)
    
    # ==========================================
    # 1. READ USER INPUT FILES
    # ==========================================
    
    # Read Y_raw (matrix or SummarizedExperiment of bulk high-throughput data)
    if (file.exists("Y_raw.rds")) {
      Y_raw <- readRDS("Y_raw.rds")
    } else if (file.exists("Y_raw.csv")) {
      Y_raw <- as.matrix(read.csv("Y_raw.csv", row.names = 1))
    } else if (file.exists("Y_raw.tsv")) {
      Y_raw <- as.matrix(read.delim("Y_raw.tsv", row.names = 1))
    } else {
      stop("Error: Y_raw file (Y_raw.rds, Y_raw.csv, or Y_raw.tsv) not found in the working directory.")
    }
    
    # Read K (integer, number of cell types)
    if (file.exists("K.rds")) {
      K <- readRDS("K.rds")
    } else if (file.exists("K.txt")) {
      K <- as.integer(readLines("K.txt", warn = FALSE)[1])
    } else {
      stop("Error: K file (K.rds or K.txt) not found in the working directory.")
    }
    
    # Optionally read reference proportions (estProp_RB) if available for alignment
    estProp_RB <- NULL
    if (file.exists("estProp_RB.rds")) {
      estProp_RB <- readRDS("estProp_RB.rds")
    } else if (file.exists("estProp_RB.csv")) {
      estProp_RB <- as.matrix(read.csv("estProp_RB.csv", row.names = 1))
    } else if (file.exists("Blood_ref.rds") || file.exists("Blood_ref.csv")) {
      # If Blood_ref is provided instead, we can compute estProp_RB using EpiDISH
      Blood_ref <- if (file.exists("Blood_ref.rds")) {
        readRDS("Blood_ref.rds")
      } else {
        as.matrix(read.csv("Blood_ref.csv", row.names = 1))
      }
      
      refinx_rb <- findRefinx(Y_raw, nmarker = min(1000, nrow(Y_raw)))
      Y_rb <- Y_raw[refinx_rb, ]
      common_features <- intersect(rownames(Y_rb), rownames(Blood_ref))
      
      if (length(common_features) > 0 && requireNamespace("EpiDISH", quietly = TRUE)) {
        Y_rb <- Y_rb[common_features, ]
        Ref <- as.matrix(Blood_ref[common_features, ])
        outT_rb <- EpiDISH::epidish(beta.m = Y_rb, ref.m = Ref, method = "RPC")
        estProp_RB <- outT_rb\$estF
      }
    }
    
    # ==========================================
    # 2. WORKFLOW: REFERENCE-FREE DECONVOLUTION
    # ==========================================
    
    # --- Select the most variable features using findRefinx() ---
    nmarker_val <- min(1000, nrow(Y_raw))
    refinx <- findRefinx(Y_raw, nmarker = nmarker_val)
    
    # --- Subset the bulk data to the selected features ---
    Y <- Y_raw[refinx,]
    
    # --- Perform reference-free deconvolution ---
    # 3a. Standard reference-free deconvolution using myRefFreeCellMix()
    outT <- myRefFreeCellMix(Y, mu0=myRefFreeCellMixInitialize(Y, K = K))
    estProp_RF <- outT\$Omega
    
    # --- Align estimated cell types to a reference (if available) ---
    if (!is.null(estProp_RB)) {
      estProp_RF <- assignCellType(input=estProp_RF, reference=estProp_RB)
    } else {
      message("Reference proportions (estProp_RB) not available. Skipping alignment for estProp_RF.")
    }
    
    # 3b. Improve reference-free deconvolution with csDeconv() wrapper
    outRF1 <- csDeconv(Y_raw, K, TotalIter = 30, bound_negative = TRUE)
    
    # Stage 4 (improved): Align improved estimated cell types to a reference (if available)
    if (!is.null(estProp_RB)) {
      estProp_RF_improved <- assignCellType(input=outRF1\$estProp, reference=estProp_RB)
    } else {
      message("Reference proportions (estProp_RB) not available. Skipping alignment for estProp_RF_improved.")
      estProp_RF_improved <- outRF1\$estProp
    }
    
    # ==========================================
    # 3. WRITE OUTPUT FILES
    # ==========================================
    
    # Save standard reference-free proportions
    write.csv(estProp_RF, file = "estProp_RF.csv", row.names = TRUE)
    saveRDS(estProp_RF, file = "estProp_RF.rds")
    
    # Save improved reference-free proportions
    write.csv(estProp_RF_improved, file = "estProp_RF_improved.csv", row.names = TRUE)
    saveRDS(estProp_RF_improved, file = "estProp_RF_improved.rds")
    
    # Save full csDeconv output object
    saveRDS(outRF1, file = "outRF1_csDeconv.rds")
    
    # Generate a diagnostic plot of the estimated proportions
    pdf("estimated_proportions_heatmap.pdf", width = 8, height = 6)
    if (requireNamespace("gplots", quietly = TRUE)) {
      gplots::heatmap.2(as.matrix(estProp_RF_improved), 
                        trace = "none", 
                        margins = c(10, 10), 
                        main = "Improved RF Proportions")
    } else {
      heatmap(as.matrix(estProp_RF_improved), 
              margins = c(10, 10), 
              main = "Improved RF Proportions")
    }
    dev.off()
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_TOAST_REFERENCE_FREE_DECONVOLUTION":',
        paste0('    TOAST: ', as.character(packageVersion('TOAST')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_reference_free_deconvolution.csv versions.yml
    """
}

workflow BIOC_TOAST_REFERENCE_FREE_DECONVOLUTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Y_raw, K ] ]

    main:
    BIOC_TOAST_REFERENCE_FREE_DECONVOLUTION(ch_input)

    emit:
    tables   = BIOC_TOAST_REFERENCE_FREE_DECONVOLUTION.out.tables
    plots    = BIOC_TOAST_REFERENCE_FREE_DECONVOLUTION.out.plots
    objects  = BIOC_TOAST_REFERENCE_FREE_DECONVOLUTION.out.objects
    versions = BIOC_TOAST_REFERENCE_FREE_DECONVOLUTION.out.versions
}
