#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: qsvaR — qsv_degradation_correction
// Identify and extract quality surrogate variables (qSVs) to correct for bench degradation in postmortem brain RNA-seq data, and perform degradation-corrected dif
// Input: rse_tx
// Container: quay.io/biocontainers/bioconductor-qsvar:1.14.0--r45hdfd78af_0
// R packages: SummarizedExperiment, BiocFileCache, ggplot2, knitr, limma, qsvaR, refmanager, rmarkdown
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, ggplot2, limma, qsvaR, sva
// Visualizations: box plot
// QC: batch-effect correction
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter the input RangedSummarizedExperiment for minimum expression and relevant samples
//  * 2. [Core Analysis] Extract degradation-associated transcripts using getDegTx() and select_transcripts()
//  * 3. [Core Analysis] Compute principal components of the degraded transcripts using getPCs()
//  * 4. [Input & Preparation] Define the experimental design matrix and calculate the optimal number of PCs (k) using k_qsvs()
//  * 5. [Core Analysis] Extract the final qSV matrix using get_qsvs() (or perform steps 2-5 in one step using the wrapper function qSVA())
//  * 6. [Core Analysis] Perform differential expression analysis using limma by appending the qSVs to the design matrix
//  * 7. [Visualization & Output] Evaluate the correction quality by plotting t-statistics against degradation t-statistics using DEqual()

nextflow.enable.dsl = 2

process BIOC_QSVAR_QSV_DEGRADATION_CORRECTION {
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
    .bm_deps <- c("SummarizedExperiment", "BiocFileCache", "ggplot2", "knitr", "limma", "qsvaR", "refmanager", "rmarkdown")
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
        library("qsvaR")
        library("limma")
        library("SummarizedExperiment")
        library("ggplot2")
        
        # -----------------------------------------------------------------------------
        # Stage 1: Load and Filter Input Data
        # -----------------------------------------------------------------------------
        
        # Read the user-provided RangedSummarizedExperiment object
        if (file.exists("rse_tx")) {
            rse_tx <- readRDS("rse_tx")
        } else if (file.exists("rse_tx.rds")) {
            rse_tx <- readRDS("rse_tx.rds")
        } else if (file.exists("rse_tx.RData")) {
            env <- new.env()
            load("rse_tx.RData", envir = env)
            if ("rse_tx" %in% names(env)) {
                rse_tx <- env\$rse_tx
            } else {
                stop("Loaded RData file but 'rse_tx' object was not found.")
            }
        } else {
            stop("Error: Input file 'rse_tx' (RDS or RData format) not found in the working directory.")
        }
        
        # Filter the input RangedSummarizedExperiment for minimum expression and relevant samples
        # Keep only adult samples (Age > 17) if the Age column exists, and apply minimum expression cutoff (TPM > 0.3)
        if ("Age" %in% colnames(colData(rse_tx))) {
            rse_tx <- rse_tx[, rse_tx\$Age > 17]
        }
        rse_tx <- rse_tx[rowMeans(assays(rse_tx)\$tpm) > 0.3, ]
        
        # -----------------------------------------------------------------------------
        # Stage 2: Extract Degradation-Associated Transcripts
        # -----------------------------------------------------------------------------
        
        # Obtain transcripts with degradation signature
        DegTx <- getDegTx(
          rse_tx, sig_transcripts = select_transcripts(cell_component = TRUE)
        )
        dim(DegTx)
        
        # -----------------------------------------------------------------------------
        # Stage 3: Compute Principal Components of Degraded Transcripts
        # -----------------------------------------------------------------------------
        
        pcTx <- getPCs(rse_tx = DegTx, assayname = "tpm")
        
        # -----------------------------------------------------------------------------
        # Stage 4: Define Experimental Design and Calculate Optimal Number of PCs (k)
        # -----------------------------------------------------------------------------
        
        # Design a basic model matrix to model the number of PCs needed
        # Dynamically select available metadata columns to avoid hardcoding errors
        expected_cols <- c("Dx", "Age", "Sex", "Race", "Region")
        present_cols <- intersect(expected_cols, colnames(colData(rse_tx)))
        
        if (length(present_cols) > 0) {
            formula_str <- paste("~", paste(present_cols, collapse = " + "))
            mod <- model.matrix(as.formula(formula_str), data = as.data.frame(colData(rse_tx)))
        } else if (ncol(colData(rse_tx)) > 0) {
            formula_str <- paste("~", colnames(colData(rse_tx))[1])
            mod <- model.matrix(as.formula(formula_str), data = as.data.frame(colData(rse_tx)))
        } else {
            mod <- model.matrix(~ 1, data = as.data.frame(colData(rse_tx)))
        }
        
        # Set random seed for reproducibility (internally calls sva::num.sv())
        set.seed(20230621)
        
        # Use k_qsvs function to return an integer of PCs needed
        k <- k_qsvs(rse_tx = DegTx, mod = mod, assayname = "tpm")
        print(k)
        
        # -----------------------------------------------------------------------------
        # Stage 5: Extract Final qSV Matrix
        # -----------------------------------------------------------------------------
        
        # get_qsvs uses k to subset our PCA analysis
        qsvs <- get_qsvs(qsvPCs = pcTx, k = k)
        dim(qsvs)
        
        # Set random seed again for the wrapper function
        set.seed(20230621)
        
        # Example use of the wrapper function qSVA() to verify consistency
        qsvs_wrapper <- qSVA(
            rse_tx = rse_tx,
            sig_transcripts = select_transcripts(cell_component = TRUE),
            mod = mod, 
            assayname = "tpm"
        )
        dim(qsvs_wrapper)
        
        # Save the extracted qSVs
        write.csv(as.data.frame(qsvs), "qsvs.csv", row.names = TRUE)
        saveRDS(qsvs, "qsvs.rds")
        
        # -----------------------------------------------------------------------------
        # Stage 6: Differential Expression Analysis with and without qSVs
        # -----------------------------------------------------------------------------
        
        # --- DE with qSVs ---
        # Create a model.matrix with demographic info and qsvs
        mod_qSVA <- cbind(mod, qsvs)
        
        # Log transform transcript expression
        txExprs <- log2(assays(rse_tx)\$tpm + 1)
        
        # Linear model differential expression
        fitTx <- lmFit(txExprs, mod_qSVA)
        
        # Generate empirical Bayes for DE
        eBTx <- eBayes(fitTx)
        
        # Get DE results table (fallback to coef=1 if model matrix lacks covariates)
        coef_idx <- if (ncol(mod_qSVA) >= 2) 2 else 1
        sigTx <- topTable(eBTx,
            coef = coef_idx,
            p.value = 1, number = nrow(rse_tx)
        )
        head(sigTx)
        write.csv(sigTx, "sigTx_with_qSVs.csv", row.names = TRUE)
        
        # --- DE without qSVs ---
        # Log transform transcript expression
        txExprs_noqsv <- log2(assays(rse_tx)\$tpm + 1)
        
        # Linear model differential expression with generic model
        fitTx_noqsv <- lmFit(txExprs_noqsv, mod)
        
        # Generate empirical Bayes for DE
        eBTx_noqsv <- eBayes(fitTx_noqsv)
        
        # Get DE results table
        coef_idx_noqsv <- if (ncol(mod) >= 2) 2 else 1
        sigTx_noqsv <- topTable(eBTx_noqsv,
            coef = coef_idx_noqsv,
            p.value = 1, number = nrow(rse_tx)
        )
        head(sigTx_noqsv)
        write.csv(sigTx_noqsv, "sigTx_no_qSVs.csv", row.names = TRUE)
        
        # -----------------------------------------------------------------------------
        # Stage 7: Evaluate Correction Quality and Generate Plots
        # -----------------------------------------------------------------------------
        
        # Subset the topTable() results to keep just the t-statistic
        DE_noqsv <- data.frame(t = sigTx_noqsv\$t, row.names = rownames(sigTx_noqsv))
        DE <- data.frame(t = sigTx\$t, row.names = rownames(sigTx))
        
        # Generate and save DEqual plots
        pdf("DEqual_plots.pdf", width = 10, height = 5)
        print(DEqual(DE_noqsv) + ggtitle("Without qSVs"))
        print(DEqual(DE) + ggtitle("With qSVs"))
        dev.off()
        
        # Visualize the expression of the most significant gene using boxplots
        yy <- txExprs[rownames(txExprs) == rownames(sigTx)[1], ]
        
        # Dynamically select grouping variable for the boxplot
        if ("Dx" %in% colnames(colData(rse_tx))) {
            group_var <- colData(rse_tx)\$Dx
        } else if (ncol(colData(rse_tx)) > 0) {
            group_var <- colData(rse_tx)[[1]]
        } else {
            group_var <- rep("Sample", ncol(rse_tx))
        }
        
        pdf("most_significant_gene_boxplot.pdf", width = 6, height = 6)
        boxplot(yy ~ group_var,
            outline = FALSE,
            ylim = range(yy), ylab = "log2 Exprs", xlab = "",
            main = paste(rownames(sigTx)[1])
        )
        dev.off()
        
        message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_QSVAR_QSV_DEGRADATION_CORRECTION":',
        paste0('    qsvaR: ', as.character(packageVersion('qsvaR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_qsv_degradation_correction.csv versions.yml
    """
}

workflow BIOC_QSVAR_QSV_DEGRADATION_CORRECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ rse_tx ] ]

    main:
    BIOC_QSVAR_QSV_DEGRADATION_CORRECTION(ch_input)

    emit:
    tables   = BIOC_QSVAR_QSV_DEGRADATION_CORRECTION.out.tables
    plots    = BIOC_QSVAR_QSV_DEGRADATION_CORRECTION.out.plots
    objects  = BIOC_QSVAR_QSV_DEGRADATION_CORRECTION.out.objects
    versions = BIOC_QSVAR_QSV_DEGRADATION_CORRECTION.out.versions
}
